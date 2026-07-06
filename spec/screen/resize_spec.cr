require "../spec_helper"

describe Term::VT::Screen do
  it "truncates rows and columns without reflowing content" do
    screen = Term::VT::Screen.new(rows: 3, cols: 5)
    screen.feed("abcde\r\nfghij\r\nklmno")

    screen.resize(rows: 2, cols: 3)

    screen.rows.should eq(2)
    screen.cols.should eq(3)
    screen.rows_text.should eq(["abc", "fgh"])
  end

  it "pads rows and columns with blank cells" do
    screen = Term::VT::Screen.new(rows: 1, cols: 3)
    screen.feed("ab")

    screen.resize(rows: 3, cols: 5)

    screen.rows_text.should eq(["ab", "", ""])
    screen.cell(0, 4).char.should eq(' ')
    screen.cell(2, 4).char.should eq(' ')
  end

  it "clamps the cursor into the resized grid" do
    screen = Term::VT::Screen.new(rows: 4, cols: 6)
    screen.feed("\e[4;6H")

    screen.resize(rows: 2, cols: 3)

    screen.cursor.should eq({row: 1, col: 2})
  end

  it "resizes the alternate buffer independently from the primary view" do
    screen = Term::VT::Screen.new(rows: 2, cols: 5)
    screen.feed("main\e[?1049halt")

    screen.resize(rows: 1, cols: 3)
    screen.text.should eq("alt")

    screen.feed("\e[?1049l")
    screen.text.should eq("mai")
  end
end
