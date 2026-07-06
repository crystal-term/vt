require "./spec_helper"

private def assert_screen_invariants(screen)
  cursor = screen.cursor
  cursor[:row].should be >= 0
  cursor[:row].should be < screen.rows
  cursor[:col].should be >= 0
  cursor[:col].should be < screen.cols

  lines = screen.snapshot.split('\n')
  lines.size.should eq(screen.rows)
  lines.each do |line|
    line.chars.size.should eq(screen.cols)
  end
end

describe "parser/screen fuzzing" do
  it "does not raise or corrupt grid invariants for random bytes" do
    seed = 0x0220_0001
    random = Random.new(seed)
    bytes = Bytes.new(100_000) { random.rand(256).to_u8 }
    screen = Term::VT::Screen.new(rows: 12, cols: 40, scrollback: 20)
    offset = 0

    while offset < bytes.size
      chunk_size = {random.rand(1..97), bytes.size - offset}.min
      screen.feed(bytes[offset, chunk_size])
      offset += chunk_size
    end

    assert_screen_invariants(screen)
  end

  it "handles valid-looking CSI garbage with absurd params" do
    screen = Term::VT::Screen.new(rows: 8, cols: 20, scrollback: 5)
    garbage = [
      "\e[999999999999999999A",
      "\e[999999999999999999B",
      "\e[999999999999999999C",
      "\e[999999999999999999D",
      "\e[999999999999999999;999999999999999999H",
      "\e[38:2::999999999999999999:0:255mX",
      "\e[48;2;999999999999999999;1;2mY",
      "\e[1;2;3;4;5;6;7;8;9;10;11;12;13;14;15;16;17mZ",
      "\e[999999999999999999@",
      "\e[999999999999999999P",
      "\e[?999999999999999999h",
      "\e]104\a",
      "\e]104\e\\",
      "\e]\a",
      "\e];\a",
      "\e]0\a",
      "\e]4;1;rgb:00/00/00\a",
    ]

    1000.times do |index|
      screen.feed(garbage[index % garbage.size])
    end

    assert_screen_invariants(screen)
  end
end
