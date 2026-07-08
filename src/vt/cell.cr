require "./style"

module Term::VT
  struct Cell
    property char : Char
    property style : Style
    property width : Int8
    property continuation : Bool
    # Zero-width characters (combining marks, VS16, ZWSP, etc.) attached in feed order.
    property extras : String?

    DEFAULT = new

    def initialize(
      @char : Char = ' ',
      @style : Style = Style::DEFAULT,
      @width : Int8 = 1_i8,
      @continuation : Bool = false,
      @extras : String? = nil,
    )
    end

    def self.blank(style : Style = Style::DEFAULT) : self
      new(style: style)
    end

    def blank? : Bool
      @char == ' ' && !@continuation && @extras.nil?
    end
  end
end
