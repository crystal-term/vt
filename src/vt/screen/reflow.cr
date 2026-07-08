module Term::VT
  class Screen
    # Re-wrap primary + scrollback at `new_cols`, then place the tail in the
    # visible grid (`new_rows` tall). Active cursor is restored only when not on
    # the alternate screen.
    private def reflow_primary(new_rows : Int32, new_cols : Int32) : Nil
      restore_cursor = !@alt_screen
      cursor_line = 0
      cursor_offset = 0

      if restore_cursor
        cursor_line, cursor_offset = capture_cursor_logical
      end

      physical, wraps = rewrap_all(new_cols)
      apply_physical_layout(physical, wraps, new_rows, new_cols)

      if restore_cursor
        restore_cursor_logical(cursor_line, cursor_offset, new_rows, new_cols)
      end
    end

    # Pure row change with reflow: pull rows back from scrollback when growing,
    # push the top of the primary into scrollback when shrinking (xterm-style tail).
    private def resize_primary_rows(new_rows : Int32) : Nil
      combined_rows = [] of Array(Cell)
      combined_wraps = [] of Bool

      @scrollback.each_with_index do |row, i|
        combined_rows << row
        combined_wraps << @scrollback_wrapped[i]
      end
      @primary.each_with_index do |row, i|
        combined_rows << row
        combined_wraps << @primary_wrapped[i]
      end

      abs_cursor = @scrollback.size + @cursor_row
      pending = @pending_wrap
      col = @cursor_col

      apply_physical_layout(combined_rows, combined_wraps, new_rows, @cols)

      unless @alt_screen
        sb = @scrollback.size
        @cursor_row = (abs_cursor - sb).clamp(0, new_rows - 1)
        @cursor_col = col.clamp(0, @cols - 1)
        @pending_wrap = pending && @cursor_col == @cols - 1
      end
    end

    private def rewrap_all(new_cols : Int32) : Tuple(Array(Array(Cell)), Array(Bool))
      physical = [] of Array(Cell)
      wraps = [] of Bool

      collect_logical_lines.each do |line|
        rows, row_wraps = wrap_logical_line(line, new_cols)
        physical.concat(rows)
        wraps.concat(row_wraps)
      end

      if physical.empty?
        physical << Array.new(new_cols) { Cell.blank }
        wraps << false
      end

      {physical, wraps}
    end

    private def apply_physical_layout(
      physical : Array(Array(Cell)),
      wraps : Array(Bool),
      new_rows : Int32,
      new_cols : Int32,
    ) : Nil
      physical = physical.map { |row| pad_or_trim_row(row, new_cols) }

      if physical.size > new_rows
        overflow = physical.size - new_rows
        sb_rows = physical[0, overflow]
        sb_wraps = wraps[0, overflow]
        physical = physical[overflow..]
        wraps = wraps[overflow..]

        @scrollback = Deque(Array(Cell)).new
        @scrollback_wrapped = Deque(Bool).new
        start = {0, sb_rows.size - @scrollback_limit}.max
        (start...sb_rows.size).each do |i|
          @scrollback << sb_rows[i]
          @scrollback_wrapped << sb_wraps[i]
        end
      else
        @scrollback = Deque(Array(Cell)).new
        @scrollback_wrapped = Deque(Bool).new
        while physical.size < new_rows
          physical << Array.new(new_cols) { Cell.blank }
          wraps << false
        end
      end

      @primary = physical
      @primary_wrapped = wraps
    end

    private def pad_or_trim_row(row : Array(Cell), cols : Int32) : Array(Cell)
      resized = row.first(cols)
      resized += Array.new(cols - resized.size) { Cell.blank } if resized.size < cols
      resized
    end

    # Join scrollback + primary into logical lines via soft-wrap flags.
    private def collect_logical_lines : Array(Array(Cell))
      lines = [] of Array(Cell)
      current = [] of Cell

      @scrollback.each_with_index do |row, i|
        append_physical_to_logical(current, row, @scrollback_wrapped[i])
        unless @scrollback_wrapped[i]
          lines << current
          current = [] of Cell
        end
      end

      @primary.each_with_index do |row, i|
        append_physical_to_logical(current, row, @primary_wrapped[i])
        unless @primary_wrapped[i]
          lines << current
          current = [] of Cell
        end
      end

      lines << current unless current.empty?

      # Unwritten trailing blank rows are not hard newlines; drop them so
      # reflow does not invent empty logical lines that shove content into
      # scrollback.
      while lines.size > 0 && lines.last.empty?
        lines.pop
      end

      lines
    end

    private def append_physical_to_logical(into : Array(Cell), row : Array(Cell), wrapped : Bool) : Nil
      cells = non_continuation_cells(row)
      if wrapped
        into.concat(cells)
      else
        into.concat(strip_trailing_blank_cells(cells))
      end
    end

    private def non_continuation_cells(row : Array(Cell)) : Array(Cell)
      row.reject(&.continuation)
    end

    private def strip_trailing_blank_cells(cells : Array(Cell)) : Array(Cell)
      end_idx = cells.size - 1
      while end_idx >= 0 && cells[end_idx].blank?
        end_idx -= 1
      end
      return [] of Cell if end_idx < 0

      cells[0..end_idx]
    end

    # Place content cells into rows of `cols`, never splitting a width-2 pair.
    private def wrap_logical_line(cells : Array(Cell), cols : Int32) : Tuple(Array(Array(Cell)), Array(Bool))
      if cells.empty?
        return {[Array.new(cols) { Cell.blank }], [false]}
      end

      rows = [] of Array(Cell)
      wraps = [] of Bool
      current = Array.new(cols) { Cell.blank }
      col = 0

      cells.each do |cell|
        width = cell.width.to_i
        width = 1 if width < 1

        if col > 0 && col + width > cols
          rows << current
          wraps << true
          current = Array.new(cols) { Cell.blank }
          col = 0
        elsif col == 0 && width > cols
          # Wide cell on a narrower screen: still place the lead cell.
        elsif col + width > cols
          rows << current
          wraps << true
          current = Array.new(cols) { Cell.blank }
          col = 0
        end

        current[col] = Cell.new(
          char: cell.char,
          style: cell.style,
          width: cell.width,
          continuation: false,
          extras: cell.extras,
        )
        if width == 2 && col + 1 < cols
          current[col + 1] = Cell.new(style: cell.style, continuation: true)
        end
        col += width
        col = cols if col > cols
      end

      rows << current
      wraps << false
      {rows, wraps}
    end

    # Logical line index + display-column offset of the active cursor within
    # scrollback+primary.
    private def capture_cursor_logical : Tuple(Int32, Int32)
      line_idx = 0
      offset_in_line = 0

      @scrollback.each_with_index do |row, i|
        cells = cells_for_join(row, @scrollback_wrapped[i])
        if @scrollback_wrapped[i]
          offset_in_line += display_width(cells)
        else
          line_idx += 1
          offset_in_line = 0
        end
      end

      @primary.each_with_index do |row, i|
        if i == @cursor_row
          prefix = cells_before_col(row, @cursor_col)
          return {line_idx, offset_in_line + display_width(prefix)}
        end

        cells = cells_for_join(row, @primary_wrapped[i])
        if @primary_wrapped[i]
          offset_in_line += display_width(cells)
        else
          line_idx += 1
          offset_in_line = 0
        end
      end

      {line_idx, 0}
    end

    private def cells_for_join(row : Array(Cell), wrapped : Bool) : Array(Cell)
      cells = non_continuation_cells(row)
      wrapped ? cells : strip_trailing_blank_cells(cells)
    end

    private def cells_before_col(row : Array(Cell), col : Int32) : Array(Cell)
      cells = [] of Cell
      c = 0
      while c < col && c < row.size
        cell = row[c]
        if cell.continuation
          c += 1
          next
        end
        width = cell.width.to_i
        width = 1 if width < 1
        cells << cell
        c += width
      end
      cells
    end

    private def display_width(cells : Array(Cell)) : Int32
      cells.sum { |cell| w = cell.width.to_i; w < 1 ? 1 : w }
    end

    private def restore_cursor_logical(
      line_idx : Int32,
      offset : Int32,
      new_rows : Int32,
      new_cols : Int32,
    ) : Nil
      # Group absolute physical rows (scrollback + primary) into logical lines.
      abs_rows = [] of Array(Cell)
      abs_wraps = [] of Bool
      @scrollback.each_with_index do |row, i|
        abs_rows << row
        abs_wraps << @scrollback_wrapped[i]
      end
      @primary.each_with_index do |row, i|
        abs_rows << row
        abs_wraps << @primary_wrapped[i]
      end

      logical = [] of Array(Int32)
      current = [] of Int32
      abs_rows.each_with_index do |_, i|
        current << i
        unless abs_wraps[i]
          logical << current
          current = [] of Int32
        end
      end
      logical << current unless current.empty?

      if logical.empty?
        @cursor_row = 0
        @cursor_col = 0
        @pending_wrap = false
        return
      end

      if line_idx >= logical.size
        line_idx = logical.size - 1
        offset = Int32::MAX // 2
      end
      line_idx = 0 if line_idx < 0

      phys = logical[line_idx]
      remaining = offset
      target_abs = phys.last
      target_col = 0

      phys.each_with_index do |abs_i, i|
        row = abs_rows[abs_i]
        is_last = i == phys.size - 1
        span = if is_last
                 display_width(strip_trailing_blank_cells(non_continuation_cells(row)))
               else
                 # Soft-wrapped row: full cell span (typically new_cols).
                 display_width(non_continuation_cells(row))
               end
        span = new_cols if !is_last && span == 0

        if remaining < span || is_last
          col = remaining
          col = span if col > span
          col = 0 if col < 0
          target_abs = abs_i
          target_col = col.clamp(0, new_cols - 1)
          break
        end

        remaining -= span
      end

      sb = @scrollback.size
      if target_abs < sb
        @cursor_row = 0
        @cursor_col = 0
        @pending_wrap = false
      else
        @cursor_row = (target_abs - sb).clamp(0, new_rows - 1)
        @cursor_col = target_col.clamp(0, new_cols - 1)
        # Pending wrap only when the cursor sits on the last column of a row
        # filled through that column (same as after autowrap print).
        @pending_wrap = @cursor_col == new_cols - 1 &&
                        row_filled_through?(@primary[@cursor_row], @cursor_col)
      end
    end

    private def row_filled_through?(row : Array(Cell), col : Int32) : Bool
      return false if col < 0 || col >= row.size

      cell = row[col]
      !cell.blank? || cell.continuation
    end
  end
end
