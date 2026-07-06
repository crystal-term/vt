module Term::VT
  class PTYUnavailable < RuntimeError
  end

  module LibCPTY
    {% if flag?(:linux) || flag?(:darwin) || flag?(:freebsd) || flag?(:openbsd) || flag?(:netbsd) || flag?(:dragonfly) %}
      {% if flag?(:linux) %}
        TIOCGWINSZ = 0x5413_u64
        TIOCSWINSZ = 0x5414_u64
        TIOCSCTTY  = 0x540e_u64
      {% else %}
        TIOCGWINSZ = 0x40087468_u64
        TIOCSWINSZ = 0x80087467_u64
        TIOCSCTTY  = 0x20007461_u64
      {% end %}

      {% if flag?(:linux) %}
        @[Link("util")]
      {% end %}
      lib Native
        struct Winsize
          row : UInt16
          col : UInt16
          xpixel : UInt16
          ypixel : UInt16
        end

        fun openpty(amaster : Int32*, aslave : Int32*, name : UInt8*, termp : Void*, winp : Winsize*) : Int32
        fun ioctl(fd : Int32, request : LibC::ULong, ...) : Int32
      end

      def self.openpty(rows : Int32, cols : Int32) : Tuple(Int32, Int32)
        master = 0
        slave = 0
        winsize = build_winsize(rows, cols)

        if Native.openpty(pointerof(master), pointerof(slave), Pointer(UInt8).null, Pointer(Void).null, pointerof(winsize)) == -1
          raise PTYUnavailable.new(IO::Error.from_errno("openpty").message || "openpty failed")
        end

        {master, slave}
      end

      def self.get_winsize(fd : Int32) : Native::Winsize
        winsize = Native::Winsize.new
        raise IO::Error.from_errno("TIOCGWINSZ") if Native.ioctl(fd, LibC::ULong.new(TIOCGWINSZ), pointerof(winsize)) == -1
        winsize
      end

      def self.set_winsize(fd : Int32, rows : Int32, cols : Int32) : Nil
        winsize = build_winsize(rows, cols)
        raise IO::Error.from_errno("TIOCSWINSZ") if Native.ioctl(fd, LibC::ULong.new(TIOCSWINSZ), pointerof(winsize)) == -1
      end

      private def self.build_winsize(rows : Int32, cols : Int32) : Native::Winsize
        winsize = Native::Winsize.new
        winsize.row = clamp_dimension(rows)
        winsize.col = clamp_dimension(cols)
        winsize.xpixel = 0_u16
        winsize.ypixel = 0_u16
        winsize
      end

      private def self.clamp_dimension(value : Int32) : UInt16
        value.clamp(1, UInt16::MAX.to_i).to_u16
      end
    {% else %}
      def self.openpty(rows : Int32, cols : Int32) : Tuple(Int32, Int32)
        raise PTYUnavailable.new("PTYs are only supported on POSIX platforms")
      end

      def self.get_winsize(fd : Int32)
        raise PTYUnavailable.new("PTYs are only supported on POSIX platforms")
      end

      def self.set_winsize(fd : Int32, rows : Int32, cols : Int32) : Nil
        raise PTYUnavailable.new("PTYs are only supported on POSIX platforms")
      end
    {% end %}
  end
end
