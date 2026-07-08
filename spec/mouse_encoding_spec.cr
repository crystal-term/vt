require "./spec_helper"

describe Term::VT::Mouse do
  it "encodes SGR press and release byte-for-byte" do
    press = Term::VT::Mouse.encode(2, 4, Term::VT::MouseButton::Left, encoding: Term::VT::MouseEncoding::Sgr)
    String.new(press).should eq("\e[<0;5;3M")

    release = Term::VT::Mouse.encode(2, 4, Term::VT::MouseButton::Left, release: true, encoding: Term::VT::MouseEncoding::Sgr)
    String.new(release).should eq("\e[<0;5;3m")

    middle = Term::VT::Mouse.encode(0, 0, Term::VT::MouseButton::Middle, encoding: Term::VT::MouseEncoding::Sgr)
    String.new(middle).should eq("\e[<1;1;1M")

    right = Term::VT::Mouse.encode(0, 0, Term::VT::MouseButton::Right, encoding: Term::VT::MouseEncoding::Sgr)
    String.new(right).should eq("\e[<2;1;1M")
  end

  it "encodes SGR motion with bit 32 set" do
    motion = Term::VT::Mouse.encode(1, 2, Term::VT::MouseButton::Left, motion: true, encoding: Term::VT::MouseEncoding::Sgr)
    String.new(motion).should eq("\e[<32;3;2M")
  end

  it "encodes wheel buttons as 64/65" do
    up = Term::VT::Mouse.encode(0, 0, Term::VT::MouseButton::WheelUp, encoding: Term::VT::MouseEncoding::Sgr)
    String.new(up).should eq("\e[<64;1;1M")

    down = Term::VT::Mouse.encode(0, 0, Term::VT::MouseButton::WheelDown, encoding: Term::VT::MouseEncoding::Sgr)
    String.new(down).should eq("\e[<65;1;1M")
  end

  it "encodes X10 press, release, and coordinate cap" do
    # left press at (0,0) → button 0+32, col 1+32, row 1+32
    press = Term::VT::Mouse.encode(0, 0, Term::VT::MouseButton::Left, encoding: Term::VT::MouseEncoding::Default)
    press.should eq(Bytes[0x1b, 0x5b, 0x4d, 32, 33, 33])

    # release always uses button 3 for X10
    release = Term::VT::Mouse.encode(0, 0, Term::VT::MouseButton::Left, release: true, encoding: Term::VT::MouseEncoding::Default)
    release.should eq(Bytes[0x1b, 0x5b, 0x4d, 35, 33, 33])

    # coordinates capped at 223 (1-based) before +32 → byte 255
    capped = Term::VT::Mouse.encode(300, 400, Term::VT::MouseButton::Left, encoding: Term::VT::MouseEncoding::Default)
    capped.should eq(Bytes[0x1b, 0x5b, 0x4d, 32, 255, 255])
  end

  it "uses X10 for non-SGR encodings (Utf8, Urxvt, Default)" do
    utf8 = Term::VT::Mouse.encode(0, 0, Term::VT::MouseButton::Left, encoding: Term::VT::MouseEncoding::Utf8)
    urxvt = Term::VT::Mouse.encode(0, 0, Term::VT::MouseButton::Left, encoding: Term::VT::MouseEncoding::Urxvt)
    default = Term::VT::Mouse.encode(0, 0, Term::VT::MouseButton::Left, encoding: Term::VT::MouseEncoding::Default)

    utf8.should eq(default)
    urxvt.should eq(default)
  end

  it "rejects negative coordinates" do
    expect_raises(ArgumentError, /mouse row must be non-negative/) do
      Term::VT::Mouse.encode(-1, 0, Term::VT::MouseButton::Left)
    end
    expect_raises(ArgumentError, /mouse col must be non-negative/) do
      Term::VT::Mouse.encode(0, -1, Term::VT::MouseButton::Left)
    end
  end
end
