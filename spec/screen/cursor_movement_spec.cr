require "../spec_helper"

describe Term::VT::Screen do
  it "handles carriage return, line feed, backspace, and tab" do
    screen = Term::VT::Screen.new(rows: 3, cols: 12)
    screen.feed("ab\bX\tY\rZ\nn")

    screen.row_text(0).should eq("ZX      Y")
    screen.row_text(1).should eq(" n")
    screen.cursor.should eq({row: 1, col: 2})
  end

  it "moves the cursor with CSI relative movement and clamps to edges" do
    screen = Term::VT::Screen.new(rows: 4, cols: 5)
    screen.feed("\e[3;3H")
    screen.feed("\e[A\e[D")
    screen.cursor.should eq({row: 1, col: 1})

    screen.feed("\e[99B\e[99C")
    screen.cursor.should eq({row: 3, col: 4})

    screen.feed("\e[99A\e[99D")
    screen.cursor.should eq({row: 0, col: 0})
  end

  it "supports CNL, CPL, CHA, VPA, CUP, and HVP defaults" do
    screen = Term::VT::Screen.new(rows: 5, cols: 6)
    screen.feed("\e[3;4H\e[E")
    screen.cursor.should eq({row: 3, col: 0})

    screen.feed("\e[F")
    screen.cursor.should eq({row: 2, col: 0})

    screen.feed("\e[5G")
    screen.cursor.should eq({row: 2, col: 4})

    screen.feed("\e[2d")
    screen.cursor.should eq({row: 1, col: 4})

    screen.feed("\e[H")
    screen.cursor.should eq({row: 0, col: 0})

    screen.feed("\e[4;6f")
    screen.cursor.should eq({row: 3, col: 5})
  end

  it "saves and restores cursor position with ESC and CSI forms" do
    screen = Term::VT::Screen.new(rows: 4, cols: 8)
    screen.feed("\e[2;3H\e7\e[4;8H\e8")
    screen.cursor.should eq({row: 1, col: 2})

    screen.feed("\e[s\e[1;1H\e[u")
    screen.cursor.should eq({row: 1, col: 2})
  end

  it "indexes and reverse-indexes with ESC controls" do
    screen = Term::VT::Screen.new(rows: 2, cols: 4, scrollback: 2)
    screen.feed("top\r\eDnext\eD")

    screen.row_text(0).should eq("next")
    screen.scrollback_text.should eq(["top"])

    screen.feed("\e[1;1H\eMup")
    screen.row_text(0).should eq("up")
  end
end
