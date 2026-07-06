require "../spec_helper"

describe Term::VT::Screen do
  it "sets the title from OSC 0 and OSC 2" do
    screen = Term::VT::Screen.new
    screen.feed("\e]0;first\a")
    screen.title.should eq("first")

    screen.feed("\e]2;second\e\\")
    screen.title.should eq("second")
  end

  it "ignores OSC payloads without a semicolon" do
    screen = Term::VT::Screen.new
    screen.feed("\e]104\a")

    screen.title.should be_nil
    screen.text.should eq("")
  end

  it "sets an explicitly empty title" do
    screen = Term::VT::Screen.new
    screen.feed("\e]0;old\a\e]0;\a")

    screen.title.should eq("")
  end

  it "ignores other OSC commands without recording them as unhandled" do
    screen = Term::VT::Screen.new
    screen.feed("\e]8;id=1;https://example.test\e\\link\e]8;;\e\\")

    screen.text.should eq("link")
    screen.unhandled.should be_empty
  end

  it "counts BEL controls" do
    screen = Term::VT::Screen.new
    screen.feed("\a\a")

    screen.bell_count.should eq(2)
  end

  it "caps primary scrollback" do
    screen = Term::VT::Screen.new(rows: 2, cols: 4, scrollback: 2)
    screen.feed("1111\r\n2222\r\n3333\r\n4444\r\n5555")

    screen.scrollback_text.should eq(["2222", "3333"])
    screen.rows_text.should eq(["4444", "5555"])
  end

  it "resets the screen and scrollback with RIS while preserving the title" do
    screen = Term::VT::Screen.new(rows: 2, cols: 4, scrollback: 5)
    screen.feed("\e]2;kept\a1111\r\n2222\r\n3333")
    screen.scrollback_text.should eq(["1111"])

    screen.feed("\ec")

    screen.text.should eq("")
    screen.scrollback_text.should be_empty
    screen.title.should eq("kept")
    screen.cursor.should eq({row: 0, col: 0})
  end
end
