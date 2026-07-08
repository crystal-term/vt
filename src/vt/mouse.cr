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

  enum MouseButton
    Left
    Middle
    Right
    WheelUp
    WheelDown

    def code : Int32
      case self
      in .left?       then 0
      in .middle?     then 1
      in .right?      then 2
      in .wheel_up?   then 64
      in .wheel_down? then 65
      end
    end

    def self.parse?(name : String) : self?
      case name
      when "left"       then Left
      when "middle"     then Middle
      when "right"      then Right
      when "wheel_up"   then WheelUp
      when "wheel_down" then WheelDown
      else
        nil
      end
    end
  end

  # Encodes mouse events for the wire format the child process expects.
  # Coordinates are 0-based on the API surface and 1-based on the wire.
  #
  # Only `MouseEncoding::Sgr` changes the encoder; `Utf8` and `Urxvt` are
  # tracked on the screen for assertions but encode as legacy X10 here.
  module Mouse
    X10_COORD_MAX = 223
    MOTION_FLAG   =  32
    X10_RELEASE   =   3

    def self.encode(
      row : Int32,
      col : Int32,
      button : MouseButton,
      *,
      release : Bool = false,
      motion : Bool = false,
      encoding : MouseEncoding = MouseEncoding::Default,
    ) : Bytes
      raise ArgumentError.new("mouse row must be non-negative") if row < 0
      raise ArgumentError.new("mouse col must be non-negative") if col < 0

      code = button.code
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
