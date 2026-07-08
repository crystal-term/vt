module Term::VT::CLI
  class UsageError < Exception
    getter line : Int32?

    def initialize(message : String, @line : Int32? = nil)
      super(@line ? "line #{@line}: #{message}" : message)
    end
  end

  module SpanParser
    def self.parse(raw : String) : Time::Span
      match = raw.match(/\A([0-9]+)(ms|s|m)\z/)
      raise UsageError.new("invalid span #{raw.inspect}; expected 500ms, 5s, or 1m") unless match

      value = match[1].to_i64
      raise UsageError.new("span must be greater than zero") unless value > 0

      case match[2]
      when "ms"
        value.milliseconds
      when "s"
        value.seconds
      else
        value.minutes
      end
    rescue ex : ArgumentError
      raise UsageError.new("invalid span #{raw.inspect}; expected 500ms, 5s, or 1m")
    end
  end

  class GlobalOptions
    property rows : Int32
    property cols : Int32
    property timeout : Time::Span
    property styled : Bool
    property quiet : Bool
    property reflow : Bool

    def initialize(
      @rows : Int32 = 24,
      @cols : Int32 = 80,
      @timeout : Time::Span = 10.seconds,
      @styled : Bool = false,
      @quiet : Bool = false,
      @reflow : Bool = false,
    )
    end
  end

  abstract class CLICommand
  end

  class RunCommand < CLICommand
    getter expects : Array(String)
    getter expect_exit : Int32?
    getter command : String
    getter args : Array(String)

    def initialize(@expects : Array(String), @expect_exit : Int32?, @command : String, @args : Array(String))
    end
  end

  class SnapshotCommand < CLICommand
    getter golden : String?
    getter update : Bool
    getter idle : Time::Span?
    getter command : String
    getter args : Array(String)

    def initialize(@golden : String?, @update : Bool, @idle : Time::Span?, @command : String, @args : Array(String))
    end
  end

  class ScriptCommand < CLICommand
    getter file : String

    def initialize(@file : String)
    end
  end

  module Options
    def self.parse(argv : Array(String)) : Tuple(GlobalOptions, CLICommand)
      Parser.new(argv).parse
    end

    private class Parser
      def initialize(@argv : Array(String))
      end

      def parse : Tuple(GlobalOptions, CLICommand)
        global = GlobalOptions.new
        index = consume_global_flags(0, global)
        verb = @argv[index]? || raise UsageError.new("missing verb: expected run, snapshot, or script")

        command = case verb
                  when "run"
                    parse_run(index + 1, global)
                  when "snapshot"
                    parse_snapshot(index + 1, global)
                  when "script"
                    parse_script(index + 1, global)
                  else
                    raise UsageError.new("unknown verb #{verb.inspect}: expected run, snapshot, or script")
                  end

        {global, command}
      end

      private def parse_run(index : Int32, global : GlobalOptions) : RunCommand
        expects = [] of String
        expect_exit = nil
        command_argv = nil

        while index < @argv.size
          if next_index = consume_global_flag(index, global)
            index = next_index
            next
          end

          arg = @argv[index]
          case arg
          when "--expect"
            expects << value_after(index, "--expect")
            index += 2
          when "--expect-exit"
            expect_exit = parse_exit_code(value_after(index, "--expect-exit"), "--expect-exit")
            index += 2
          when "--"
            command_argv = rest_after(index)
            index = @argv.size
          else
            raise UsageError.new("unknown run option #{arg.inspect}; put child command after --")
          end
        end

        command, args = split_command(command_argv, "run")
        RunCommand.new(expects, expect_exit, command, args)
      end

      private def parse_snapshot(index : Int32, global : GlobalOptions) : SnapshotCommand
        golden = nil
        update = false
        idle = nil
        command_argv = nil

        while index < @argv.size
          if next_index = consume_global_flag(index, global)
            index = next_index
            next
          end

          arg = @argv[index]
          case arg
          when "--golden"
            golden = value_after(index, "--golden")
            index += 2
          when "--update"
            update = true
            index += 1
          when "--idle"
            idle = SpanParser.parse(value_after(index, "--idle"))
            index += 2
          when "--"
            command_argv = rest_after(index)
            index = @argv.size
          else
            raise UsageError.new("unknown snapshot option #{arg.inspect}; put child command after --")
          end
        end

        raise UsageError.new("--update requires --golden FILE") if update && golden.nil?

        command, args = split_command(command_argv, "snapshot")
        SnapshotCommand.new(golden, update, idle, command, args)
      end

      private def parse_script(index : Int32, global : GlobalOptions) : ScriptCommand
        file = nil

        while index < @argv.size
          if next_index = consume_global_flag(index, global)
            index = next_index
            next
          end

          arg = @argv[index]
          raise UsageError.new("script accepts exactly one FILE.tape argument") if file

          file = arg
          index += 1
        end

        raise UsageError.new("script requires FILE.tape") unless file

        ScriptCommand.new(file)
      end

      private def consume_global_flags(index : Int32, global : GlobalOptions) : Int32
        cursor = index
        while cursor < @argv.size
          next_index = consume_global_flag(cursor, global)
          break unless next_index

          cursor = next_index
        end

        cursor
      end

      private def consume_global_flag(index : Int32, global : GlobalOptions) : Int32?
        arg = @argv[index]
        case arg
        when "--rows"
          global.rows = parse_positive_int(value_after(index, "--rows"), "--rows")
          index + 2
        when "--cols"
          global.cols = parse_positive_int(value_after(index, "--cols"), "--cols")
          index + 2
        when "--timeout"
          global.timeout = SpanParser.parse(value_after(index, "--timeout"))
          index + 2
        when "--styled"
          global.styled = true
          index + 1
        when "--quiet"
          global.quiet = true
          index + 1
        when "--reflow"
          global.reflow = true
          index + 1
        else
          nil
        end
      end

      private def value_after(index : Int32, flag : String) : String
        value = @argv[index + 1]?
        raise UsageError.new("#{flag} requires a value") unless value
        raise UsageError.new("#{flag} requires a value") if value == "--"

        value
      end

      private def rest_after(index : Int32) : Array(String)
        return [] of String if index + 1 >= @argv.size

        @argv[(index + 1)..]
      end

      private def split_command(argv : Array(String)?, verb : String) : Tuple(String, Array(String))
        raise UsageError.new("#{verb} requires -- CMD ARGS...") unless argv && !argv.empty?

        args = argv.size > 1 ? argv[1, argv.size - 1] : [] of String
        {argv.first, args}
      end

      private def parse_positive_int(raw : String, flag : String) : Int32
        value = raw.to_i?
        raise UsageError.new("#{flag} must be a positive integer") unless value && value > 0

        value
      end

      private def parse_exit_code(raw : String, flag : String) : Int32
        value = raw.to_i?
        raise UsageError.new("#{flag} must be an integer from 0 to 255") unless value && value >= 0 && value <= 255

        value
      end
    end
  end
end
