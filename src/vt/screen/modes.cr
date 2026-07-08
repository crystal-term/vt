module Term::VT
  class Screen
    private def set_private_modes(params : Array(CSIParam), enabled : Bool) : Nil
      params.each do |param|
        case param.value
        when 25
          @cursor_visible = enabled
        when 7
          @autowrap = enabled
          @pending_wrap = false unless enabled
        when 6
          @origin_mode = enabled
          home_cursor
        when 9
          set_mouse_tracking(MouseTracking::X10, enabled)
        when 1000
          set_mouse_tracking(MouseTracking::Normal, enabled)
        when 1002
          set_mouse_tracking(MouseTracking::Button, enabled)
        when 1003
          set_mouse_tracking(MouseTracking::Any, enabled)
        when 1005
          set_mouse_encoding(MouseEncoding::Utf8, enabled)
        when 1006
          set_mouse_encoding(MouseEncoding::Sgr, enabled)
        when 1015
          set_mouse_encoding(MouseEncoding::Urxvt, enabled)
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

    # Setting a tracking mode replaces the previous one. Resetting the active
    # mode returns to Off; resetting an inactive mode is a no-op (xterm).
    private def set_mouse_tracking(mode : MouseTracking, enabled : Bool) : Nil
      if enabled
        @mouse_tracking = mode
      elsif @mouse_tracking == mode
        @mouse_tracking = MouseTracking::Off
      end
    end

    # Last encoding set wins; reset of the active encoding falls back to Default.
    private def set_mouse_encoding(mode : MouseEncoding, enabled : Bool) : Nil
      if enabled
        @mouse_encoding = mode
      elsif @mouse_encoding == mode
        @mouse_encoding = MouseEncoding::Default
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
      @cursor_row = 0
      @cursor_col = 0
      @pending_wrap = false
    end

    private def leave_alt_screen(restore : Bool) : Nil
      @alt_screen = false
      restore_cursor if restore
      @pending_wrap = false
    end
  end
end
