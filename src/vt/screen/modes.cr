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
        when 47, 1047
          enabled ? enter_alt_screen(clear: true, save: false) : leave_alt_screen(restore: false)
        when 1049
          enabled ? enter_alt_screen(clear: true, save: true) : leave_alt_screen(restore: true)
        else
          record_unhandled("CSI ?#{param.value}#{enabled ? 'h' : 'l'}")
        end
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
