require "../spec_helper"

describe Term::VT::Screen do
  it "copies scroll margins, origin mode, insert mode, and tab stops via dup" do
    screen = Term::VT::Screen.new(rows: 6, cols: 20, scrollback: 5)
    screen.feed("\e[2;5r\e[?6h\e[4h\e[1;4H\eH")

    copy = screen.dup

    # Origin mode: CUP 1;1 addresses the top margin.
    copy.feed("\e[1;1H")
    copy.cursor.should eq({row: 1, col: 0})

    # Custom tab stop at column 3 (set on source, copied).
    copy.feed("\t")
    copy.cursor.should eq({row: 1, col: 3})

    # Insert mode is on (CUP row 1 is the top margin under DECOM).
    copy.feed("\e[1;1Hab\e[1;1HX")
    copy.row_text(1).should eq("Xab")

    # Source remains independent and still has origin mode.
    screen.feed("\e[1;1H")
    screen.cursor.should eq({row: 1, col: 0})
    screen.row_text(1).should eq("")
  end

  it "copies scroll margins so partial-region scrolls stay off scrollback" do
    screen = Term::VT::Screen.new(rows: 5, cols: 4, scrollback: 5)
    screen.feed("AAAA\r\nBBBB\r\nCCCC\r\nDDDD\r\nEEEE")
    screen.feed("\e[2;4r")

    copy = screen.dup
    copy.feed("\e[4;1H\n")

    copy.rows_text.should eq(["AAAA", "CCCC", "DDDD", "", "EEEE"])
    copy.scrollback_text.should be_empty
  end

  it "round-trips origin mode through DECSC on a duplicated screen" do
    screen = Term::VT::Screen.new(rows: 6, cols: 8)
    screen.feed("\e[2;5r\e[?6h\e[2;3H\e7")
    copy = screen.dup

    copy.feed("\e[?6l\e[1;1H\e8")
    copy.cursor.should eq({row: 2, col: 2})
    copy.feed("\e[99;1H")
    copy.cursor.should eq({row: 4, col: 0})
  end
end
