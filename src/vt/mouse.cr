module Term::VT
  enum MouseTracking
    Off
    X10
    Normal
    Button
    Any
  end

  enum MouseEncoding
    Default
    Utf8
    Sgr
    Urxvt
  end

  # Encodes mouse events for the wire format the child process expects.
  # Coordinates are 0-based on the API surface and 1-based on the wire.
  module Mouse
    BUTTONS = {
      :left       => 0,
      :middle     => 1,
      :right      => 2,
      :wheel_up   => 64,
      :wheel_down => 65,
    }

    X10_COORD_MAX = 223
    MOTION_FLAG   =  32
    X10_RELEASE   =   3

    def self.button_code(button : Symbol) : Int32
      BUTTONS[button]? || raise ArgumentError.new("unknown mouse button: #{button}")
    end

    def self.encode(
      row : Int32,
      col : Int32,
      button : Symbol,
      *,
      release : Bool = false,
      motion : Bool = false,
      encoding : MouseEncoding = MouseEncoding::Default,
    ) : Bytes
      code = button_code(button)
      code |= MOTION_FLAG if motion

      x = col + 1
      y = row + 1

      if encoding.sgr?
        encode_sgr(code, x, y, release)
      else
        encode_x10(code, x, y, release)
      end
    end

    private def self.encode_sgr(code : Int32, x : Int32, y : Int32, release : Bool) : Bytes
      final = release ? 'm' : 'M'
      "\e[<#{code};#{x};#{y}#{final}".to_slice
    end

    private def self.encode_x10(code : Int32, x : Int32, y : Int32, release : Bool) : Bytes
      cb = release ? X10_RELEASE : code
      cx = {x, X10_COORD_MAX}.min
      cy = {y, X10_COORD_MAX}.min

      Bytes[
        0x1b_u8,
        '['.ord.to_u8,
        'M'.ord.to_u8,
        (cb + 32).to_u8,
        (cx + 32).to_u8,
        (cy + 32).to_u8,
      ]
    end
  end
end
