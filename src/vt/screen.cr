require "./cell"
require "./mouse"
require "./parser"
require "./width"
require "./tab_stops"

module Term::VT
  class Screen
    include Performer

    getter rows : Int32
    getter cols : Int32
    getter title : String?
    getter bell_count : Int32
    getter unhandled : Array(String)
    property on_report : Proc(Bytes, Nil)?

    private struct SavedCursor
      property row : Int32
      property col : Int32
      property style : Style
      property pending_wrap : Bool
      property origin : Bool

      def initialize(
        @row : Int32 = 0,
        @col : Int32 = 0,
        @style : Style = Style::DEFAULT,
        @pending_wrap : Bool = false,
        @origin : Bool = false,
      )
      end
    end

    @primary : Array(Array(Cell))
    @alternate : Array(Array(Cell))
    @scrollback : Deque(Array(Cell))
    # Per-row soft-wrap flags for primary + scrollback (alt never reflows).
    @primary_wrapped : Array(Bool)
    @scrollback_wrapped : Deque(Bool)
    @parser : Parser?
    @style : Style
    @saved_primary : SavedCursor
    @saved_alternate : SavedCursor
    @scroll_top : Int32
    @scroll_bottom : Int32
    @origin_mode : Bool
    @insert_mode : Bool
    @tab_stops : TabStops
    @mouse_tracking : MouseTracking
    @mouse_encoding : MouseEncoding
    @focus_reporting : Bool
    @bracketed_paste : Bool
    @reflow : Bool

    def initialize(rows : Int32 = 24, cols : Int32 = 80, scrollback : Int32 = 1000, *, reflow : Bool = false)
      @rows = {rows, 1}.max
      @cols = {cols, 1}.max
      @scrollback_limit = {scrollback, 0}.max
      @reflow = reflow
      @primary = build_grid
      @alternate = build_grid
      @scrollback = Deque(Array(Cell)).new
      @primary_wrapped = Array.new(@rows, false)
      @scrollback_wrapped = Deque(Bool).new
      @cursor_row = 0
      @cursor_col = 0
      @cursor_visible = true
      @pending_wrap = false
      @style = Style::DEFAULT
      @saved_primary = SavedCursor.new
      @saved_alternate = SavedCursor.new
      @autowrap = true
      @alt_screen = false
      @scroll_top = 0
      @scroll_bottom = @rows - 1
      @origin_mode = false
      @insert_mode = false
      @tab_stops = TabStops.new(@cols)
      @mouse_tracking = MouseTracking::Off
      @mouse_encoding = MouseEncoding::Default
      @focus_reporting = false
      @bracketed_paste = false
      @title = nil
      @bell_count = 0
      @unhandled = [] of String
      @on_report = nil
      @parser = Parser.new(self)
    end

    def feed(input : String | Bytes) : self
      @parser.not_nil!.feed(input)
      self
    end

    def print(char : Char)
      width = Width.of(char)
      if width == 0
        attach_zero_width(char)
        return
      end

      wrap_pending if @pending_wrap
      wrap_pending if width == 2 && @autowrap && @cursor_col == @cols - 1

      insert_chars(width) if @insert_mode

      row = current_row
      clear_wide_pair_at(@cursor_row, @cursor_col)
      row[@cursor_col] = Cell.new(char: char, style: @style, width: width.to_i8)

      if width == 2 && @cursor_col + 1 < @cols
        clear_wide_pair_at(@cursor_row, @cursor_col + 1)
        row[@cursor_col + 1] = Cell.new(style: @style, continuation: true)
      end

      advance_after_print(width)
    end

    # Attach a width-0 character to the preceding cell (combining marks, VS16,
    # ZWSP, directional marks). Cursor and pending-wrap state are unchanged.
    # No target (column 0 of a fresh row) → drop, matching xterm.
    private def attach_zero_width(char : Char) : Nil
      target = zero_width_target_col
      return unless target

      row = current_row
      cell = row[target]
      extras = cell.extras
      new_extras = extras ? (extras + char) : char.to_s
      row[target] = Cell.new(
        char: cell.char,
        style: cell.style,
        width: cell.width,
        continuation: cell.continuation,
        extras: new_extras,
      )
    end

    # Column of the cell that should receive a width-0 attachment, or nil.
    private def zero_width_target_col : Int32?
      col = if @pending_wrap
              @cursor_col
            else
              return nil if @cursor_col == 0

              @cursor_col - 1
            end

      cell = current_row[col]
      if cell.continuation && col > 0
        col -= 1
      end

      col
    end

    def execute(byte : UInt8)
      case byte
      when 0x07
        @bell_count += 1
      when 0x08
        @pending_wrap = false
        @cursor_col -= 1 if @cursor_col > 0
      when 0x09
        @pending_wrap = false
        horizontal_tab(1)
      when 0x0a, 0x0b, 0x0c
        @pending_wrap = false
        index
      when 0x0d
        @pending_wrap = false
        @cursor_col = 0
      else
      end
    end

    def esc_dispatch(intermediates : String, final : Char)
      case {intermediates, final}
      when {"", '7'}
        save_cursor
      when {"", '8'}
        restore_cursor
      when {"", 'D'}
        index
      when {"", 'M'}
        reverse_index
      when {"", 'E'}
        @cursor_col = 0
        index
      when {"", 'H'}
        @tab_stops.set(@cursor_col)
      when {"", 'c'}
        reset_screen_preserving_title
      else
        return if charset_designation?(intermediates, final)

        record_unhandled("ESC #{intermediates}#{final}")
      end
    end

    def csi_dispatch(params : Array(CSIParam), intermediates : String, final : Char)
      if intermediates == "?" && (final == 'h' || final == 'l')
        set_private_modes(params, final == 'h')
        return
      end

      if intermediates.empty? && (final == 'h' || final == 'l')
        set_ansi_modes(params, final == 'h')
        return
      end

      case final
      when 'A'
        move_cursor_vertical(-pn(params, 0))
      when 'B'
        move_cursor_vertical(pn(params, 0))
      when 'C'
        move_cursor(row: @cursor_row, col: @cursor_col + pn(params, 0))
      when 'D'
        move_cursor(row: @cursor_row, col: @cursor_col - pn(params, 0))
      when 'E'
        move_cursor_vertical(pn(params, 0))
        @cursor_col = 0
      when 'F'
        move_cursor_vertical(-pn(params, 0))
        @cursor_col = 0
      when 'G'
        move_cursor(row: @cursor_row, col: one_based(params, 0) - 1)
      when 'd'
        vpa(one_based(params, 0))
      when 'H', 'f'
        cup(one_based(params, 0), one_based(params, 1))
      when 'J'
        erase_display(param(params, 0, 0))
      when 'K'
        erase_line(param(params, 0, 0))
      when '@'
        insert_chars(pn(params, 0))
      when 'P'
        delete_chars(pn(params, 0))
      when 'X'
        erase_chars(pn(params, 0))
      when 'L'
        insert_lines(pn(params, 0))
      when 'M'
        delete_lines(pn(params, 0))
      when 'S'
        scroll_up(pn(params, 0))
      when 'T'
        scroll_down(pn(params, 0))
      when 'I'
        with_empty_intermediates(params, intermediates, final) do
          @pending_wrap = false
          horizontal_tab(pn(params, 0))
        end
      when 'Z'
        with_empty_intermediates(params, intermediates, final) do
          @pending_wrap = false
          back_tab(pn(params, 0))
        end
      when 'g'
        with_empty_intermediates(params, intermediates, final) do
          clear_tab_stops(param(params, 0, 0))
        end
      when 'r'
        with_empty_intermediates(params, intermediates, final) do
          set_scroll_region(param(params, 0, 1), param(params, 1, @rows))
        end
      when 's'
        save_cursor
      when 'u'
        restore_cursor
      when 'm'
        apply_sgr(params)
      when 'n'
        if intermediates.empty? && param(params, 0, 0) == 6
          report_cursor_position
        else
          csi_unhandled(params, intermediates, final)
        end
      else
        csi_unhandled(params, intermediates, final)
      end
    end

    def osc_dispatch(data : String)
      command, separator, value = data.partition(';')
      @title = value if (command == "0" || command == "2") && !separator.empty?
    end

    def resize(rows : Int32, cols : Int32) : self
      new_rows = {rows, 1}.max
      new_cols = {cols, 1}.max
      old_cols = @cols
      old_rows = @rows

      if @reflow && (new_cols != old_cols || new_rows != old_rows)
        if new_cols != old_cols
          reflow_primary(new_rows, new_cols)
        else
          resize_primary_rows(new_rows)
        end
        @alternate = resize_grid_to(@alternate, new_rows, new_cols)
        @rows = new_rows
        @cols = new_cols
        if @alt_screen
          clamp_cursor
          @pending_wrap = false if @cursor_col < @cols - 1
        end
      else
        @rows = new_rows
        @cols = new_cols
        @primary = resize_grid(@primary)
        @primary_wrapped = resize_wrap_flags(@primary_wrapped)
        @alternate = resize_grid(@alternate)
        clamp_cursor
        @pending_wrap = false if @cursor_col < @cols - 1
      end

      reset_scroll_region
      @tab_stops.resize(old_cols, @cols)
      self
    end

    def row_text(row : Int32) : String
      row_to_text(grid[row])
    end

    def rows_text : Array(String)
      grid.map { |row| row_to_text(row) }
    end

    def text : String
      rows = rows_text
      while rows.last?.try(&.empty?)
        rows.pop
      end
      rows.join('\n')
    end

    def to_s(io : IO) : Nil
      io << text
    end

    def cell(row : Int32, col : Int32) : Cell
      grid[row][col]
    end

    def cursor : NamedTuple(row: Int32, col: Int32)
      {row: @cursor_row, col: @cursor_col}
    end

    def cursor_visible? : Bool
      @cursor_visible
    end

    def alt_screen? : Bool
      @alt_screen
    end

    def reflow? : Bool
      @reflow
    end

    # True when the primary row soft-wraps into the next row (for specs/debug).
    def row_wrapped?(row : Int32) : Bool
      return false if row < 0 || row >= @primary_wrapped.size

      @primary_wrapped[row]
    end

    def mouse_tracking : MouseTracking
      @mouse_tracking
    end

    def mouse_encoding : MouseEncoding
      @mouse_encoding
    end

    def focus_reporting? : Bool
      @focus_reporting
    end

    def bracketed_paste? : Bool
      @bracketed_paste
    end

    def scrollback_text : Array(String)
      @scrollback.map { |row| row_to_text(row) }.to_a
    end

    def dup : self
      copy = Screen.new(@rows, @cols, @scrollback_limit, reflow: @reflow)
      copy.copy_from(self)
      copy
    end

    protected def copy_from(source : Screen) : Nil
      @primary = clone_grid(source.primary_for_copy)
      @alternate = clone_grid(source.alternate_for_copy)
      @scrollback = source.scrollback_for_copy
      @primary_wrapped = source.primary_wrapped_for_copy
      @scrollback_wrapped = source.scrollback_wrapped_for_copy
      @reflow = source.reflow?
      @cursor_row = source.cursor_row_for_copy
      @cursor_col = source.cursor_col_for_copy
      @cursor_visible = source.cursor_visible?
      @pending_wrap = source.pending_wrap_for_copy
      @style = source.style_for_copy
      @saved_primary = source.saved_primary_for_copy
      @saved_alternate = source.saved_alternate_for_copy
      @autowrap = source.autowrap_for_copy
      @alt_screen = source.alt_screen?
      @scroll_top = source.scroll_top_for_copy
      @scroll_bottom = source.scroll_bottom_for_copy
      @origin_mode = source.origin_mode_for_copy
      @insert_mode = source.insert_mode_for_copy
      @tab_stops = source.tab_stops_for_copy
      @mouse_tracking = source.mouse_tracking
      @mouse_encoding = source.mouse_encoding
      @focus_reporting = source.focus_reporting?
      @bracketed_paste = source.bracketed_paste?
      @title = source.title
      @bell_count = source.bell_count
      @unhandled = source.unhandled.dup
      @on_report = source.on_report
    end

    protected def primary_for_copy
      @primary
    end

    protected def alternate_for_copy
      @alternate
    end

    protected def scrollback_for_copy
      clone_scrollback
    end

    protected def cursor_row_for_copy
      @cursor_row
    end

    protected def cursor_col_for_copy
      @cursor_col
    end

    protected def pending_wrap_for_copy
      @pending_wrap
    end

    protected def style_for_copy
      @style
    end

    protected def saved_primary_for_copy
      @saved_primary
    end

    protected def saved_alternate_for_copy
      @saved_alternate
    end

    protected def autowrap_for_copy
      @autowrap
    end

    protected def scroll_top_for_copy
      @scroll_top
    end

    protected def scroll_bottom_for_copy
      @scroll_bottom
    end

    protected def origin_mode_for_copy
      @origin_mode
    end

    protected def insert_mode_for_copy
      @insert_mode
    end

    protected def tab_stops_for_copy
      @tab_stops.dup
    end

    protected def primary_wrapped_for_copy
      @primary_wrapped.dup
    end

    protected def scrollback_wrapped_for_copy
      copy = Deque(Bool).new
      @scrollback_wrapped.each { |flag| copy << flag }
      copy
    end

    private def build_grid : Array(Array(Cell))
      Array.new(@rows) { blank_row }
    end

    private def clone_grid(source : Array(Array(Cell))) : Array(Array(Cell))
      source.map(&.dup)
    end

    private def clone_scrollback : Deque(Array(Cell))
      copy = Deque(Array(Cell)).new
      @scrollback.each { |row| copy << row.dup }
      copy
    end

    private def blank_row(style : Style = Style::DEFAULT) : Array(Cell)
      Array.new(@cols) { Cell.blank(style) }
    end

    private def grid : Array(Array(Cell))
      @alt_screen ? @alternate : @primary
    end

    private def current_row : Array(Cell)
      grid[@cursor_row]
    end

    private def row_to_text(row : Array(Cell)) : String
      String.build do |io|
        row.each do |cell|
          next if cell.continuation

          io << cell.char
          io << cell.extras if cell.extras
        end
      end.rstrip
    end

    private def advance_after_print(width : Int32) : Nil
      if @autowrap
        if @cursor_col + width >= @cols
          @cursor_col = @cols - 1
          @pending_wrap = true
        else
          @cursor_col += width
          @pending_wrap = false
        end
      else
        @cursor_col = {@cursor_col + width, @cols - 1}.min
        @pending_wrap = false
      end
    end

    private def wrap_pending : Nil
      mark_row_wrapped(@cursor_row) unless @alt_screen
      @pending_wrap = false
      @cursor_col = 0
      index
    end

    private def mark_row_wrapped(row : Int32) : Nil
      return unless row >= 0 && row < @primary_wrapped.size

      @primary_wrapped[row] = true
    end

    private def clear_row_wrapped(row : Int32) : Nil
      return unless row >= 0 && row < @primary_wrapped.size

      @primary_wrapped[row] = false
    end

    private def clear_wide_pair_at(row : Int32, col : Int32) : Nil
      target = grid[row][col]

      if target.continuation && col > 0
        grid[row][col - 1] = Cell.blank
        grid[row][col] = Cell.blank
      elsif target.width == 2
        grid[row][col] = Cell.blank
        grid[row][col + 1] = Cell.blank if col + 1 < @cols && grid[row][col + 1].continuation
      end
    end

    private def erase_display(mode : Int32) : Nil
      case mode
      when 0
        erase_row_range(@cursor_row, @cursor_col, @cols - 1)
        (@cursor_row + 1...@rows).each { |row| erase_row(row) }
      when 1
        (0...@cursor_row).each { |row| erase_row(row) }
        erase_row_range(@cursor_row, 0, @cursor_col)
      when 2
        (0...@rows).each { |row| erase_row(row) }
      when 3
        @scrollback.clear
        @scrollback_wrapped.clear
      else
        record_unhandled("CSI #{mode}J")
      end
    end

    private def erase_line(mode : Int32) : Nil
      case mode
      when 0
        erase_row_range(@cursor_row, @cursor_col, @cols - 1)
      when 1
        erase_row_range(@cursor_row, 0, @cursor_col)
      when 2
        erase_row(@cursor_row)
      else
        record_unhandled("CSI #{mode}K")
      end
    end

    private def erase_row(row : Int32) : Nil
      erase_row_range(row, 0, @cols - 1)
    end

    private def erase_row_range(row : Int32, first : Int32, last : Int32) : Nil
      lo = first.clamp(0, @cols - 1)
      hi = last.clamp(0, @cols - 1)
      lo.upto(hi) do |col|
        grid[row][col] = Cell.blank(@style)
      end
      # Soft-wrap is broken once the last column is erased (full or partial EL/ED).
      clear_row_wrapped(row) if !@alt_screen && hi >= @cols - 1 && lo <= @cols - 1
    end

    private def insert_chars(count : Int32) : Nil
      count = {count, @cols - @cursor_col}.min
      row = current_row
      count.times { row.insert(@cursor_col, Cell.blank(@style)) }
      row.pop(count)
      # Only clear an orphaned wide lead on the last column (no room for a
      # continuation). A complete pair ending in a continuation must stay.
      if row[@cols - 1].width == 2
        row[@cols - 1] = Cell.blank
      end
    end

    private def delete_chars(count : Int32) : Nil
      count = {count, @cols - @cursor_col}.min
      row = current_row
      count.times { row.delete_at(@cursor_col) }
      count.times { row << Cell.blank(@style) }
    end

    private def erase_chars(count : Int32) : Nil
      last = {@cursor_col + count - 1, @cols - 1}.min
      erase_row_range(@cursor_row, @cursor_col, last)
    end

    private def reset_screen_preserving_title : Nil
      title = @title
      initialize(@rows, @cols, @scrollback_limit, reflow: @reflow)
      @title = title
    end

    private def apply_sgr(params : Array(CSIParam)) : Nil
      params = [CSIParam.new("", 0)] if params.empty?
      index = 0

      while index < params.size
        param = params[index]
        case param.value
        when 0
          @style = Style::DEFAULT
        when 1
          @style.bold = true
        when 2
          @style.dim = true
        when 3
          @style.italic = true
        when 4
          @style.underline = true
        when 5
          @style.blink = true
        when 7
          @style.inverse = true
        when 8
          @style.hidden = true
        when 9
          @style.strikethrough = true
        when 21, 22
          @style.bold = false
          @style.dim = false
        when 23
          @style.italic = false
        when 24
          @style.underline = false
        when 25
          @style.blink = false
        when 27
          @style.inverse = false
        when 28
          @style.hidden = false
        when 29
          @style.strikethrough = false
        when 30..37
          @style.fg = Color.indexed(param.value - 30)
        when 40..47
          @style.bg = Color.indexed(param.value - 40)
        when 90..97
          @style.fg = Color.indexed(param.value - 90 + 8)
        when 100..107
          @style.bg = Color.indexed(param.value - 100 + 8)
        when 38
          index = apply_extended_color(params, index, foreground: true)
        when 48
          index = apply_extended_color(params, index, foreground: false)
        when 39
          @style.fg = Color::DEFAULT
        when 49
          @style.bg = Color::DEFAULT
        else
          record_unhandled("SGR #{param.raw}") unless param.raw.empty?
        end

        index += 1
      end
    end

    private def apply_extended_color(params : Array(CSIParam), index : Int32, foreground : Bool) : Int32
      param = params[index]

      if param.subparams.size >= 1
        case param.subparams[0]
        when 5
          set_color(Color.indexed(param.subparams[1]? || 0), foreground) if param.subparams.size >= 2
        when 2
          # 38:2:r:g:b (3 components) or ITU form 38:2:<colorspace>:r:g:b (4+)
          components = param.subparams[1..]
          components = components[1..] if components.size >= 4
          if components.size >= 3
            set_color(Color.rgb(components[0], components[1], components[2]), foreground)
          end
        end

        return index
      end

      mode = params[index + 1]?.try(&.value)
      case mode
      when 5
        set_color(Color.indexed(params[index + 2]?.try(&.value) || 0), foreground)
        index + 2
      when 2
        red = params[index + 2]?.try(&.value)
        green = params[index + 3]?.try(&.value)
        blue = params[index + 4]?.try(&.value)
        set_color(Color.rgb(red || 0, green || 0, blue || 0), foreground) if red && green && blue
        index + 4
      else
        index
      end
    end

    private def set_color(color : Color, foreground : Bool) : Nil
      if foreground
        @style.fg = color
      else
        @style.bg = color
      end
    end

    private def report_cursor_position : Nil
      if callback = @on_report
        # Under DECOM, CPR reports origin-relative row (xterm/VT100); column
        # stays absolute.
        row = @origin_mode ? (@cursor_row - @scroll_top) + 1 : @cursor_row + 1
        col = @cursor_col + 1
        callback.call("\e[#{row};#{col}R".to_slice.dup)
      end
    end

    private def with_empty_intermediates(params : Array(CSIParam), intermediates : String, final : Char, &) : Nil
      if intermediates.empty?
        yield
      else
        csi_unhandled(params, intermediates, final)
      end
    end

    private def csi_unhandled(params : Array(CSIParam), intermediates : String, final : Char) : Nil
      record_unhandled("CSI #{intermediates}#{params.map(&.raw).join(';')}#{final}")
    end

    private def param(params : Array(CSIParam), index : Int32, default : Int32) : Int32
      params[index]?.try(&.value) || default
    end

    private def pn(params : Array(CSIParam), index : Int32) : Int32
      value = param(params, index, 1)
      value == 0 ? 1 : value
    end

    private def one_based(params : Array(CSIParam), index : Int32) : Int32
      pn(params, index)
    end

    private def charset_designation?(intermediates : String, final : Char) : Bool
      return false unless intermediates.size == 1

      ['(', ')', '*', '+', '-', '.', '/'].includes?(intermediates[0]) && final >= '0' && final <= '~'
    end

    private def resize_grid(source : Array(Array(Cell))) : Array(Array(Cell))
      resize_grid_to(source, @rows, @cols)
    end

    private def resize_grid_to(source : Array(Array(Cell)), rows : Int32, cols : Int32) : Array(Array(Cell))
      resized_rows = source.first(rows).map do |row|
        resized = row.first(cols)
        resized += Array.new(cols - resized.size) { Cell.blank } if resized.size < cols
        resized
      end

      while resized_rows.size < rows
        resized_rows << Array.new(cols) { Cell.blank }
      end
      resized_rows
    end

    private def resize_wrap_flags(source : Array(Bool)) : Array(Bool)
      flags = source.first(@rows)
      while flags.size < @rows
        flags << false
      end
      flags
    end

    private def record_unhandled(description : String) : Nil
      @unhandled << description
      while @unhandled.size > 100
        @unhandled.shift
      end
    end
  end
end

require "./screen/scroll"
require "./screen/reflow"
require "./screen/cursor"
require "./screen/modes"
require "./screen/tabs"
