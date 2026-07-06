module Term::VT
  struct CSIParam
    MAX_VALUE = 65_535

    getter raw : String
    getter value : Int32
    getter subparams : Array(Int32)

    def initialize(@raw : String, @value : Int32, @subparams : Array(Int32) = [] of Int32)
    end

    def self.parse(raw : String) : self
      parts = raw.split(':')
      value = parse_number(parts[0]? || "")
      subparams = parts[1..]?.try(&.map { |part| parse_number(part) }) || [] of Int32

      new(raw, value, subparams)
    end

    def self.parse_list(raw : String) : Array(self)
      pieces = raw.empty? ? [""] : raw.split(';')
      pieces.first(16).map { |piece| parse(piece) }
    end

    private def self.parse_number(text : String) : Int32
      value = 0
      saw_digit = false

      text.each_char do |char|
        break unless char >= '0' && char <= '9'

        saw_digit = true
        value = value * 10 + char.ord - '0'.ord
        value = MAX_VALUE if value > MAX_VALUE
      end

      saw_digit ? value : 0
    end
  end

  module Performer
    abstract def print(char : Char)
    abstract def execute(byte : UInt8)
    abstract def esc_dispatch(intermediates : String, final : Char)
    abstract def csi_dispatch(params : Array(CSIParam), intermediates : String, final : Char)
    abstract def osc_dispatch(data : String)
  end
end
