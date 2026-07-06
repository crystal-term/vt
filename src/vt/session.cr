require "./keys"
require "./pty"
require "./screen"

module Term::VT
  class TimeoutError < Exception
  end

  class Session
    DEFAULT_DEADLINE = 5.seconds
    POLL_INTERVAL    = 5.milliseconds
    CTTY_RUNG        = 2
    CTTY_STRATEGY    = "setsid/TIOCSCTTY shim"

    getter pty : PTY
    getter process : Process

    @screen : Screen
    @mutex : Mutex
    @updates : Channel(Nil)
    @changes : UInt64
    @exit_status : Process::Status?
    @closed : Bool

    private def initialize(@pty : PTY, @process : Process, @screen : Screen)
      @mutex = Mutex.new
      @updates = Channel(Nil).new(1)
      @changes = 0_u64
      @exit_status = nil
      @closed = false
      @pty.attach_child_pgid(@process.pid)
      @screen.on_report = ->(bytes : Bytes) { write_report(bytes) }
      start_waiter
      start_reader
    end

    def self.spawn(
      command : String,
      args : Enumerable(String) = [] of String,
      *,
      rows : Int32 = 24,
      cols : Int32 = 80,
      env : Process::Env = nil,
      clear_env : Bool = false,
      chdir : Path | String? = nil,
    ) : self
      pty = PTY.open(rows: rows, cols: cols)
      argv = args.to_a

      begin
        process = CTTYShim.spawn(command, argv, pty, env, clear_env, chdir)
        pty.slave.close
        new(pty, process, Screen.new(rows: rows, cols: cols))
      rescue ex
        pty.close
        raise ex
      end
    end

    def send(data : String | Bytes) : self
      bytes = data.is_a?(String) ? data.to_slice : data
      @pty.master.write(bytes)
      @pty.master.flush
      self
    end

    def press(name : Symbol) : self
      send(Keys.sequence(name))
    end

    def type(text : String, delay : Time::Span = Time::Span.zero) : self
      if delay <= Time::Span.zero
        send(text)
      else
        chars = text.chars
        chars.each_with_index do |char, index|
          send(char.to_s)
          wait_duration(delay) if index < chars.size - 1
        end
      end

      self
    end

    def screen : Screen
      @mutex.synchronize { @screen.dup.tap { |copy| copy.on_report = nil } }
    end

    def resize(rows : Int32, cols : Int32) : self
      @pty.resize(rows, cols)
      @mutex.synchronize do
        @screen.resize(rows, cols)
        @changes &+= 1
      end
      notify_update
      self
    end

    def wait_for(text : String, deadline : Time::Span = DEFAULT_DEADLINE) : self
      wait_for(deadline: deadline) { |screen| screen.contains?(text) }
    rescue ex : TimeoutError
      raise TimeoutError.new("timed out waiting for #{text.inspect} after #{deadline}\n\n#{screen_snapshot_for_error}")
    end

    def wait_for(deadline : Time::Span = DEFAULT_DEADLINE, &block : Screen -> Bool) : self
      limit = Time.instant + deadline

      until Time.instant >= limit
        return self if @mutex.synchronize { yield @screen }
        wait_for_update(limit)
      end

      raise TimeoutError.new("timed out waiting for screen condition after #{deadline}\n\n#{screen_snapshot_for_error}")
    end

    def wait_idle(settle : Time::Span = 50.milliseconds, deadline : Time::Span = DEFAULT_DEADLINE) : self
      limit = Time.instant + deadline
      idle_since = Time.instant
      last_change = change_count

      loop do
        now = Time.instant
        raise TimeoutError.new("timed out waiting for idle screen after #{deadline}\n\n#{screen_snapshot_for_error}") if now >= limit

        current_change = change_count
        if current_change != last_change
          last_change = current_change
          idle_since = now
        end

        return self if now - idle_since >= settle

        next_wake = idle_since + settle
        wait_for_update({limit, next_wake}.min)
      end
    end

    def wait_exit(deadline : Time::Span = 10.seconds) : Process::Status
      limit = Time.instant + deadline

      until Time.instant >= limit
        if status = exit_status
          return status
        end

        wait_for_update(limit)
      end

      raise TimeoutError.new("timed out waiting for process exit after #{deadline}\n\n#{screen_snapshot_for_error}")
    end

    def close : Nil
      return if @closed

      @closed = true
      unless exit_status
        signal_process_group(Signal::HUP)
        begin
          wait_exit(deadline: 250.milliseconds)
        rescue TimeoutError
          signal_process_group(Signal::KILL)
          begin
            wait_exit(deadline: 2.seconds)
          rescue TimeoutError
          end
        end
      end
    ensure
      @pty.close
    end

    private def start_reader : Nil
      spawn do
        buffer = Bytes.new(4096)

        loop do
          count = @pty.master.read(buffer)
          break if count == 0

          @mutex.synchronize do
            @screen.feed(buffer[0, count])
            @changes &+= 1
          end
          notify_update
        end
      rescue IO::Error
      ensure
        notify_update
      end
    end

    private def start_waiter : Nil
      spawn do
        status = @process.wait
        @mutex.synchronize { @exit_status = status }
      ensure
        notify_update
      end
    end

    private def wait_for_update(limit) : Nil
      remaining = limit - Time.instant
      return if remaining <= Time::Span.zero

      timeout = remaining < POLL_INTERVAL ? remaining : POLL_INTERVAL
      select
      when @updates.receive
      when timeout(timeout)
      end
    end

    private def wait_duration(duration : Time::Span) : Nil
      return if duration <= Time::Span.zero

      select
      when timeout(duration)
      end
    end

    private def write_report(bytes : Bytes) : Nil
      @pty.master.write(bytes)
      @pty.master.flush
    rescue IO::Error
    end

    private def notify_update : Nil
      select
      when @updates.send(nil)
      else
      end
    end

    private def change_count : UInt64
      @mutex.synchronize { @changes }
    end

    private def exit_status : Process::Status?
      @mutex.synchronize { @exit_status }
    end

    private def screen_snapshot_for_error : String
      "Screen snapshot:\n#{@mutex.synchronize { @screen.snapshot }}"
    end

    private def signal_process_group(signal : Signal) : Nil
      Process.signal(signal, -@process.pid.to_i)
    rescue RuntimeError
      begin
        @process.signal(signal)
      rescue RuntimeError
      end
    end

    private module CTTYShim
      SHARD_ROOT = File.expand_path("../..", __DIR__)
      SOURCE     = File.join(__DIR__, "ctty_exec.c")
      HELPER     = File.join(SHARD_ROOT, ".term-vt", "bin", "vt-ctty")

      @@build_lock = Mutex.new

      def self.spawn(
        command : String,
        args : Array(String),
        pty : PTY,
        env : Process::Env,
        clear_env : Bool,
        chdir : Path | String?,
      ) : Process
        helper = ensure_helper
        Process.new(
          helper,
          [command] + args,
          env: env,
          clear_env: clear_env,
          input: pty.slave,
          output: pty.slave,
          error: pty.slave,
          chdir: chdir
        )
      rescue ex : File::Error
        raise PTYUnavailable.new(ex.message || "ctty helper unavailable")
      end

      private def self.ensure_helper : String
        @@build_lock.synchronize { build_helper }
      end

      private def self.build_helper : String
        return HELPER if File.exists?(HELPER)

        Dir.mkdir_p(File.dirname(HELPER))
        # Build to a process-unique path and rename so concurrent spawns
        # never observe (or clobber) a half-written helper binary.
        staging = "#{HELPER}.#{Process.pid}.tmp"
        output = IO::Memory.new
        error = IO::Memory.new
        status = Process.run("cc", [SOURCE, "-o", staging], output: output, error: error)
        unless status.success?
          File.delete?(staging)
          message = error.to_s.empty? ? output.to_s : error.to_s
          raise PTYUnavailable.new("failed to build vt-ctty helper: #{message}")
        end

        File.rename(staging, HELPER)
        HELPER
      rescue ex : File::Error
        raise PTYUnavailable.new(ex.message || "failed to build vt-ctty helper")
      end
    end
  end
end
