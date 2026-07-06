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

      def initialize(
        @row : Int32 = 0,
        @col : Int32 = 0,
        @style : Style = Style::DEFAULT,
        @pending_wrap : Bool = false,
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
        @cursor_col = {@cursor_col + (8 - (@cursor_col % 8)), @cols - 1}.min
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

      case final
      when 'A'
        move_cursor(row: @cursor_row - pn(params, 0), col: @cursor_col)
      when 'B'
        move_cursor(row: @cursor_row + pn(params, 0), col: @cursor_col)
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
        move_cursor(row: one_based(params, 0) - 1, col: @cursor_col)
      when 'H', 'f'
        move_cursor(row: one_based(params, 0) - 1, col: one_based(params, 1) - 1)
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
      @rows = {rows, 1}.max
      @cols = {cols, 1}.max
      @primary = resize_grid(@primary)
      @alternate = resize_grid(@alternate)
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
      if @cursor_row == @rows - 1
        scroll_up(1)
      else
        @cursor_row += 1
      end
    end

    private def reverse_index : Nil
      if @cursor_row == 0
        scroll_down(1)
      else
        @cursor_row -= 1
      end
    end

    private def scroll_up(count : Int32) : Nil
      count.times do
        removed = grid.shift
        push_scrollback(removed) unless @alt_screen
        grid << blank_row
      end
    end

    private def scroll_down(count : Int32) : Nil
      count.times do
        grid.pop
        grid.unshift(blank_row)
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
      @cursor_row = row.clamp(0, @rows - 1)
      @cursor_col = col.clamp(0, @cols - 1)
    end

    private def clamp_cursor : Nil
      @cursor_row = @cursor_row.clamp(0, @rows - 1)
      @cursor_col = @cursor_col.clamp(0, @cols - 1)
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
      count = {count, @rows - @cursor_row}.min
      count.times { grid.insert(@cursor_row, blank_row) }
      count.times { grid.pop }
    end

    private def delete_lines(count : Int32) : Nil
      count = {count, @rows - @cursor_row}.min
      count.times { grid.delete_at(@cursor_row) }
      count.times { grid << blank_row }
    end

    private def save_cursor : Nil
      saved = SavedCursor.new(@cursor_row, @cursor_col, @style, @pending_wrap)
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
      clamp_cursor
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
        when 47, 1047
          enabled ? enter_alt_screen(clear: true, save: false) : leave_alt_screen(restore: false)
        when 1049
          enabled ? enter_alt_screen(clear: true, save: true) : leave_alt_screen(restore: true)
        else
          record_unhandled("CSI ?#{param.value}#{enabled ? 'h' : 'l'}")
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
