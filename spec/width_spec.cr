require "./spec_helper"

describe Term::VT::Width do
  it "reports ASCII printable characters as width 1" do
    Term::VT::Width.of('A').should eq(1)
    Term::VT::Width.of(' ').should eq(1)
  end

  it "reports controls and zero-width joiners as width 0" do
    Term::VT::Width.of('\u{0007}').should eq(0)
    Term::VT::Width.of('\u{200d}').should eq(0)
    Term::VT::Width.of('\u{200c}').should eq(0)
  end

  it "reports combining marks as width 0" do
    Term::VT::Width.of('\u{0301}').should eq(0)
  end

  it "reports East Asian wide and fullwidth characters as width 2" do
    Term::VT::Width.of('\u{3042}').should eq(2)
    Term::VT::Width.of('\u{ff41}').should eq(2)
  end

  it "reports emoji presentation characters as width 2" do
    Term::VT::Width.of('\u{1f600}').should eq(2)
  end

  it "lets a base character plus combining mark occupy one column total" do
    chars = "e\u{0301}".chars
    chars.sum { |char| Term::VT::Width.of(char) }.should eq(1)
  end
end
