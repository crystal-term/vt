module Term::VT
  class Screen
    private def horizontal_tab(count : Int32) : Nil
      count.times do
        @cursor_col = @tab_stops.next_after(@cursor_col) || (@cols - 1)
      end
    end

    private def back_tab(count : Int32) : Nil
      count.times do
        @cursor_col = @tab_stops.prev_before(@cursor_col) || 0
      end
    end

    private def clear_tab_stops(mode : Int32) : Nil
      case mode
      when 0
        @tab_stops.clear(@cursor_col)
      when 3
        @tab_stops.clear_all
      else
        record_unhandled("CSI #{mode}g")
      end
    end
  end
end
