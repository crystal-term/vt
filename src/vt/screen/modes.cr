module Term::VT
  class Screen
    private MOUSE_TRACKING = {
         9 => MouseTracking::X10,
      1000 => MouseTracking::Normal,
      1002 => MouseTracking::Button,
      1003 => MouseTracking::Any,
    } of Int32 => MouseTracking

    private MOUSE_ENCODING = {
      1005 => MouseEncoding::Utf8,
      1006 => MouseEncoding::Sgr,
      1015 => MouseEncoding::Urxvt,
    } of Int32 => MouseEncoding

    private def set_private_modes(params : Array(CSIParam), enabled : Bool) : Nil
      params.each do |param|
        if tracking = MOUSE_TRACKING[param.value]?
          @mouse_tracking = exclusive(@mouse_tracking, tracking, enabled, MouseTracking::Off)
          next
        end

        if encoding = MOUSE_ENCODING[param.value]?
          @mouse_encoding = exclusive(@mouse_encoding, encoding, enabled, MouseEncoding::Default)
          next
        end

        case param.value
        when 25
          @cursor_visible = enabled
        when 7
          @autowrap = enabled
          @pending_wrap = false unless enabled
        when 6
          @origin_mode = enabled
          home_cursor
        when 1004
          @focus_reporting = enabled
        when 2004
          @bracketed_paste = enabled
        when 47, 1047
          enabled ? enter_alt_screen(clear: true, save: false) : leave_alt_screen(restore: false)
        when 1049
          enabled ? enter_alt_screen(clear: true, save: true) : leave_alt_screen(restore: true)
        else
          record_unhandled("CSI ?#{param.value}#{enabled ? 'h' : 'l'}")
        end
      end
    end

    # Setting a mode replaces the previous exclusive value. Resetting the active
    # mode returns to `off`; resetting an inactive mode is a no-op (xterm).
    private def exclusive(current : T, mode : T, enabled : Bool, off : T) : T forall T
      if enabled
        mode
      elsif current == mode
        off
      else
        current
      end
    end

    private def set_ansi_modes(params : Array(CSIParam), enabled : Bool) : Nil
      params.each do |param|
        case param.value
        when 4
          @insert_mode = enabled
        else
          record_unhandled("CSI #{param.value}#{enabled ? 'h' : 'l'}")
        end
      end
    end

    private def enter_alt_screen(clear : Bool, save : Bool) : Nil
      save_cursor if save && !@alt_screen
      @alt_screen = true
      @alternate = build_grid if clear
      # DECOM: home into the top margin, not absolute (0,0).
      home_cursor
    end

    private def leave_alt_screen(restore : Bool) : Nil
      @alt_screen = false
      restore_cursor if restore
      @pending_wrap = false
    end
  end
end
