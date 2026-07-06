require "./libc_pty"

module Term::VT
  class PTY
    getter master : IO::FileDescriptor
    getter slave : IO::FileDescriptor
    getter rows : Int32
    getter cols : Int32

    @child_pgid : Int64?
    @closed = false

    private def initialize(@master : IO::FileDescriptor, @slave : IO::FileDescriptor, @rows : Int32, @cols : Int32)
      @child_pgid = nil
    end

    def self.open(rows : Int32 = 24, cols : Int32 = 80) : self
      master_fd, slave_fd = LibCPTY.openpty(rows, cols)
      master = IO::FileDescriptor.new(master_fd)

      begin
        slave = IO::FileDescriptor.new(slave_fd)
      rescue ex
        master.close
        raise ex
      end

      new(master, slave, {rows, 1}.max, {cols, 1}.max)
    rescue ex : PTYUnavailable
      raise ex
    rescue ex : IO::Error
      raise PTYUnavailable.new(ex.message || "PTY unavailable")
    end

    def attach_child_pgid(pgid : Int64?) : Nil
      @child_pgid = pgid
    end

    def winsize : NamedTuple(rows: Int32, cols: Int32)
      size = LibCPTY.get_winsize(@master.fd.to_i)
      {rows: size.row.to_i, cols: size.col.to_i}
    rescue ex : IO::Error
      raise PTYUnavailable.new(ex.message || "PTY winsize unavailable")
    end

    def resize(rows : Int32, cols : Int32) : self
      @rows = {rows, 1}.max
      @cols = {cols, 1}.max
      LibCPTY.set_winsize(@master.fd.to_i, @rows, @cols)
      signal_child_pgrp(Signal::WINCH)
      self
    rescue ex : IO::Error
      raise PTYUnavailable.new(ex.message || "PTY resize unavailable")
    end

    def close : Nil
      return if @closed

      @closed = true
      close_fd(@master)
      close_fd(@slave)
    end

    def closed? : Bool
      @closed
    end

    private def close_fd(io : IO::FileDescriptor) : Nil
      io.close unless io.closed?
    rescue IO::Error
    end

    private def signal_child_pgrp(signal : Signal) : Nil
      if pgid = @child_pgid
        Process.signal(signal, -pgid.to_i)
      end
    rescue RuntimeError
    end
  end
end
