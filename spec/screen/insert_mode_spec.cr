require "../spec_helper"

describe Term::VT::Screen do
  it "overwrites by default and inserts when IRM is enabled" do
    screen = Term::VT::Screen.new(rows: 1, cols: 8)
    screen.feed("abcdef\e[1;3HXY")
    screen.row_text(0).should eq("abXYef")

    screen = Term::VT::Screen.new(rows: 1, cols: 8)
    screen.feed("abcdef\e[4h\e[1;3HXY")
    screen.row_text(0).should eq("abXYcdef")
  end

  it "restores overwrite when IRM is disabled" do
    screen = Term::VT::Screen.new(rows: 1, cols: 8)
    screen.feed("abcdef\e[4h\e[1;3HX\e[4lY")
    screen.row_text(0).should eq("abXYdef")
  end

  it "inserts a wide character without leaving a dangling continuation at the row edge" do
    screen = Term::VT::Screen.new(rows: 1, cols: 4)
    screen.feed("ab\u{3042}\e[4h\e[1;1HX")

    # Insert shifts the wide lead to the last column and pops its continuation;
    # the dangling lead must be cleared before writing.
    screen.row_text(0).should eq("Xab")
    screen.cell(0, 3).continuation.should be_false
    screen.cell(0, 3).width.should eq(1)
  end

  it "records unknown ANSI modes as unhandled" do
    screen = Term::VT::Screen.new
    screen.feed("\e[2h")

    screen.unhandled.should eq(["CSI 2h"])
  end
end
