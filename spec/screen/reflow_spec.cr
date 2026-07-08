require "../spec_helper"

describe "Screen reflow" do
  it "defaults reflow off and keeps truncate/pad resize" do
    screen = Term::VT::Screen.new(rows: 3, cols: 5)
    screen.reflow?.should be_false
    screen.feed("abcde\r\nfghij\r\nklmno")

    screen.resize(rows: 2, cols: 3)

    screen.rows_text.should eq(["abc", "fgh"])
  end

  it "narrows a soft-wrapped logical line and follows the cursor character" do
    screen = Term::VT::Screen.new(rows: 24, cols: 80, reflow: true)
    screen.feed("A" * 80)
    screen.cursor.should eq({row: 0, col: 79})

    screen.resize(rows: 24, cols: 40)

    screen.cols.should eq(40)
    screen.row_text(0).should eq("A" * 40)
    screen.row_text(1).should eq("A" * 40)
    screen.row_wrapped?(0).should be_true
    screen.row_wrapped?(1).should be_false
    # Cursor was on last col of the 80-col line → offset 79 → col 39 of row 1.
    screen.cursor.should eq({row: 1, col: 39})
  end

  it "widens back and re-joins soft-wrapped content" do
    screen = Term::VT::Screen.new(rows: 4, cols: 80, reflow: true)
    screen.feed("A" * 80)
    screen.resize(rows: 4, cols: 40)
    screen.resize(rows: 4, cols: 80)

    screen.row_text(0).should eq("A" * 80)
    screen.row_text(1).should eq("")
    screen.row_wrapped?(0).should be_false
  end

  it "never splits a wide character across the reflow boundary" do
    screen = Term::VT::Screen.new(rows: 3, cols: 5, reflow: true)
    screen.feed("ab\u{3042}c")
    screen.row_text(0).should eq("ab\u{3042}c")

    screen.resize(rows: 3, cols: 3)

    # Width-2 あ cannot sit after "ab" on a 3-col row; it moves whole to next.
    screen.row_text(0).should eq("ab")
    screen.row_text(1).should eq("\u{3042}c")
    screen.cell(1, 0).width.should eq(2)
    screen.cell(1, 1).continuation.should be_true
  end

  it "overflows the top of the grid into scrollback when narrowing" do
    screen = Term::VT::Screen.new(rows: 2, cols: 10, scrollback: 10, reflow: true)
    screen.feed("AAAAAAAAAA\r\nBBBBBBBBBB")
    screen.resize(rows: 2, cols: 5)

    # Each 10-char line becomes two 5-char rows → 4 physical; visible is the tail.
    screen.rows_text.should eq(["BBBBB", "BBBBB"])
    screen.scrollback_text.should eq(["AAAAA", "AAAAA"])
  end

  it "pulls rows back from scrollback when growing taller with reflow" do
    screen = Term::VT::Screen.new(rows: 2, cols: 5, scrollback: 10, reflow: true)
    screen.feed("AAAAA\r\nBBBBB\r\nCCCCC")
    screen.scrollback_text.should eq(["AAAAA"])
    screen.rows_text.should eq(["BBBBB", "CCCCC"])

    screen.resize(rows: 3, cols: 5)

    screen.scrollback_text.should be_empty
    screen.rows_text.should eq(["AAAAA", "BBBBB", "CCCCC"])
  end

  it "never joins hard newlines across reflow" do
    screen = Term::VT::Screen.new(rows: 4, cols: 20, reflow: true)
    screen.feed("hello\r\nworld")
    screen.resize(rows: 4, cols: 10)

    screen.row_text(0).should eq("hello")
    screen.row_text(1).should eq("world")
    screen.row_wrapped?(0).should be_false
  end

  it "preserves pending-wrap through a reflow round-trip" do
    screen = Term::VT::Screen.new(rows: 3, cols: 4, reflow: true)
    screen.feed("abcd")
    screen.cursor.should eq({row: 0, col: 3})

    screen.resize(rows: 3, cols: 8)
    screen.row_text(0).should eq("abcd")
    # Insertion point was after the line; with room it sits past the content.
    screen.cursor.should eq({row: 0, col: 4})

    screen.resize(rows: 3, cols: 4)
    screen.row_text(0).should eq("abcd")
    screen.cursor.should eq({row: 0, col: 3})
    # Next printable should wrap as before.
    screen.feed("e")
    screen.row_text(1).should eq("e")
  end

  it "truncates the alternate screen even when reflow is enabled" do
    screen = Term::VT::Screen.new(rows: 2, cols: 5, reflow: true)
    screen.feed("main\e[?1049haltxx")

    screen.resize(rows: 2, cols: 3)
    screen.text.should eq("alt")

    screen.feed("\e[?1049l")
    # Primary reflowed while on alt: "main" → "mai"/"n" both fit in 2×3.
    screen.row_text(0).should eq("mai")
    screen.row_text(1).should eq("n")
  end

  it "keeps wrapped flags aligned through full-region scroll so reflow re-joins" do
    screen = Term::VT::Screen.new(rows: 2, cols: 4, scrollback: 5, reflow: true)
    # Soft-wrap 8 chars, then a hard line that scrolls the wrap pair into scrollback+grid.
    screen.feed("AAAABBBB")
    screen.row_wrapped?(0).should be_true
    screen.feed("\r\nCCCC")
    # Scroll: AAAA (wrapped) → scrollback, BBBB and CCCC visible.
    screen.scrollback_text.should eq(["AAAA"])
    screen.rows_text.should eq(["BBBB", "CCCC"])

    screen.resize(rows: 3, cols: 8)

    # AAAA was wrapped into BBBB; reflow re-joins across scrollback.
    screen.scrollback_text.should be_empty
    screen.row_text(0).should eq("AAAABBBB")
    screen.row_text(1).should eq("CCCC")
  end

  it "does not invent pending-wrap after CUP to the last column and reflow" do
    screen = Term::VT::Screen.new(rows: 3, cols: 8, reflow: true)
    screen.feed("abcd\e[1;4H")
    screen.cursor.should eq({row: 0, col: 3})

    screen.resize(rows: 3, cols: 4)

    screen.cursor.should eq({row: 0, col: 3})
    # Next printable overwrites at the cursor, not wrap-pending onto the next row.
    screen.feed("X")
    screen.row_text(0).should eq("abcX")
    screen.row_text(1).should eq("")
  end

  it "clears soft-wrap when EL erases through the last column" do
    screen = Term::VT::Screen.new(rows: 3, cols: 4, reflow: true)
    screen.feed("AAAABBBB")
    screen.row_wrapped?(0).should be_true

    screen.feed("\e[1;1H\e[K")
    screen.row_text(0).should eq("")
    screen.row_wrapped?(0).should be_false

    screen.resize(rows: 3, cols: 8)
    # Blanked row is its own logical line; must not join as leading spaces on BBBB.
    screen.row_text(0).should eq("")
    screen.row_text(1).should eq("BBBB")
  end
end
