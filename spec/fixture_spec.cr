require "./spec_helper"

describe "captured sibling shard fixtures" do
  it "renders the spinner success fixture" do
    screen = Term::VT::Screen.new(rows: 5, cols: 80)
    screen.feed(File.read("spec/fixtures/spinner_success.bin").to_slice)

    screen.text.should eq("[\u{2714}] Loading done")
    screen.unhandled.should be_empty
  end

  it "renders the progress finish fixture" do
    screen = Term::VT::Screen.new(rows: 5, cols: 80)
    screen.feed(File.read("spec/fixtures/progress_finish.bin").to_slice)

    blocks = "\u{2588}" * 10
    screen.text.should eq("Build [#{blocks}] 100% done")
    screen.unhandled.should be_empty
  end
end
