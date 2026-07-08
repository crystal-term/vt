require "../term-vt"
require "./options"
require "./tape"

module Term::VT::CLI
  class Failure < Exception
    getter snapshot : String?
    getter line : Int32?

    def initialize(message : String, @snapshot : String? = nil, @line : Int32? = nil)
      super(@line ? "line #{@line}: #{message}" : message)
    end
  end

  class Runner
    EXIT_DRAIN_SETTLE   = 20.milliseconds
    EXIT_DRAIN_DEADLINE = 500.milliseconds
    SEND_EXIT_GRACE     = 250.milliseconds

    def initialize(@global : GlobalOptions, @stdout : IO, @stderr : IO)
    end

    def execute(command : CLICommand) : Nil
      case command
      when RunCommand
        execute_run(command)
      when SnapshotCommand
        execute_snapshot(command)
      when ScriptCommand
        execute_script(command)
      else
        raise UsageError.new("unsupported command")
      end
    end

    private def execute_run(command : RunCommand) : Nil
      session = spawn_session(command.command, command.args, @global.rows, @global.cols, @global.reflow)
      begin
        status = wait_exit(session, @global.timeout)
        screen = session.screen
        snapshot = render(screen)

        if command.expects.empty? && command.expect_exit.nil?
          assert_exit(status, 0, snapshot)
          return
        end

        command.expects.each do |text|
          unless screen.contains?(text)
            raise Failure.new("expected final screen to contain #{text.inspect}", snapshot)
          end
        end

        if expected = command.expect_exit
          assert_exit(status, expected, snapshot)
        end
      ensure
        session.close
      end
    end

    private def execute_snapshot(command : SnapshotCommand) : Nil
      session = spawn_session(command.command, command.args, @global.rows, @global.cols, @global.reflow)
      begin
        if settle = command.idle
          wait_idle(session, settle, @global.timeout)
        else
          status = wait_exit(session, @global.timeout)
          snapshot = render(session.screen)
          assert_exit(status, 0, snapshot)
        end

        snapshot = render(session.screen)

        if golden = command.golden
          if command.update
            File.write(golden, snapshot)
            return
          end

          compare_golden(golden, snapshot)
        else
          print_snapshot(snapshot)
        end
      ensure
        session.close
      end
    end

    private def execute_script(command : ScriptCommand) : Nil
      source = File.read(command.file)
      execute_tape(Tape.parse(source))
    rescue ex : File::Error
      raise UsageError.new("failed to read #{command.file.inspect}: #{ex.message}")
    end

    private def execute_tape(tape : Tape) : Nil
      rows = @global.rows
      cols = @global.cols
      reflow = @global.reflow
      session = nil
      status = nil

      begin
        tape.directives.each do |directive|
          case directive
          when Tape::Rows
            rows = directive.value
          when Tape::Cols
            cols = directive.value
          when Tape::Reflow
            reflow = true
          when Tape::Run
            session = spawn_session(directive.command, directive.args, rows, cols, reflow)
          when Tape::Wait
            active = require_session(session, directive)
            wait_for(active, directive.text, directive.deadline, directive.line)
          when Tape::Idle
            active = require_session(session, directive)
            wait_idle(active, directive.settle, directive.deadline, directive.line)
          when Tape::TypeText
            require_session(session, directive).type(directive.text)
          when Tape::Press
            require_session(session, directive).press(directive.key)
          when Tape::Click
            active = require_session(session, directive)
            session_input(active, directive) do
              active.click(directive.row, directive.col, directive.button)
            end
          when Tape::Paste
            # paste never raises for mode; always meaningful raw or bracketed.
            require_session(session, directive).paste(directive.text)
          when Tape::Expect
            active = require_session(session, directive)
            screen = active.screen
            snapshot = render(screen)
            unless screen.contains?(directive.text)
              raise Failure.new("expected screen to contain #{directive.text.inspect}", snapshot, directive.line)
            end
          when Tape::ExpectNot
            active = require_session(session, directive)
            screen = active.screen
            snapshot = render(screen)
            if screen.contains?(directive.text)
              raise Failure.new("expected screen not to contain #{directive.text.inspect}", snapshot, directive.line)
            end
          when Tape::Snapshot
            active = require_session(session, directive)
            snapshot = render(active.screen)
            if file = directive.file
              File.write(file, snapshot)
            else
              print_snapshot(snapshot)
            end
          when Tape::Resize
            require_session(session, directive).resize(rows: directive.rows, cols: directive.cols)
          when Tape::SendExit
            active = require_session(session, directive)
            status ||= wait_exit_if_ready(active)
            active.close
            status ||= wait_exit(active, @global.timeout, directive.line)
          when Tape::ExpectExit
            active = require_session(session, directive)
            status ||= wait_exit(active, @global.timeout, directive.line)
            assert_exit(status.not_nil!, directive.code, render(active.screen), directive.line)
          end
        end
      ensure
        session.try(&.close)
      end
    end

    private def spawn_session(command : String, args : Array(String), rows : Int32, cols : Int32, reflow : Bool = false) : Term::VT::Session
      Term::VT::Session.spawn(command, args, rows: rows, cols: cols, reflow: reflow)
    rescue ex : Exception
      raise UsageError.new("failed to spawn #{command.inspect}: #{ex.message}")
    end

    private def wait_for(session : Term::VT::Session, text : String, deadline : Time::Span, line : Int32? = nil) : Nil
      session.wait_for(text, deadline: deadline)
    rescue Term::VT::TimeoutError
      raise Failure.new("timed out waiting for #{text.inspect} after #{deadline}", render(session.screen), line)
    end

    private def wait_idle(session : Term::VT::Session, settle : Time::Span, deadline : Time::Span, line : Int32? = nil) : Nil
      session.wait_idle(settle: settle, deadline: deadline)
    rescue Term::VT::TimeoutError
      raise Failure.new("timed out waiting for idle screen after #{deadline}", render(session.screen), line)
    end

    private def wait_exit(session : Term::VT::Session, deadline : Time::Span, line : Int32? = nil) : Process::Status
      status = session.wait_exit(deadline: deadline)
      drain_after_exit(session)
      status
    rescue Term::VT::TimeoutError
      raise Failure.new("timed out waiting for process exit after #{deadline}", render(session.screen), line)
    end

    private def wait_exit_if_ready(session : Term::VT::Session) : Process::Status?
      wait_exit(session, SEND_EXIT_GRACE)
    rescue Failure
      nil
    end

    private def drain_after_exit(session : Term::VT::Session) : Nil
      session.wait_idle(settle: EXIT_DRAIN_SETTLE, deadline: EXIT_DRAIN_DEADLINE)
    rescue Term::VT::TimeoutError
    end

    private def assert_exit(status : Process::Status, expected : Int32, snapshot : String, line : Int32? = nil) : Nil
      return if status.exit_code? == expected

      raise Failure.new("expected exit #{expected}, got #{exit_label(status)}", snapshot, line)
    end

    private def exit_label(status : Process::Status) : String
      if code = status.exit_code?
        code.to_s
      elsif signal = status.exit_signal?
        "signal #{signal}"
      else
        "abnormal exit"
      end
    end

    private def compare_golden(path : String, snapshot : String) : Nil
      unless File.exists?(path)
        raise Failure.new("golden file #{path.inspect} does not exist", snapshot)
      end

      expected = File.read(path)
      return if expected == snapshot

      diff = unified_diff(path, expected, snapshot)
      raise Failure.new("snapshot differed from #{path.inspect}\n#{diff}", snapshot)
    end

    private def unified_diff(path : String, expected : String, actual : String) : String
      expected_lines = expected.lines(chomp: true)
      actual_lines = actual.lines(chomp: true)
      max = {expected_lines.size, actual_lines.size}.max

      String.build do |io|
        io.puts "--- #{path}"
        io.puts "+++ actual"
        io.puts "@@ -1,#{expected_lines.size} +1,#{actual_lines.size} @@"

        max.times do |index|
          expected_line = expected_lines[index]?
          actual_line = actual_lines[index]?

          if expected_line == actual_line
            io.puts " #{expected_line}" if expected_line
          else
            io.puts "-#{expected_line}" if expected_line
            io.puts "+#{actual_line}" if actual_line
          end
        end
      end
    end

    private def require_session(session : Term::VT::Session?, directive : Tape::Directive) : Term::VT::Session
      session || raise UsageError.new("#{directive.class.name.split("::").last} requires a running session", directive.line)
    end

    # Maps fail-loud Session input errors (mouse/focus) to exit-1 Failure.
    private def session_input(session : Term::VT::Session, directive : Tape::Directive, &) : Nil
      yield
    rescue ex : ArgumentError
      raise Failure.new(ex.message || "input failed", render(session.screen), directive.line)
    end

    private def render(screen : Term::VT::Screen) : String
      @global.styled ? screen.styled_snapshot : screen.snapshot
    end

    private def print_snapshot(snapshot : String) : Nil
      @stdout.print snapshot unless @global.quiet
    end
  end
end
