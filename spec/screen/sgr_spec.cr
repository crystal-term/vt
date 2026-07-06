require "../spec_helper"

describe Term::VT::Screen do
  it "applies and resets text attributes structurally" do
    screen = Term::VT::Screen.new(rows: 1, cols: 4)
    screen.feed("\e[1;2;3;4;5;7;8;9mA")

    style = screen.cell(0, 0).style
    style.bold.should be_true
    style.dim.should be_true
    style.italic.should be_true
    style.underline.should be_true
    style.blink.should be_true
    style.inverse.should be_true
    style.hidden.should be_true
    style.strikethrough.should be_true

    screen.feed("\e[22;23;24;25;27;28;29mB")
    screen.cell(0, 1).style.should eq(Term::VT::Style::DEFAULT)
  end

  it "applies standard and bright indexed colors" do
    screen = Term::VT::Screen.new(rows: 1, cols: 4)
    screen.feed("\e[31;44mA\e[91;104mB")

    screen.cell(0, 0).style.fg.should eq(Term::VT::Color.indexed(1))
    screen.cell(0, 0).style.bg.should eq(Term::VT::Color.indexed(4))
    screen.cell(0, 1).style.fg.should eq(Term::VT::Color.indexed(9))
    screen.cell(0, 1).style.bg.should eq(Term::VT::Color.indexed(12))
  end

  it "applies semicolon truecolor and indexed extended colors" do
    screen = Term::VT::Screen.new(rows: 1, cols: 2)
    screen.feed("\e[38;2;1;2;3;48;5;200mA")

    screen.cell(0, 0).style.fg.should eq(Term::VT::Color.rgb(1, 2, 3))
    screen.cell(0, 0).style.bg.should eq(Term::VT::Color.indexed(200))
  end

  it "applies colon truecolor and indexed extended colors" do
    screen = Term::VT::Screen.new(rows: 1, cols: 2)
    screen.feed("\e[38:2::4:5:6;48:5:7mA")

    screen.cell(0, 0).style.fg.should eq(Term::VT::Color.rgb(4, 5, 6))
    screen.cell(0, 0).style.bg.should eq(Term::VT::Color.indexed(7))
  end

  it "applies colon truecolor with zero components" do
    screen = Term::VT::Screen.new(rows: 1, cols: 2)
    screen.feed("\e[38:2::255:0:0mA")

    screen.cell(0, 0).style.fg.should eq(Term::VT::Color.rgb(255, 0, 0))
  end

  it "applies colon truecolor without a colorspace id" do
    screen = Term::VT::Screen.new(rows: 1, cols: 2)
    screen.feed("\e[38:2:0:0:255mA")

    screen.cell(0, 0).style.fg.should eq(Term::VT::Color.rgb(0, 0, 255))
  end

  it "resets foreground, background, and all style state" do
    screen = Term::VT::Screen.new(rows: 1, cols: 4)
    screen.feed("\e[31;42;1mA\e[39;49mB\e[0mC")

    screen.cell(0, 1).style.fg.should eq(Term::VT::Color::DEFAULT)
    screen.cell(0, 1).style.bg.should eq(Term::VT::Color::DEFAULT)
    screen.cell(0, 1).style.bold.should be_true
    screen.cell(0, 2).style.should eq(Term::VT::Style::DEFAULT)
  end
end
