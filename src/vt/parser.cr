require "./performer"

module Term::VT
  class Parser
    OSC_LIMIT   = 4096
    REPLACEMENT = 0xfffd.chr

    enum State
      Ground
      Escape
      EscapeIntermediate
      CsiEntry
      CsiParam
      CsiIntermediate
      CsiIgnore
      OscString
      StringIgnore
    end

    getter state : State

    @utf_code : Int32
    @utf_expected : Int32
    @utf_min : Int32

    def initialize(@performer : Performer)
      @state = State::Ground
      @intermediates = String.new
      @csi_raw = String.new
      @csi_overflow = false
      @osc_bytes = [] of UInt8
      @osc_esc = false
      @string_esc = false
      @utf_code = 0
      @utf_expected = 0
      @utf_min = 0
    end

    def feed(string : String) : self
      feed(string.to_slice)
    end

    def feed(bytes : Bytes) : self
      bytes.each { |byte| process_byte(byte) }
      self
    end

    private def process_byte(byte : UInt8) : Nil
      if @state.ground?
        process_ground(byte)
      else
        process_sequence(byte)
      end
    end

    private def process_ground(byte : UInt8) : Nil
      if @utf_expected > 0
        if continuation?(byte)
          @utf_code = (@utf_code << 6) | (byte.to_i & 0x3f)
          @utf_expected -= 1
          emit_pending_utf8 if @utf_expected == 0
        else
          emit_replacement
          reset_utf8
          process_ground(byte)
        end

        return
      end

      case byte
      when 0x1b
        start_escape
      when 0x00..0x1f, 0x7f
        @performer.execute(byte)
      when 0x00..0x7f
        @performer.print(byte.to_i.chr)
      when 0xc2..0xdf
        start_utf8(byte, expected: 1, min: 0x80, mask: 0x1f)
      when 0xe0..0xef
        start_utf8(byte, expected: 2, min: 0x800, mask: 0x0f)
      when 0xf0..0xf4
        start_utf8(byte, expected: 3, min: 0x10000, mask: 0x07)
      else
        emit_replacement
      end
    end

    private def process_sequence(byte : UInt8) : Nil
      case @state
      when State::OscString
        process_osc(byte)
      when State::StringIgnore
        process_string_ignore(byte)
      else
        process_control_in_sequence(byte) || process_dispatch_state(byte)
      end
    end

    private def process_control_in_sequence(byte : UInt8) : Bool
      case byte
      when 0x18, 0x1a
        ground
      when 0x1b
        start_escape
      when 0x00..0x1f, 0x7f
        @performer.execute(byte)
      else
        return false
      end

      true
    end

    private def process_dispatch_state(byte : UInt8) : Nil
      case @state
      when State::Escape
        process_escape(byte)
      when State::EscapeIntermediate
        process_escape_intermediate(byte)
      when State::CsiEntry
        process_csi_entry(byte)
      when State::CsiParam
        process_csi_param(byte)
      when State::CsiIntermediate
        process_csi_intermediate(byte)
      when State::CsiIgnore
        dispatch_csi_ignore(byte)
      else
      end
    end

    private def process_escape(byte : UInt8) : Nil
      case byte
      when 0x20..0x2f
        append_intermediate(byte)
        @state = State::EscapeIntermediate
      when 0x5b
        enter_csi
      when 0x5d
        enter_osc
      when 0x50, 0x58, 0x5e, 0x5f
        enter_string_ignore
      when 0x30..0x7e
        dispatch_esc(byte)
      else
        ground
      end
    end

    private def process_escape_intermediate(byte : UInt8) : Nil
      case byte
      when 0x20..0x2f
        append_intermediate(byte)
      when 0x30..0x7e
        dispatch_esc(byte)
      else
        ground
      end
    end

    private def process_csi_entry(byte : UInt8) : Nil
      case byte
      when 0x30..0x39, 0x3a, 0x3b
        append_csi_param(byte)
        @state = State::CsiParam
      when 0x3c..0x3f
        append_intermediate(byte)
        @state = State::CsiParam
      when 0x20..0x2f
        append_intermediate(byte)
        @state = State::CsiIntermediate
      when 0x40..0x7e
        dispatch_csi(byte)
      else
      end
    end

    private def process_csi_param(byte : UInt8) : Nil
      case byte
      when 0x30..0x39, 0x3a, 0x3b
        append_csi_param(byte)
      when 0x20..0x2f
        append_intermediate(byte)
        @state = State::CsiIntermediate
      when 0x3c..0x3f
        @state = State::CsiIgnore
      when 0x40..0x7e
        dispatch_csi(byte)
      else
      end
    end

    private def process_csi_intermediate(byte : UInt8) : Nil
      case byte
      when 0x20..0x2f
        append_intermediate(byte)
      when 0x30..0x3f
        @state = State::CsiIgnore
      when 0x40..0x7e
        dispatch_csi(byte)
      else
      end
    end

    private def dispatch_csi_ignore(byte : UInt8) : Nil
      dispatch_csi(byte) if byte >= 0x40 && byte <= 0x7e
    end

    private def process_osc(byte : UInt8) : Nil
      if @osc_esc
        if byte == 0x5c
          dispatch_osc
        else
          append_osc(0x1b_u8)
          @osc_esc = false
          process_osc(byte)
        end

        return
      end

      case byte
      when 0x07
        dispatch_osc
      when 0x18, 0x1a
        ground
      when 0x1b
        @osc_esc = true
      when 0x00..0x1f, 0x7f
        @performer.execute(byte)
      else
        append_osc(byte)
      end
    end

    private def process_string_ignore(byte : UInt8) : Nil
      if @string_esc
        if byte == 0x5c
          ground
        else
          @string_esc = false
          process_string_ignore(byte)
        end

        return
      end

      case byte
      when 0x18, 0x1a
        ground
      when 0x1b
        @string_esc = true
      when 0x00..0x1f, 0x7f
        @performer.execute(byte)
      else
      end
    end

    private def start_escape : Nil
      reset_sequence
      reset_utf8
      @state = State::Escape
    end

    private def enter_csi : Nil
      @csi_raw = String.new
      @csi_overflow = false
      @intermediates = String.new
      @state = State::CsiEntry
    end

    private def enter_osc : Nil
      @osc_bytes.clear
      @osc_esc = false
      @state = State::OscString
    end

    private def enter_string_ignore : Nil
      @string_esc = false
      @state = State::StringIgnore
    end

    private def dispatch_esc(byte : UInt8) : Nil
      @performer.esc_dispatch(@intermediates, byte.to_i.chr)
      ground
    end

    private def dispatch_csi(byte : UInt8) : Nil
      @performer.csi_dispatch(CSIParam.parse_list(@csi_raw), @intermediates, byte.to_i.chr)
      ground
    end

    private def dispatch_osc : Nil
      @performer.osc_dispatch(String.build(@osc_bytes.size) do |io|
        @osc_bytes.each { |byte| io.write_byte(byte) }
      end)
      ground
    end

    private def ground : Nil
      reset_sequence
      @state = State::Ground
    end

    private def reset_sequence : Nil
      @intermediates = String.new
      @csi_raw = String.new
      @csi_overflow = false
      @osc_bytes.clear
      @osc_esc = false
      @string_esc = false
    end

    private def append_intermediate(byte : UInt8) : Nil
      @intermediates += byte.to_i.chr.to_s
    end

    private def append_csi_param(byte : UInt8) : Nil
      return if @csi_overflow

      if byte == 0x3b && @csi_raw.count(';') >= 15
        @csi_overflow = true
        return
      end

      @csi_raw += byte.to_i.chr.to_s
    end

    private def append_osc(byte : UInt8) : Nil
      @osc_bytes << byte if @osc_bytes.size < OSC_LIMIT
    end

    private def start_utf8(byte : UInt8, expected : Int32, min : Int32, mask : Int32) : Nil
      @utf_code = byte.to_i & mask
      @utf_expected = expected
      @utf_min = min
    end

    private def emit_pending_utf8 : Nil
      if @utf_code < @utf_min ||
         @utf_code > 0x10ffff ||
         (@utf_code >= 0xd800 && @utf_code <= 0xdfff)
        emit_replacement
      else
        @performer.print(@utf_code.chr)
      end

      reset_utf8
    end

    private def emit_replacement : Nil
      @performer.print(REPLACEMENT)
    end

    private def reset_utf8 : Nil
      @utf_code = 0
      @utf_expected = 0
      @utf_min = 0
    end

    private def continuation?(byte : UInt8) : Bool
      byte >= 0x80 && byte <= 0xbf
    end
  end
end
