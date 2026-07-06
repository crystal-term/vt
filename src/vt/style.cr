module Term::VT
  struct Color
    enum Kind
      Default
      Indexed
      RGB
    end

    getter kind : Kind
    getter index : UInt8
    getter red : UInt8
    getter green : UInt8
    getter blue : UInt8

    DEFAULT = new

    def initialize(
      @kind : Kind = Kind::Default,
      @index : UInt8 = 0_u8,
      @red : UInt8 = 0_u8,
      @green : UInt8 = 0_u8,
      @blue : UInt8 = 0_u8,
    )
    end

    def self.default : self
      DEFAULT
    end

    def self.indexed(index : Int) : self
      new(Kind::Indexed, index.clamp(0, 255).to_u8)
    end

    def self.rgb(red : Int, green : Int, blue : Int) : self
      new(
        Kind::RGB,
        red: red.clamp(0, 255).to_u8,
        green: green.clamp(0, 255).to_u8,
        blue: blue.clamp(0, 255).to_u8
      )
    end

    def default? : Bool
      @kind == Kind::Default
    end

    def indexed? : Bool
      @kind == Kind::Indexed
    end

    def rgb? : Bool
      @kind == Kind::RGB
    end

    def ==(other : self) : Bool
      @kind == other.kind &&
        @index == other.index &&
        @red == other.red &&
        @green == other.green &&
        @blue == other.blue
    end
  end

  struct Style
    property fg : Color
    property bg : Color
    property bold : Bool
    property dim : Bool
    property italic : Bool
    property underline : Bool
    property blink : Bool
    property inverse : Bool
    property hidden : Bool
    property strikethrough : Bool

    DEFAULT = new

    def initialize(
      @fg : Color = Color::DEFAULT,
      @bg : Color = Color::DEFAULT,
      @bold : Bool = false,
      @dim : Bool = false,
      @italic : Bool = false,
      @underline : Bool = false,
      @blink : Bool = false,
      @inverse : Bool = false,
      @hidden : Bool = false,
      @strikethrough : Bool = false,
    )
    end

    def self.default : self
      DEFAULT
    end

    def default? : Bool
      self == DEFAULT
    end

    def ==(other : self) : Bool
      @fg == other.fg &&
        @bg == other.bg &&
        @bold == other.bold &&
        @dim == other.dim &&
        @italic == other.italic &&
        @underline == other.underline &&
        @blink == other.blink &&
        @inverse == other.inverse &&
        @hidden == other.hidden &&
        @strikethrough == other.strikethrough
    end
  end
end
