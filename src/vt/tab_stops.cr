module Term::VT
  # Column tab-stop table: one flag per column. Defaults at every multiple of 8.
  struct TabStops
    def initialize(cols : Int32)
      @stops = Array(Bool).new({cols, 0}.max, false)
      apply_defaults(from: 0)
    end

    def initialize(*, stops : Array(Bool))
      @stops = stops
    end

    def dup : TabStops
      TabStops.new(stops: @stops.dup)
    end

    def set(col : Int32) : Nil
      @stops[col] = true if col.in?(0...@stops.size)
    end

    def clear(col : Int32) : Nil
      @stops[col] = false if col.in?(0...@stops.size)
    end

    def clear_all : Nil
      @stops.fill(false)
    end

    def next_after(col : Int32) : Int32?
      ((col + 1)...@stops.size).each do |c|
        return c if @stops[c]
      end
      nil
    end

    def prev_before(col : Int32) : Int32?
      (col - 1).downto(0) do |c|
        return c if @stops[c]
      end
      nil
    end

    # Keep stops that still fit; add default multiples of 8 for columns gained.
    def resize(old_cols : Int32, new_cols : Int32) : Nil
      new_cols = {new_cols, 0}.max
      if new_cols < @stops.size
        @stops = @stops.first(new_cols)
      elsif new_cols > @stops.size
        @stops.concat(Array.new(new_cols - @stops.size, false))
        apply_defaults(from: old_cols)
      end
    end

    private def apply_defaults(from : Int32) : Nil
      col = 8
      while col < @stops.size
        @stops[col] = true if col >= from
        col += 8
      end
    end
  end
end
