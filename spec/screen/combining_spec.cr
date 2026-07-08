require "../spec_helper"

describe "combining marks and zero-width attachments" do
  it "attaches a combining mark to the preceding base cell" do
    screen = Term::VT::Screen.new(rows: 1, cols: 4)
    screen.feed("e\u{0301}")

    screen.text.should eq("e\u{0301}")
    screen.contains?("e\u{0301}").should be_true
    screen.cell(0, 0).char.should eq('e')
    screen.cell(0, 0).extras.should eq("\u{0301}")
    screen.cursor.should eq({row: 0, col: 1})
  end

  it "appends multiple marks to one base in feed order" do
    screen = Term::VT::Screen.new(rows: 1, cols: 4)
    # e + acute + grave
    screen.feed("e\u{0301}\u{0300}")

    screen.cell(0, 0).char.should eq('e')
    screen.cell(0, 0).extras.should eq("\u{0301}\u{0300}")
    screen.text.should eq("e\u{0301}\u{0300}")
    screen.cursor.should eq({row: 0, col: 1})
  end

  it "attaches a mark to a wide (CJK) lead cell" do
    screen = Term::VT::Screen.new(rows: 1, cols: 4)
    screen.feed("\u{3042}\u{0301}")

    screen.cell(0, 0).char.should eq('\u{3042}')
    screen.cell(0, 0).width.should eq(2)
    screen.cell(0, 0).extras.should eq("\u{0301}")
    screen.cell(0, 1).continuation.should be_true
    screen.cell(0, 1).extras.should be_nil
    screen.row_text(0).should eq("\u{3042}\u{0301}")
  end

  it "attaches a mark while pending_wrap is true to the last column cell" do
    screen = Term::VT::Screen.new(rows: 2, cols: 3)
    screen.feed("abc")
    screen.cursor.should eq({row: 0, col: 2})

    screen.feed("\u{0301}")

    screen.cell(0, 2).char.should eq('c')
    screen.cell(0, 2).extras.should eq("\u{0301}")
    screen.row_text(0).should eq("abc\u{0301}")
    # Cursor and pending wrap are untouched by a width-0 print.
    screen.cursor.should eq({row: 0, col: 2})
    screen.feed("d")
    screen.row_text(1).should eq("d")
  end

  it "attaches a mark after a wide char that filled the line (continuation target)" do
    screen = Term::VT::Screen.new(rows: 2, cols: 4)
    screen.feed("ab\u{3042}")
    screen.cursor.should eq({row: 0, col: 3})

    screen.feed("\u{0301}")

    screen.cell(0, 2).char.should eq('\u{3042}')
    screen.cell(0, 2).extras.should eq("\u{0301}")
    screen.cell(0, 3).continuation.should be_true
    screen.cell(0, 3).extras.should be_nil
    screen.cursor.should eq({row: 0, col: 3})
  end

  it "drops a mark at column 0 of an untouched row" do
    screen = Term::VT::Screen.new(rows: 1, cols: 4)
    screen.feed("\u{0301}")

    screen.cell(0, 0).char.should eq(' ')
    screen.cell(0, 0).extras.should be_nil
    screen.text.should eq("")
    screen.cursor.should eq({row: 0, col: 0})
  end

  it "attaches VS16 without changing cell width or cursor" do
    screen = Term::VT::Screen.new(rows: 1, cols: 4)
    # U+2764 HEART SUIT is narrow under wcwidth; VS16 (U+FE0F) does not widen.
    screen.feed("\u{2764}\u{FE0F}")

    screen.cell(0, 0).char.should eq('\u{2764}')
    screen.cell(0, 0).extras.should eq("\u{FE0F}")
    screen.cell(0, 0).width.should eq(1)
    screen.cursor.should eq({row: 0, col: 1})
    screen.row_text(0).should eq("\u{2764}\u{FE0F}")
  end

  it "clears extras when overwriting a cell" do
    screen = Term::VT::Screen.new(rows: 1, cols: 4)
    screen.feed("e\u{0301}\e[1GX")

    screen.cell(0, 0).char.should eq('X')
    screen.cell(0, 0).extras.should be_nil
    screen.row_text(0).should eq("X")
  end

  it "clears extras on EL and ED" do
    screen = Term::VT::Screen.new(rows: 1, cols: 4)
    screen.feed("e\u{0301}\e[1G\e[2K")
    screen.cell(0, 0).extras.should be_nil
    screen.row_text(0).should eq("")

    screen.feed("e\u{0301}\e[2J")
    screen.cell(0, 0).extras.should be_nil
    screen.text.should eq("")
  end

  it "deep-copies extras via dup so a post-dup feed does not mutate the copy" do
    screen = Term::VT::Screen.new(rows: 1, cols: 4)
    screen.feed("e\u{0301}")
    copy = screen.dup

    screen.feed("\e[1Ga\u{0300}")
    screen.cell(0, 0).char.should eq('a')
    screen.cell(0, 0).extras.should eq("\u{0300}")

    copy.cell(0, 0).char.should eq('e')
    copy.cell(0, 0).extras.should eq("\u{0301}")
  end

  it "does not trigger insert-mode shift for a width-0 char" do
    screen = Term::VT::Screen.new(rows: 1, cols: 6)
    screen.feed("ab\e[4h\e[1G\u{0301}")

    # At column 0 the mark is dropped and must not insert-shift the row.
    screen.row_text(0).should eq("ab")
    screen.cursor.should eq({row: 0, col: 0})

    screen.feed("e\u{0301}")
    # Insert 'e' at col 0 shifts "ab"; the mark attaches without a second shift.
    screen.row_text(0).should eq("e\u{0301}ab")
    screen.cell(0, 0).extras.should eq("\u{0301}")
    screen.cursor.should eq({row: 0, col: 1})
  end
end
