require "../spec_helper"

describe Term::VT::Screen do
  it "scrolls only inside the DECSTBM region on LF at the bottom margin" do
    screen = Term::VT::Screen.new(rows: 5, cols: 4, scrollback: 5)
    screen.feed("AAAA\r\nBBBB\r\nCCCC\r\nDDDD\r\nEEEE")
    screen.feed("\e[2;4r")
    screen.feed("\e[4;1H\n")

    screen.rows_text.should eq(["AAAA", "CCCC", "DDDD", "", "EEEE"])
    screen.scrollback_text.should be_empty
    screen.cursor.should eq({row: 3, col: 0})
  end

  it "reverse-indexes at the top margin and scrolls the region down" do
    screen = Term::VT::Screen.new(rows: 5, cols: 4)
    screen.feed("AAAA\r\nBBBB\r\nCCCC\r\nDDDD\r\nEEEE")
    screen.feed("\e[2;4r\e[2;1H\eM")

    screen.rows_text.should eq(["AAAA", "", "BBBB", "CCCC", "EEEE"])
    screen.cursor.should eq({row: 1, col: 0})
  end

  it "inserts and deletes lines only within the region when the cursor is inside" do
    screen = Term::VT::Screen.new(rows: 5, cols: 4)
    screen.feed("AAAA\r\nBBBB\r\nCCCC\r\nDDDD\r\nEEEE")
    screen.feed("\e[2;4r\e[3;1H\e[L")

    screen.rows_text.should eq(["AAAA", "BBBB", "", "CCCC", "EEEE"])

    screen.feed("\e[3;1H\e[M")
    screen.rows_text.should eq(["AAAA", "BBBB", "CCCC", "", "EEEE"])
  end

  it "no-ops IL and DL when the cursor is outside the margins" do
    screen = Term::VT::Screen.new(rows: 5, cols: 4)
    screen.feed("AAAA\r\nBBBB\r\nCCCC\r\nDDDD\r\nEEEE")
    screen.feed("\e[2;4r\e[1;1H\e[L\e[5;1H\e[M")

    screen.rows_text.should eq(["AAAA", "BBBB", "CCCC", "DDDD", "EEEE"])
  end

  it "limits SU and SD to the scroll region" do
    screen = Term::VT::Screen.new(rows: 5, cols: 4, scrollback: 5)
    screen.feed("AAAA\r\nBBBB\r\nCCCC\r\nDDDD\r\nEEEE")
    screen.feed("\e[2;4r\e[1S")

    screen.rows_text.should eq(["AAAA", "CCCC", "DDDD", "", "EEEE"])
    screen.scrollback_text.should be_empty

    screen.feed("\e[1T")
    screen.rows_text.should eq(["AAAA", "", "CCCC", "DDDD", "EEEE"])
  end

  it "still feeds scrollback on full-screen scrolls" do
    screen = Term::VT::Screen.new(rows: 3, cols: 4, scrollback: 5)
    screen.feed("1111\r\n2222\r\n3333\e[1S")

    screen.rows_text.should eq(["2222", "3333", ""])
    screen.scrollback_text.should eq(["1111"])
  end

  it "resets the region with CSI r and homes the cursor" do
    screen = Term::VT::Screen.new(rows: 5, cols: 4)
    screen.feed("\e[2;4r\e[3;2H\e[r")

    screen.cursor.should eq({row: 0, col: 0})
    screen.feed("AAAA\r\nBBBB\r\nCCCC\r\nDDDD\r\nEEEE\n")
    screen.rows_text.should eq(["BBBB", "CCCC", "DDDD", "EEEE", ""])
  end

  it "ignores invalid scroll regions where Pt >= Pb" do
    screen = Term::VT::Screen.new(rows: 4, cols: 4, scrollback: 2)
    screen.feed("1111\r\n2222\r\n3333\r\n4444")
    screen.feed("\e[3;3r")
    screen.feed("\e[4;1H\n")

    screen.rows_text.should eq(["2222", "3333", "4444", ""])
    screen.scrollback_text.should eq(["1111"])
  end

  it "ignores inverted regions without changing margins" do
    screen = Term::VT::Screen.new(rows: 4, cols: 4, scrollback: 2)
    screen.feed("1111\r\n2222\r\n3333\r\n4444")
    screen.feed("\e[3;1r")
    screen.feed("\e[4;1H\n")

    screen.rows_text.should eq(["2222", "3333", "4444", ""])
    screen.scrollback_text.should eq(["1111"])
  end

  it "resets margins to full screen on resize" do
    screen = Term::VT::Screen.new(rows: 5, cols: 4, scrollback: 2)
    screen.feed("AAAA\r\nBBBB\r\nCCCC\r\nDDDD\r\nEEEE")
    screen.feed("\e[2;4r")
    screen.resize(5, 4)
    screen.feed("\e[5;1H\n")

    screen.rows_text.should eq(["BBBB", "CCCC", "DDDD", "EEEE", ""])
    screen.scrollback_text.should eq(["AAAA"])
  end

  it "keeps a status line outside the region across content scrolls (vim-shaped)" do
    screen = Term::VT::Screen.new(rows: 4, cols: 8)
    screen.feed("line1\r\nline2\r\nline3\r\nSTATUS")
    screen.feed("\e[1;3r\e[3;1H\n\n")

    screen.row_text(3).should eq("STATUS")
    screen.rows_text[0..2].should eq(["line3", "", ""])
  end
end
