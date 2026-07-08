module Term::VT
  class Screen
    private def move_cursor(row : Int32, col : Int32) : Nil
      @pending_wrap = false
      @cursor_row = row.clamp(row_min, row_max)
      @cursor_col = col.clamp(0, @cols - 1)
    end

    private def clamp_cursor : Nil
      @cursor_row = @cursor_row.clamp(row_min, row_max)
      @cursor_col = @cursor_col.clamp(0, @cols - 1)
    end

    private def home_cursor : Nil
      move_cursor(row: row_min, col: 0)
    end

    # Absolute origin for CUP/HVP/VPA and clamp bounds under DECOM.
    private def row_min : Int32
      @origin_mode ? @scroll_top : 0
    end

    private def row_max : Int32
      @origin_mode ? @scroll_bottom : @rows - 1
    end

    # CUU/CUD: when the cursor starts inside the scroll region, stay within margins.
    private def move_cursor_vertical(delta : Int32) : Nil
      target = @cursor_row + delta
      if inside_scroll_region?
        target = target.clamp(@scroll_top, @scroll_bottom)
      end
      move_cursor(row: target, col: @cursor_col)
    end

    private def cup(row_one_based : Int32, col_one_based : Int32) : Nil
      row = row_one_based - 1
      col = col_one_based - 1
      row += @scroll_top if @origin_mode
      move_cursor(row: row, col: col)
    end

    private def vpa(row_one_based : Int32) : Nil
      row = row_one_based - 1
      row += @scroll_top if @origin_mode
      move_cursor(row: row, col: @cursor_col)
    end

    private def save_cursor : Nil
      saved = SavedCursor.new(@cursor_row, @cursor_col, @style, @pending_wrap, @origin_mode)
      if @alt_screen
        @saved_alternate = saved
      else
        @saved_primary = saved
      end
    end

    private def restore_cursor : Nil
      saved = @alt_screen ? @saved_alternate : @saved_primary
      @cursor_row = saved.row
      @cursor_col = saved.col
      @style = saved.style
      @pending_wrap = saved.pending_wrap
      @origin_mode = saved.origin
      clamp_cursor
    end
  end
end
