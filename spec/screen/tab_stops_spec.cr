require "../spec_helper"

describe Term::VT::Screen do
  it "advances to default tab stops every 8 columns" do
    screen = Term::VT::Screen.new(rows: 1, cols: 24)
    screen.feed("a\tb\tc")

    screen.row_text(0).should eq("a       b       c")
    screen.cursor.should eq({row: 0, col: 17})
  end

  it "sets a custom stop with HTS and clears with TBC 0" do
    screen = Term::VT::Screen.new(rows: 1, cols: 20)
    screen.feed("\e[1;3H\eH\e[1;1Ha\tb")

    screen.row_text(0).should eq("a b")
    screen.cursor.should eq({row: 0, col: 3})

    screen.feed("\e[1;3H\e[0g\e[2K\e[1;1Hc\td")
    screen.row_text(0).should eq("c       d")
    screen.cursor.should eq({row: 0, col: 9})
  end

  it "clears all tab stops with TBC 3 and HT lands on the last column" do
    screen = Term::VT::Screen.new(rows: 1, cols: 16)
    screen.feed("\e[3g\t")

    screen.cursor.should eq({row: 0, col: 15})

    screen.feed("a")
    screen.row_text(0).should eq("               a")
    screen.cursor.should eq({row: 0, col: 15})
  end

  it "lands on the last column when HT has no remaining stops" do
    screen = Term::VT::Screen.new(rows: 1, cols: 10)
    screen.feed("\e[3g\t")

    screen.cursor.should eq({row: 0, col: 9})
  end

  it "advances and retreats multiple stops with CHT and CBT" do
    screen = Term::VT::Screen.new(rows: 1, cols: 40)
    screen.feed("\e[2I")
    screen.cursor.should eq({row: 0, col: 16})

    screen.feed("\e[1Z")
    screen.cursor.should eq({row: 0, col: 8})

    screen.feed("\e[2Z")
    screen.cursor.should eq({row: 0, col: 0})
  end

  it "keeps fitting stops and adds default stops for new columns on resize" do
    screen = Term::VT::Screen.new(rows: 1, cols: 10)
    screen.feed("\e[1;3H\eH")
    screen.resize(1, 20)
    screen.feed("\e[1;1H\t\t\t")

    # custom stop at 2, default stop at 8 (kept), new default at 16
    screen.cursor.should eq({row: 0, col: 16})
  end

  it "records unknown TBC params as unhandled" do
    screen = Term::VT::Screen.new
    screen.feed("\e[2g")

    screen.unhandled.should eq(["CSI 2g"])
  end
end
