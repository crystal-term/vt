require "../spec_helper"

describe Term::VT::Screen do
  it "erases display from cursor, to cursor, and all visible cells" do
    screen = Term::VT::Screen.new(rows: 3, cols: 5)
    screen.feed("abcde\r\nfghij\r\nklmno")

    screen.feed("\e[2;3H\e[J")
    screen.rows_text.should eq(["abcde", "fg", ""])

    screen.feed("abcde\r\nfghij\r\nklmno")
    screen.feed("\e[2;3H\e[1J")
    screen.rows_text.should eq(["", "   ij", "klmno"])

    screen.feed("\e[2J")
    screen.text.should eq("")
  end

  it "erases parts of the current line" do
    screen = Term::VT::Screen.new(rows: 1, cols: 6)
    screen.feed("abcdef\e[1;3H\e[K")
    screen.row_text(0).should eq("ab")

    screen = Term::VT::Screen.new(rows: 1, cols: 6)
    screen.feed("abcdef\e[1;4H\e[1K")
    screen.row_text(0).should eq("    ef")

    screen = Term::VT::Screen.new(rows: 1, cols: 6)
    screen.feed("abcdef")
    screen.feed("\e[2K")
    screen.row_text(0).should eq("")
  end

  it "inserts, deletes, and erases characters" do
    screen = Term::VT::Screen.new(rows: 1, cols: 8)
    screen.feed("abcdef\e[1;3H\e[2@")
    screen.row_text(0).should eq("ab  cdef")

    screen.feed("\e[1;3H\e[3P")
    screen.row_text(0).should eq("abdef")

    screen.feed("\e[1;2HXYZ\e[1;2H\e[2X")
    screen.row_text(0).should eq("a  Zf")
  end

  it "inserts and deletes full-screen lines at the cursor row" do
    screen = Term::VT::Screen.new(rows: 4, cols: 4)
    screen.feed("aaaa\r\nbbbb\r\ncccc\r\ndddd")

    screen.feed("\e[2;1H\e[L")
    screen.rows_text.should eq(["aaaa", "", "bbbb", "cccc"])

    screen.feed("\e[2;1H\e[M")
    screen.rows_text.should eq(["aaaa", "bbbb", "cccc", ""])
  end

  it "scrolls up and down with CSI S and T" do
    screen = Term::VT::Screen.new(rows: 3, cols: 4, scrollback: 5)
    screen.feed("1111\r\n2222\r\n3333\e[1S")

    screen.rows_text.should eq(["2222", "3333", ""])
    screen.scrollback_text.should eq(["1111"])

    screen.feed("\e[1T")
    screen.rows_text.should eq(["", "2222", "3333"])
  end

  it "clears scrollback with ED 3" do
    screen = Term::VT::Screen.new(rows: 2, cols: 4, scrollback: 5)
    screen.feed("1111\r\n2222\r\n3333")
    screen.scrollback_text.should eq(["1111"])

    screen.feed("\e[3J")
    screen.scrollback_text.should be_empty
    screen.rows_text.should eq(["2222", "3333"])
  end
end
