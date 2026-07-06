require "./screen"

module Term::VT
  class CapturedTTY < IO
    def initialize
      @buffer = IO::Memory.new
    end

    def read(slice : Bytes) : Int32
      0
    end

    def write(slice : Bytes) : Nil
      @buffer.write(slice)
    end

    def tty? : Bool
      true
    end

    def flush : Nil
    end

    def bytes : Bytes
      @buffer.to_slice
    end

    def output : String
      @buffer.to_s
    end

    def clear : Nil
      @buffer.clear
    end

    def screen(rows : Int32 = 24, cols : Int32 = 80) : Screen
      Screen.new(rows: rows, cols: cols).feed(bytes)
    end
  end
end
