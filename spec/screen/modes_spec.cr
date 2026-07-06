require "../spec_helper"

describe Term::VT::Screen do
  it "toggles cursor visibility with DECTCEM" do
    screen = Term::VT::Screen.new
    screen.cursor_visible?.should be_true

    screen.feed("\e[?25l")
    screen.cursor_visible?.should be_false

    screen.feed("\e[?25h")
    screen.cursor_visible?.should be_true
  end

  it "toggles autowrap with DECAWM" do
    screen = Term::VT::Screen.new(rows: 2, cols: 3)
    screen.feed("\e[?7labcd")

    screen.row_text(0).should eq("abd")
    screen.row_text(1).should eq("")

    screen.feed("\e[?7h\e[2J\e[Habcd")
    screen.row_text(0).should eq("abc")
    screen.row_text(1).should eq("d")
  end

  it "switches to a cleared alternate screen and restores primary cursor for mode 1049" do
    screen = Term::VT::Screen.new(rows: 2, cols: 8)
    screen.feed("main\e[?1049halt")

    screen.alt_screen?.should be_true
    screen.text.should eq("alt")
    screen.cursor.should eq({row: 0, col: 3})

    screen.feed("\e[?1049l")

    screen.alt_screen?.should be_false
    screen.text.should eq("main")
    screen.cursor.should eq({row: 0, col: 4})
  end

  it "keeps alternate-screen scrolling out of primary scrollback" do
    screen = Term::VT::Screen.new(rows: 2, cols: 4, scrollback: 5)
    screen.feed("base\e[?1049h1111\r\n2222\r\n3333")

    screen.text.should eq("2222\n3333")
    screen.scrollback_text.should be_empty
  end

  it "supports legacy alternate screen modes" do
    screen = Term::VT::Screen.new(rows: 1, cols: 6)
    screen.feed("main\e[?47halt")
    screen.alt_screen?.should be_true
    screen.text.should eq("alt")

    screen.feed("\e[?47l")
    screen.alt_screen?.should be_false
    screen.text.should eq("main")
  end

  it "records unknown private modes as unhandled without raising" do
    screen = Term::VT::Screen.new
    screen.feed("\e[?9999h")

    screen.unhandled.should eq(["CSI ?9999h"])
  end
end
