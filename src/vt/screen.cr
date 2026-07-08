require "./cell"
require "./parser"
require "./width"

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
    @parser : Parser?
    @style : Style
    @saved_primary : SavedCursor
    @saved_alternate : SavedCursor
    @scroll_top : Int32
    @scroll_bottom : Int32
    @origin_mode : Bool
    @insert_mode : Bool
    @tab_stops : Set(Int32)

    def initialize(rows : Int32 = 24, cols : Int32 = 80, scrollback : Int32 = 1000)
      @rows = {rows, 1}.max
      @cols = {cols, 1}.max
      @scrollback_limit = {scrollback, 0}.max
      @primary = build_grid
      @alternate = build_grid
      @scrollback = Deque(Array(Cell)).new
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
      @tab_stops = default_tab_stops(@cols)
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
      return if width == 0

      wrap_pending if @pending_wrap
      wrap_pending if width == 2 && @autowrap && @cursor_col == @cols - 1

      if @insert_mode
        insert_chars(width)
        clear_wide_pair_at(@cursor_row, @cols - 1)
      end

      row = current_row
      clear_wide_pair_at(@cursor_row, @cursor_col)
      row[@cursor_col] = Cell.new(char: char, style: @style, width: width.to_i8)

      if width == 2 && @cursor_col + 1 < @cols
        clear_wide_pair_at(@cursor_row, @cursor_col + 1)
        row[@cursor_col + 1] = Cell.new(style: @style, continuation: true)
      end

      advance_after_print(width)
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
        @tab_stops << @cursor_col
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
        n = pn(params, 0)
        target = @cursor_row - n
        if inside_scroll_region?
          target = {target, @scroll_top}.max
        end
        move_cursor(row: target, col: @cursor_col)
      when 'B'
        n = pn(params, 0)
        target = @cursor_row + n
        if inside_scroll_region?
          target = {target, @scroll_bottom}.min
        end
        move_cursor(row: target, col: @cursor_col)
      when 'C'
        move_cursor(row: @cursor_row, col: @cursor_col + pn(params, 0))
      when 'D'
        move_cursor(row: @cursor_row, col: @cursor_col - pn(params, 0))
      when 'E'
        move_cursor(row: @cursor_row + pn(params, 0), col: 0)
      when 'F'
        move_cursor(row: @cursor_row - pn(params, 0), col: 0)
      when 'G'
        move_cursor(row: @cursor_row, col: one_based(params, 0) - 1)
      when 'd'
        row = one_based(params, 0) - 1
        row += @scroll_top if @origin_mode
        move_cursor(row: row, col: @cursor_col)
      when 'H', 'f'
        row = one_based(params, 0) - 1
        col = one_based(params, 1) - 1
        row += @scroll_top if @origin_mode
        move_cursor(row: row, col: col)
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
        if intermediates.empty?
          @pending_wrap = false
          horizontal_tab(pn(params, 0))
        else
          record_unhandled("CSI #{intermediates}#{params.map(&.raw).join(';')}#{final}")
        end
      when 'Z'
        if intermediates.empty?
          @pending_wrap = false
          back_tab(pn(params, 0))
        else
          record_unhandled("CSI #{intermediates}#{params.map(&.raw).join(';')}#{final}")
        end
      when 'g'
        if intermediates.empty?
          clear_tab_stops(param(params, 0, 0))
        else
          record_unhandled("CSI #{intermediates}#{params.map(&.raw).join(';')}#{final}")
        end
      when 'r'
        if intermediates.empty?
          set_scroll_region(param(params, 0, 1), param(params, 1, @rows))
        else
          record_unhandled("CSI #{intermediates}#{params.map(&.raw).join(';')}#{final}")
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
          record_unhandled("CSI #{intermediates}#{params.map(&.raw).join(';')}#{final}")
        end
      else
        record_unhandled("CSI #{intermediates}#{params.map(&.raw).join(';')}#{final}")
      end
    end

    def osc_dispatch(data : String)
      command, separator, value = data.partition(';')
      @title = value if (command == "0" || command == "2") && !separator.empty?
    end

    def resize(rows : Int32, cols : Int32) : self
      old_cols = @cols
      @rows = {rows, 1}.max
      @cols = {cols, 1}.max
      @primary = resize_grid(@primary)
      @alternate = resize_grid(@alternate)
      @scroll_top = 0
      @scroll_bottom = @rows - 1
      resize_tab_stops(old_cols)
      clamp_cursor
      @pending_wrap = false if @cursor_col < @cols - 1
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

    def scrollback_text : Array(String)
      @scrollback.map { |row| row_to_text(row) }.to_a
    end

    def dup : self
      copy = Screen.new(@rows, @cols, @scrollback_limit)
      copy.copy_from(self)
      copy
    end

    protected def copy_from(source : Screen) : Nil
      @primary = clone_grid(source.primary_for_copy)
      @alternate = clone_grid(source.alternate_for_copy)
      @scrollback = source.scrollback_for_copy
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
      @pending_wrap = false
      @cursor_col = 0
      index
    end

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
        removed = grid[@scroll_top]
        (@scroll_top...@scroll_bottom).each do |row|
          grid[row] = grid[row + 1]
        end
        grid[@scroll_bottom] = blank_row
        push_scrollback(removed) if full_region && !@alt_screen
      end
    end

    private def scroll_down(count : Int32) : Nil
      count.times do
        @scroll_bottom.downto(@scroll_top + 1) do |row|
          grid[row] = grid[row - 1]
        end
        grid[@scroll_top] = blank_row
      end
    end

    private def push_scrollback(row : Array(Cell)) : Nil
      return if @scrollback_limit == 0

      @scrollback << row
      while @scrollback.size > @scrollback_limit
        @scrollback.shift
      end
    end

    private def move_cursor(row : Int32, col : Int32) : Nil
      @pending_wrap = false
      if @origin_mode
        @cursor_row = row.clamp(@scroll_top, @scroll_bottom)
      else
        @cursor_row = row.clamp(0, @rows - 1)
      end
      @cursor_col = col.clamp(0, @cols - 1)
    end

    private def clamp_cursor : Nil
      if @origin_mode
        @cursor_row = @cursor_row.clamp(@scroll_top, @scroll_bottom)
      else
        @cursor_row = @cursor_row.clamp(0, @rows - 1)
      end
      @cursor_col = @cursor_col.clamp(0, @cols - 1)
    end

    private def home_cursor : Nil
      if @origin_mode
        move_cursor(row: @scroll_top, col: 0)
      else
        move_cursor(row: 0, col: 0)
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
      first.clamp(0, @cols - 1).upto(last.clamp(0, @cols - 1)) do |col|
        grid[row][col] = Cell.blank(@style)
      end
    end

    private def insert_chars(count : Int32) : Nil
      count = {count, @cols - @cursor_col}.min
      row = current_row
      count.times { row.insert(@cursor_col, Cell.blank(@style)) }
      row.pop(count)
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

    private def insert_lines(count : Int32) : Nil
      return unless inside_scroll_region?

      count = {count, @scroll_bottom - @cursor_row + 1}.min
      count.times do
        @scroll_bottom.downto(@cursor_row + 1) do |row|
          grid[row] = grid[row - 1]
        end
        grid[@cursor_row] = blank_row
      end
    end

    private def delete_lines(count : Int32) : Nil
      return unless inside_scroll_region?

      count = {count, @scroll_bottom - @cursor_row + 1}.min
      count.times do
        (@cursor_row...@scroll_bottom).each do |row|
          grid[row] = grid[row + 1]
        end
        grid[@scroll_bottom] = blank_row
      end
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

    private def default_tab_stops(cols : Int32) : Set(Int32)
      stops = Set(Int32).new
      col = 8
      while col < cols
        stops << col
        col += 8
      end
      stops
    end

    private def resize_tab_stops(old_cols : Int32) : Nil
      @tab_stops = @tab_stops.select { |col| col < @cols }.to_set
      return unless @cols > old_cols

      col = 8
      while col < @cols
        @tab_stops << col if col >= old_cols
        col += 8
      end
    end

    private def horizontal_tab(count : Int32) : Nil
      count.times do
        next_stop = @tab_stops.select { |col| col > @cursor_col }.min?
        @cursor_col = next_stop || (@cols - 1)
      end
    end

    private def back_tab(count : Int32) : Nil
      count.times do
        prev_stop = @tab_stops.select { |col| col < @cursor_col }.max?
        @cursor_col = prev_stop || 0
      end
    end

    private def clear_tab_stops(mode : Int32) : Nil
      case mode
      when 0
        @tab_stops.delete(@cursor_col)
      when 3
        @tab_stops.clear
      else
        record_unhandled("CSI #{mode}g")
      end
    end

    private def reset_screen_preserving_title : Nil
      title = @title
      initialize(@rows, @cols, @scrollback_limit)
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
        callback.call("\e[#{@cursor_row + 1};#{@cursor_col + 1}R".to_slice)
      end
    end

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
      rows = source.first(@rows).map do |row|
        resized = row.first(@cols)
        resized += Array.new(@cols - resized.size) { Cell.blank } if resized.size < @cols
        resized
      end

      while rows.size < @rows
        rows << blank_row
      end
      rows
    end

    private def record_unhandled(description : String) : Nil
      @unhandled << description
      while @unhandled.size > 100
        @unhandled.shift
      end
    end
  end
end
