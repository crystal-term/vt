require "../term-vt"
require "./options"

module Term::VT::CLI
  class Tape
    getter directives : Array(Directive)

    def initialize(@directives : Array(Directive))
    end

    def self.parse(source : String) : self
      Parser.new(source).parse
    end

    abstract class Directive
      getter line : Int32

      def initialize(@line : Int32)
      end
    end

    class Rows < Directive
      getter value : Int32

      def initialize(line : Int32, @value : Int32)
        super(line)
      end
    end

    class Cols < Directive
      getter value : Int32

      def initialize(line : Int32, @value : Int32)
        super(line)
      end
    end

    class Run < Directive
      getter command : String
      getter args : Array(String)

      def initialize(line : Int32, @command : String, @args : Array(String))
        super(line)
      end
    end

    class Wait < Directive
      getter text : String
      getter deadline : Time::Span

      def initialize(line : Int32, @text : String, @deadline : Time::Span)
        super(line)
      end
    end

    class Idle < Directive
      getter settle : Time::Span
      getter deadline : Time::Span

      def initialize(line : Int32, @settle : Time::Span, @deadline : Time::Span)
        super(line)
      end
    end

    class TypeText < Directive
      getter text : String

      def initialize(line : Int32, @text : String)
        super(line)
      end
    end

    class Press < Directive
      getter key : Symbol

      def initialize(line : Int32, @key : Symbol)
        super(line)
      end
    end

    class Click < Directive
      getter row : Int32
      getter col : Int32
      getter button : Term::VT::MouseButton

      def initialize(line : Int32, @row : Int32, @col : Int32, @button : Term::VT::MouseButton = Term::VT::MouseButton::Left)
        super(line)
      end
    end

    class Paste < Directive
      getter text : String

      def initialize(line : Int32, @text : String)
        super(line)
      end
    end

    class Expect < Directive
      getter text : String

      def initialize(line : Int32, @text : String)
        super(line)
      end
    end

    class ExpectNot < Directive
      getter text : String

      def initialize(line : Int32, @text : String)
        super(line)
      end
    end

    class Snapshot < Directive
      getter file : String?

      def initialize(line : Int32, @file : String?)
        super(line)
      end
    end

    class Resize < Directive
      getter rows : Int32
      getter cols : Int32

      def initialize(line : Int32, @rows : Int32, @cols : Int32)
        super(line)
      end
    end

    class SendExit < Directive
    end

    class ExpectExit < Directive
      getter code : Int32

      def initialize(line : Int32, @code : Int32)
        super(line)
      end
    end

    private struct Token
      getter value : String
      getter quoted : Bool

      def initialize(@value : String, @quoted : Bool)
      end
    end

    private class Parser
      KEYWORDS = {
        "rows", "cols", "run", "wait", "idle", "type", "press",
        "click", "paste", "expect", "expect-not", "snapshot", "resize",
        "send-exit", "expect-exit",
      }

      def initialize(@source : String)
      end

      def parse : Tape
        directives = [] of Directive
        saw_run = false

        @source.each_line.with_index(1) do |line, line_number|
          tokens = tokenize(line, line_number)
          index = 0

          while index < tokens.size
            token = tokens[index]

            case token.value
            when "rows"
              reject_after_run("rows", line_number) if saw_run
              value, index = read_positive_int(tokens, index + 1, line_number, "row count")
              directives << Rows.new(line_number, value)
            when "cols"
              reject_after_run("cols", line_number) if saw_run
              value, index = read_positive_int(tokens, index + 1, line_number, "column count")
              directives << Cols.new(line_number, value)
            when "run"
              raise error(line_number, "duplicate run directive") if saw_run

              argv = tokens[(index + 1)..].map(&.value)
              raise error(line_number, "run requires a command") if argv.empty?

              directives << Run.new(line_number, argv.first, argv[1..]? || [] of String)
              saw_run = true
              index = tokens.size
            when "wait"
              require_run!(saw_run, "wait", line_number)
              text, index = read_quoted(tokens, index + 1, line_number, "wait text")
              deadline, index = read_span(tokens, index, line_number, "wait deadline")
              directives << Wait.new(line_number, text, deadline)
            when "idle"
              require_run!(saw_run, "idle", line_number)
              settle, index = read_span(tokens, index + 1, line_number, "idle settle")
              deadline, index = read_span(tokens, index, line_number, "idle deadline")
              directives << Idle.new(line_number, settle, deadline)
            when "type"
              require_run!(saw_run, "type", line_number)
              text, index = read_quoted(tokens, index + 1, line_number, "type text")
              directives << TypeText.new(line_number, text)
            when "press"
              require_run!(saw_run, "press", line_number)
              key, index = read_key(tokens, index + 1, line_number)
              directives << Press.new(line_number, key)
            when "click"
              require_run!(saw_run, "click", line_number)
              row, index = read_non_negative_int(tokens, index + 1, line_number, "click row")
              col, index = read_non_negative_int(tokens, index, line_number, "click column")
              button = Term::VT::MouseButton::Left
              if next_token = tokens[index]?
                unless keyword?(next_token)
                  button = case next_token.value
                           when "left"   then Term::VT::MouseButton::Left
                           when "middle" then Term::VT::MouseButton::Middle
                           when "right"  then Term::VT::MouseButton::Right
                           else
                             raise error(line_number, "unknown click button #{next_token.value.inspect}")
                           end
                  index += 1
                end
              end
              directives << Click.new(line_number, row, col, button)
            when "paste"
              require_run!(saw_run, "paste", line_number)
              text, index = read_quoted(tokens, index + 1, line_number, "paste text")
              directives << Paste.new(line_number, text)
            when "expect"
              require_run!(saw_run, "expect", line_number)
              text, index = read_quoted(tokens, index + 1, line_number, "expected text")
              directives << Expect.new(line_number, text)
            when "expect-not"
              require_run!(saw_run, "expect-not", line_number)
              text, index = read_quoted(tokens, index + 1, line_number, "forbidden text")
              directives << ExpectNot.new(line_number, text)
            when "snapshot"
              require_run!(saw_run, "snapshot", line_number)
              file = nil
              if next_token = tokens[index + 1]?
                unless keyword?(next_token)
                  file = next_token.value
                  index += 1
                end
              end
              directives << Snapshot.new(line_number, file)
              index += 1
            when "resize"
              require_run!(saw_run, "resize", line_number)
              rows, index = read_positive_int(tokens, index + 1, line_number, "row count")
              cols, index = read_positive_int(tokens, index, line_number, "column count")
              directives << Resize.new(line_number, rows, cols)
            when "send-exit"
              require_run!(saw_run, "send-exit", line_number)
              directives << SendExit.new(line_number)
              index += 1
            when "expect-exit"
              require_run!(saw_run, "expect-exit", line_number)
              code, index = read_exit_code(tokens, index + 1, line_number)
              directives << ExpectExit.new(line_number, code)
            else
              raise error(line_number, "unknown directive #{token.value.inspect}")
            end
          end
        end

        raise UsageError.new("tape must contain exactly one run directive") unless saw_run

        Tape.new(directives)
      end

      private def tokenize(line : String, line_number : Int32) : Array(Token)
        tokens = [] of Token
        chars = line.chars
        index = 0

        while index < chars.size
          case chars[index]
          when ' ', '\t', '\r', '\n'
            index += 1
          when '#'
            break
          when '"'
            token, index = parse_quoted(chars, index, line_number)
            tokens << token
          else
            token, index = parse_unquoted(chars, index)
            tokens << token
          end
        end

        tokens
      end

      private def parse_unquoted(chars : Array(Char), start : Int32) : Tuple(Token, Int32)
        index = start
        value = String.build do |io|
          while index < chars.size
            char = chars[index]
            break if char.whitespace? || char == '#'

            io << char
            index += 1
          end
        end

        {Token.new(value, false), index}
      end

      private def parse_quoted(chars : Array(Char), start : Int32, line_number : Int32) : Tuple(Token, Int32)
        index = start + 1
        value = String.build do |io|
          while index < chars.size
            char = chars[index]

            case char
            when '"'
              return {Token.new(io.to_s, true), index + 1}
            when '\\'
              index += 1
              raise error(line_number, "unterminated escape sequence") if index >= chars.size

              index = append_escape(io, chars, index, line_number)
            else
              io << char
              index += 1
            end
          end
        end

        raise error(line_number, "unterminated string #{value.inspect}")
      end

      private def append_escape(io : IO, chars : Array(Char), index : Int32, line_number : Int32) : Int32
        case chars[index]
        when '"'
          io << '"'
          index + 1
        when '\\'
          io << '\\'
          index + 1
        when '0'
          io << '\0'
          index + 1
        when 'a'
          io << '\a'
          index + 1
        when 'b'
          io << '\b'
          index + 1
        when 'e'
          io << '\e'
          index + 1
        when 'f'
          io << '\f'
          index + 1
        when 'n'
          io << '\n'
          index + 1
        when 'r'
          io << '\r'
          index + 1
        when 't'
          io << '\t'
          index + 1
        when 'v'
          io << '\v'
          index + 1
        when 'x'
          append_hex_escape(io, chars, index, line_number)
        when 'u'
          append_unicode_escape(io, chars, index, line_number)
        else
          raise error(line_number, "invalid escape sequence \\#{chars[index]}")
        end
      end

      private def append_hex_escape(io : IO, chars : Array(Char), index : Int32, line_number : Int32) : Int32
        raise error(line_number, "invalid hex escape") unless index + 2 < chars.size

        hex = String.build do |builder|
          builder << chars[index + 1]
          builder << chars[index + 2]
        end
        codepoint = hex.to_i?(16)
        raise error(line_number, "invalid hex escape") unless codepoint

        io << codepoint.chr
        index + 3
      rescue ex : ArgumentError
        raise error(line_number, "invalid hex escape")
      end

      private def append_unicode_escape(io : IO, chars : Array(Char), index : Int32, line_number : Int32) : Int32
        raise error(line_number, "invalid unicode escape") unless chars[index + 1]? == '{'

        cursor = index + 2
        hex = String.build do |builder|
          while cursor < chars.size && chars[cursor] != '}'
            builder << chars[cursor]
            cursor += 1
          end
        end

        raise error(line_number, "invalid unicode escape") if hex.empty? || cursor >= chars.size

        codepoint = hex.to_i?(16)
        raise error(line_number, "invalid unicode escape") unless codepoint

        io << codepoint.chr
        cursor + 1
      rescue ex : ArgumentError
        raise error(line_number, "invalid unicode escape")
      end

      private def read_positive_int(tokens : Array(Token), index : Int32, line_number : Int32, label : String) : Tuple(Int32, Int32)
        token = require_token(tokens, index, line_number, label)
        value = token.value.to_i?
        raise error(line_number, "#{label} must be a positive integer") unless value && value > 0

        {value, index + 1}
      end

      private def read_non_negative_int(tokens : Array(Token), index : Int32, line_number : Int32, label : String) : Tuple(Int32, Int32)
        token = require_token(tokens, index, line_number, label)
        value = token.value.to_i?
        raise error(line_number, "#{label} must be a non-negative integer") unless value && value >= 0

        {value, index + 1}
      end

      private def read_exit_code(tokens : Array(Token), index : Int32, line_number : Int32) : Tuple(Int32, Int32)
        token = require_token(tokens, index, line_number, "exit code")
        value = token.value.to_i?
        raise error(line_number, "exit code must be an integer from 0 to 255") unless value && value >= 0 && value <= 255

        {value, index + 1}
      end

      private def read_span(tokens : Array(Token), index : Int32, line_number : Int32, label : String) : Tuple(Time::Span, Int32)
        token = require_token(tokens, index, line_number, label)
        {SpanParser.parse(token.value), index + 1}
      rescue ex : UsageError
        raise error(line_number, ex.message || "invalid #{label}")
      end

      private def read_quoted(tokens : Array(Token), index : Int32, line_number : Int32, label : String) : Tuple(String, Int32)
        token = require_token(tokens, index, line_number, label)
        raise error(line_number, "#{label} must be a double-quoted string") unless token.quoted

        {token.value, index + 1}
      end

      private def read_key(tokens : Array(Token), index : Int32, line_number : Int32) : Tuple(Symbol, Int32)
        token = require_token(tokens, index, line_number, "key name")
        key = Term::VT::Keys.supported.find { |candidate| candidate.to_s == token.value }
        unless key
          raise error(line_number, "unknown key #{token.value.inspect}")
        end

        {key, index + 1}
      end

      private def require_token(tokens : Array(Token), index : Int32, line_number : Int32, label : String) : Token
        tokens[index]? || raise error(line_number, "missing #{label}")
      end

      private def require_run!(saw_run : Bool, directive : String, line_number : Int32) : Nil
        raise error(line_number, "#{directive} cannot appear before run") unless saw_run
      end

      private def reject_after_run(directive : String, line_number : Int32) : Nil
        raise error(line_number, "#{directive} must appear before run; use resize after run")
      end

      private def keyword?(token : Token) : Bool
        !token.quoted && KEYWORDS.includes?(token.value)
      end

      private def error(line_number : Int32, message : String) : UsageError
        UsageError.new(message, line_number)
      end
    end
  end
end
