require "../spec_helper"

describe "screen input mode tracking" do
  it "tracks mouse tracking modes with set/reset/replacement" do
    screen = Term::VT::Screen.new
    screen.mouse_tracking.should eq(Term::VT::MouseTracking::Off)

    screen.feed("\e[?1000h")
    screen.mouse_tracking.should eq(Term::VT::MouseTracking::Normal)

    screen.feed("\e[?1002h")
    screen.mouse_tracking.should eq(Term::VT::MouseTracking::Button)

    screen.feed("\e[?1003h")
    screen.mouse_tracking.should eq(Term::VT::MouseTracking::Any)

    screen.feed("\e[?9h")
    screen.mouse_tracking.should eq(Term::VT::MouseTracking::X10)

    # Resetting an inactive mode is a no-op.
    screen.feed("\e[?1000l")
    screen.mouse_tracking.should eq(Term::VT::MouseTracking::X10)

    # Resetting the active mode returns to Off.
    screen.feed("\e[?9l")
    screen.mouse_tracking.should eq(Term::VT::MouseTracking::Off)
  end

  it "tracks mouse encoding modes with last-set-wins and reset to Default" do
    screen = Term::VT::Screen.new
    screen.mouse_encoding.should eq(Term::VT::MouseEncoding::Default)

    screen.feed("\e[?1006h")
    screen.mouse_encoding.should eq(Term::VT::MouseEncoding::Sgr)

    screen.feed("\e[?1005h")
    screen.mouse_encoding.should eq(Term::VT::MouseEncoding::Utf8)

    screen.feed("\e[?1015h")
    screen.mouse_encoding.should eq(Term::VT::MouseEncoding::Urxvt)

    # Resetting an inactive encoding is a no-op.
    screen.feed("\e[?1006l")
    screen.mouse_encoding.should eq(Term::VT::MouseEncoding::Urxvt)

    screen.feed("\e[?1015l")
    screen.mouse_encoding.should eq(Term::VT::MouseEncoding::Default)
  end

  it "tracks focus reporting and bracketed paste" do
    screen = Term::VT::Screen.new
    screen.focus_reporting?.should be_false
    screen.bracketed_paste?.should be_false

    screen.feed("\e[?1004h\e[?2004h")
    screen.focus_reporting?.should be_true
    screen.bracketed_paste?.should be_true

    screen.feed("\e[?1004l\e[?2004l")
    screen.focus_reporting?.should be_false
    screen.bracketed_paste?.should be_false
  end

  it "does not record tracked input modes as unhandled" do
    screen = Term::VT::Screen.new
    screen.feed("\e[?9h\e[?1000h\e[?1002h\e[?1003h")
    screen.feed("\e[?1005h\e[?1006h\e[?1015h")
    screen.feed("\e[?1004h\e[?2004h")
    screen.feed("\e[?9l\e[?1000l\e[?1002l\e[?1003l")
    screen.feed("\e[?1005l\e[?1006l\e[?1015l")
    screen.feed("\e[?1004l\e[?2004l")

    screen.unhandled.should be_empty
  end

  it "leaves highlight tracking (?1001) unhandled" do
    screen = Term::VT::Screen.new
    screen.feed("\e[?1001h")
    screen.unhandled.should eq(["CSI ?1001h"])
    screen.mouse_tracking.should eq(Term::VT::MouseTracking::Off)
  end

  it "resets all input modes on RIS (ESC c)" do
    screen = Term::VT::Screen.new
    screen.feed("\e[?1000h\e[?1006h\e[?1004h\e[?2004h")
    screen.feed("\ec")

    screen.mouse_tracking.should eq(Term::VT::MouseTracking::Off)
    screen.mouse_encoding.should eq(Term::VT::MouseEncoding::Default)
    screen.focus_reporting?.should be_false
    screen.bracketed_paste?.should be_false
  end

  it "copies input mode state via dup" do
    screen = Term::VT::Screen.new
    screen.feed("\e[?1002h\e[?1006h\e[?1004h\e[?2004h")

    copy = screen.dup
    copy.mouse_tracking.should eq(Term::VT::MouseTracking::Button)
    copy.mouse_encoding.should eq(Term::VT::MouseEncoding::Sgr)
    copy.focus_reporting?.should be_true
    copy.bracketed_paste?.should be_true

    # Source and copy are independent after dup.
    copy.feed("\e[?1002l\e[?1006l\e[?1004l\e[?2004l")
    screen.mouse_tracking.should eq(Term::VT::MouseTracking::Button)
    screen.mouse_encoding.should eq(Term::VT::MouseEncoding::Sgr)
    screen.focus_reporting?.should be_true
    screen.bracketed_paste?.should be_true
  end
end
