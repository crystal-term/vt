require "./spec_helper"

describe Term::VT::CapturedTTY do
  it "captures written bytes and reports TTY output" do
    io = Term::VT::CapturedTTY.new

    io.tty?.should be_true
    io.print "hello"
    io.print "\e[2K"

    io.output.should eq("hello\e[2K")
    io.bytes.should eq("hello\e[2K".to_slice)
  end

  it "renders captured output into a fresh screen" do
    io = Term::VT::CapturedTTY.new

    io.print "first\r\nsecond"

    screen = io.screen(rows: 3, cols: 10)
    screen.row_text(0).should eq("first")
    screen.row_text(1).should eq("second")

    screen.feed("\rchanged")
    io.screen(rows: 3, cols: 10).row_text(1).should eq("second")
  end

  it "clears the captured bytes" do
    io = Term::VT::CapturedTTY.new

    io.print "before"
    io.clear

    io.output.should eq("")
    io.screen.text.should eq("")
  end
end
