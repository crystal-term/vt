require "./spec_helper"

describe "screen query helpers" do
  it "returns trimmed row text, visible text, and to_s text" do
    screen = Term::VT::Screen.new(rows: 3, cols: 6)
    screen.feed("hello\r\nworld")

    screen.row_text(0).should eq("hello")
    screen.rows_text.should eq(["hello", "world", ""])
    screen.text.should eq("hello\nworld")
    screen.to_s.should eq("hello\nworld")
  end

  it "finds visible text by row-major order" do
    screen = Term::VT::Screen.new(rows: 3, cols: 8)
    screen.feed("alpha\r\nbeta\r\ngamma")

    screen.find("ta").should eq({row: 1, col: 2})
    screen.contains?("gamma").should be_true
    screen.contains?("delta").should be_false
  end

  it "maps matches across wide characters back to grid columns" do
    screen = Term::VT::Screen.new(rows: 1, cols: 8)
    screen.feed("\u{3042}bc")

    screen.find("bc").should eq({row: 0, col: 2})
  end
end
