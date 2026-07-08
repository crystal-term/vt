module Term::VT
  class Screen
    private def index : Nil
      if @cursor_row == @scroll_bottom
        scroll_up(1)
      elsif @cursor_row > @scroll_bottom
        @cursor_row = {@cursor_row + 1, @rows - 1}.min
      else
        @cursor_row += 1
      end
    end

    private def reverse_index : Nil
      if @cursor_row == @scroll_top
        scroll_down(1)
      elsif @cursor_row < @scroll_top
        @cursor_row = {@cursor_row - 1, 0}.max
      else
        @cursor_row -= 1
      end
    end

    private def scroll_up(count : Int32) : Nil
      full_region = full_scroll_region?
      count.times do
        removed, removed_wrap = shift_region_up(@scroll_top, @scroll_bottom)
        push_scrollback(removed, removed_wrap) if full_region && !@alt_screen
      end
    end

    private def scroll_down(count : Int32) : Nil
      count.times { shift_region_down(@scroll_top, @scroll_bottom) }
    end

    private def insert_lines(count : Int32) : Nil
      return unless inside_scroll_region?

      count = {count, @scroll_bottom - @cursor_row + 1}.min
      count.times { shift_region_down(@cursor_row, @scroll_bottom) }
    end

    private def delete_lines(count : Int32) : Nil
      return unless inside_scroll_region?

      count = {count, @scroll_bottom - @cursor_row + 1}.min
      count.times { shift_region_up(@cursor_row, @scroll_bottom) }
    end

    # Content moves toward lower indices; blank fills `bottom`. Returns the removed top row and wrap flag.
    private def shift_region_up(top : Int32, bottom : Int32) : Tuple(Array(Cell), Bool)
      removed = grid.delete_at(top)
      grid.insert(bottom, blank_row)
      removed_wrap = false
      unless @alt_screen
        removed_wrap = @primary_wrapped.delete_at(top)
        @primary_wrapped.insert(bottom, false)
      end
      {removed, removed_wrap}
    end

    # Content moves toward higher indices; blank fills `top`.
    private def shift_region_down(top : Int32, bottom : Int32) : Nil
      grid.insert(top, blank_row)
      grid.delete_at(bottom + 1)
      unless @alt_screen
        @primary_wrapped.insert(top, false)
        @primary_wrapped.delete_at(bottom + 1)
      end
    end

    private def push_scrollback(row : Array(Cell), wrapped : Bool = false) : Nil
      return if @scrollback_limit == 0

      @scrollback << row
      @scrollback_wrapped << wrapped
      while @scrollback.size > @scrollback_limit
        @scrollback.shift
        @scrollback_wrapped.shift
      end
    end

    private def inside_scroll_region? : Bool
      @cursor_row >= @scroll_top && @cursor_row <= @scroll_bottom
    end

    private def full_scroll_region? : Bool
      @scroll_top == 0 && @scroll_bottom == @rows - 1
    end

    private def set_scroll_region(top_one_based : Int32, bottom_one_based : Int32) : Nil
      top = top_one_based
      top = 1 if top <= 0
      bottom = bottom_one_based
      bottom = @rows if bottom <= 0

      top = (top - 1).clamp(0, @rows - 1)
      bottom = (bottom - 1).clamp(0, @rows - 1)
      return unless top < bottom

      @scroll_top = top
      @scroll_bottom = bottom
      home_cursor
    end

    private def reset_scroll_region : Nil
      @scroll_top = 0
      @scroll_bottom = @rows - 1
    end
  end
end
