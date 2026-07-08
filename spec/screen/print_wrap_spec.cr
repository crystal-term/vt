require "../spec_helper"

describe Term::VT::Screen do
  it "prints text into the visible grid" do
    screen = Term::VT::Screen.new(rows: 2, cols: 10)
    screen.feed("hello")

    screen.row_text(0).should eq("hello")
    screen.cursor.should eq({row: 0, col: 5})
  end

  it "keeps the cursor in the last column until the next printable wraps" do
    screen = Term::VT::Screen.new(rows: 2, cols: 3)
    screen.feed("abc")

    screen.row_text(0).should eq("abc")
    screen.cursor.should eq({row: 0, col: 2})

    screen.feed("d")

    screen.row_text(1).should eq("d")
    screen.cursor.should eq({row: 1, col: 1})
  end

  it "wraps a wide character before printing if it cannot fit" do
    screen = Term::VT::Screen.new(rows: 2, cols: 4)
    screen.feed("abc\u{3042}")

    screen.row_text(0).should eq("abc")
    screen.row_text(1).should eq("\u{3042}")
    screen.cell(1, 0).width.should eq(2)
    screen.cell(1, 1).continuation.should be_true
  end

  it "blanks the orphaned half of an overwritten wide character" do
    screen = Term::VT::Screen.new(rows: 1, cols: 4)
    screen.feed("\u{3042}\e[1Gx")

    screen.row_text(0).should eq("x")
    screen.cell(0, 1).continuation.should be_false
  end
end
