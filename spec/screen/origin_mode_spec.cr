require "../spec_helper"

describe Term::VT::Screen do
  it "addresses CUP and VPA relative to the top margin when DECOM is set" do
    screen = Term::VT::Screen.new(rows: 6, cols: 8)
    screen.feed("\e[2;5r\e[?6h")

    screen.cursor.should eq({row: 1, col: 0})

    screen.feed("\e[1;1H")
    screen.cursor.should eq({row: 1, col: 0})

    screen.feed("\e[3;2H")
    screen.cursor.should eq({row: 3, col: 1})

    screen.feed("\e[2d")
    screen.cursor.should eq({row: 2, col: 1})
  end

  it "clamps absolute positioning to the scroll margins under origin mode" do
    screen = Term::VT::Screen.new(rows: 6, cols: 8)
    screen.feed("\e[2;5r\e[?6h\e[99;1H")

    screen.cursor.should eq({row: 4, col: 0})
  end

  it "homes the cursor when origin mode is set or reset" do
    screen = Term::VT::Screen.new(rows: 6, cols: 8)
    screen.feed("\e[2;5r\e[4;3H\e[?6h")
    screen.cursor.should eq({row: 1, col: 0})

    screen.feed("\e[3;2H\e[?6l")
    screen.cursor.should eq({row: 0, col: 0})
  end

  it "round-trips origin mode through DECSC and DECRC" do
    screen = Term::VT::Screen.new(rows: 6, cols: 8)
    screen.feed("\e[2;5r\e[?6h\e[2;3H\e7")
    screen.cursor.should eq({row: 2, col: 2})

    screen.feed("\e[?6l\e[1;1H")
    screen.cursor.should eq({row: 0, col: 0})

    screen.feed("\e8")
    screen.cursor.should eq({row: 2, col: 2})

    screen.feed("\e[99;1H")
    screen.cursor.should eq({row: 4, col: 0})
  end

  it "clamps CUU and CUD at the margins when the cursor starts inside them" do
    screen = Term::VT::Screen.new(rows: 6, cols: 8)
    screen.feed("\e[2;5r\e[3;1H\e[99A")
    screen.cursor.should eq({row: 1, col: 0})

    screen.feed("\e[99B")
    screen.cursor.should eq({row: 4, col: 0})
  end
end
