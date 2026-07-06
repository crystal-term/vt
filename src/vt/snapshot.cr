require "./screen"

module Term::VT
  class Screen
    def snapshot : String
      String.build do |io|
        @rows.times do |row|
          io << '\n' if row > 0
          @cols.times { |col| io << cell(row, col).char }
        end
      end
    end

    def styled_snapshot : String
      String.build do |io|
        @rows.times do |row|
          io << '\n' if row > 0
          write_styled_row(io, row)
        end
      end
    end

    def find(text : String) : NamedTuple(row: Int32, col: Int32)?
      return nil if text.empty?

      @rows.times do |row|
        row_text, columns = row_text_with_columns(row)
        if byte_index = row_text.index(text)
          char_index = row_text.byte_slice(0, byte_index).chars.size
          return {row: row, col: columns[char_index]} if char_index < columns.size
        end
      end

      nil
    end

    def contains?(text : String) : Bool
      !!find(text)
    end

    private def write_styled_row(io : IO, row_index : Int32) : Nil
      row = grid[row_index]
      return if row.empty?
      last_col = last_styled_column(row)

      unless last_col
        io << "{}"
        return
      end

      current_style = row[0].style
      io << '{' << style_attrs(current_style) << '}'

      row[0..last_col].each do |cell|
        if cell.style != current_style
          current_style = cell.style
          io << '{' << style_attrs(current_style) << '}'
        end

        io << cell.char
      end
    end

    private def last_styled_column(row : Array(Cell)) : Int32?
      index = row.size - 1

      while index >= 0
        cell = row[index]
        return index unless cell.char == ' ' && !cell.continuation && cell.style == Style::DEFAULT
        index -= 1
      end

      nil
    end

    private def style_attrs(style : Style) : String
      attrs = [] of String
      attrs << "bold" if style.bold
      attrs << "dim" if style.dim
      attrs << "italic" if style.italic
      attrs << "underline" if style.underline
      attrs << "blink" if style.blink
      attrs << "inverse" if style.inverse
      attrs << "hidden" if style.hidden
      attrs << "strike" if style.strikethrough
      attrs << "fg=#{color_attr(style.fg)}" unless style.fg.default?
      attrs << "bg=#{color_attr(style.bg)}" unless style.bg.default?
      attrs.join(' ')
    end

    private def color_attr(color : Color) : String
      case color.kind
      when Color::Kind::Indexed
        color.index.to_s
      when Color::Kind::RGB
        "#%02x%02x%02x" % {color.red, color.green, color.blue}
      else
        ""
      end
    end

    private def row_text_with_columns(row_index : Int32) : Tuple(String, Array(Int32))
      columns = [] of Int32
      text = String.build do |io|
        grid[row_index].each_with_index do |cell, col|
          next if cell.continuation

          columns << col
          io << cell.char
        end
      end.rstrip

      while columns.size > text.chars.size
        columns.pop
      end

      {text, columns}
    end
  end
end
