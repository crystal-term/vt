require "./spec_helper"

describe Term::VT::Keys do
  it "maps common editing keys to terminal sequences" do
    Term::VT::Keys.sequence(:enter).should eq("\r")
    Term::VT::Keys.sequence(:tab).should eq("\t")
    Term::VT::Keys.sequence(:escape).should eq("\e")
    Term::VT::Keys.sequence(:backspace).should eq("\u{7f}")
  end

  it "maps navigation and function keys to xterm-compatible sequences" do
    Term::VT::Keys.sequence(:up).should eq("\e[A")
    Term::VT::Keys.sequence(:down).should eq("\e[B")
    Term::VT::Keys.sequence(:right).should eq("\e[C")
    Term::VT::Keys.sequence(:left).should eq("\e[D")
    Term::VT::Keys.sequence(:home).should eq("\e[H")
    Term::VT::Keys.sequence(:end).should eq("\e[F")
    Term::VT::Keys.sequence(:page_up).should eq("\e[5~")
    Term::VT::Keys.sequence(:page_down).should eq("\e[6~")
    Term::VT::Keys.sequence(:f1).should eq("\eOP")
    Term::VT::Keys.sequence(:f12).should eq("\e[24~")
  end

  it "maps Ctrl-A through Ctrl-Z" do
    Term::VT::Keys.sequence(:ctrl_a).bytes.should eq([1])
    Term::VT::Keys.sequence(:ctrl_m).bytes.should eq([13])
    Term::VT::Keys.sequence(:ctrl_z).bytes.should eq([26])
  end

  it "raises for unknown keys" do
    expect_raises(ArgumentError, "unknown key: nope") do
      Term::VT::Keys.sequence(:nope)
    end
  end
end
