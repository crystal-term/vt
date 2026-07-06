require "./spec_helper"

describe "screen snapshots" do
  it "renders an exact padded snapshot with all rows" do
    screen = Term::VT::Screen.new(rows: 2, cols: 5)
    screen.feed("hi")

    screen.snapshot.should eq("hi   \n     ")
  end

  it "renders styled rows as run-length style segments" do
    screen = Term::VT::Screen.new(rows: 1, cols: 12)
    screen.feed("\e[1;32mDone\e[0m in \e[38;2;1;2;3m3s")

    screen.styled_snapshot.should eq("{bold fg=2}Done{} in {fg=#010203}3s")
  end

  it "includes default-style blank rows in styled snapshots" do
    screen = Term::VT::Screen.new(rows: 2, cols: 3)
    screen.feed("ok")

    screen.styled_snapshot.should eq("{}ok\n{}")
  end
end
