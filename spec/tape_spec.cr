require "./spec_helper"
require "../src/cli/tape"

describe Term::VT::CLI::Tape do
  it "parses rows, cols, and run directives" do
    tape = Term::VT::CLI::Tape.parse(%(rows 24 cols 80\nrun sh -c "printf hi"\n))

    rows = tape.directives[0].as(Term::VT::CLI::Tape::Rows)
    cols = tape.directives[1].as(Term::VT::CLI::Tape::Cols)
    run = tape.directives[2].as(Term::VT::CLI::Tape::Run)

    rows.value.should eq(24)
    cols.value.should eq(80)
    run.command.should eq("sh")
    run.args.should eq(["-c", "printf hi"])
  end

  it "parses every action directive" do
    tape = Term::VT::CLI::Tape.parse <<-TAPE
      rows 10
      cols 20
      run sh
      wait "ready" 5s
      idle 50ms 5s
      type "iHello\\n"
      press escape
      click 2 4 left
      paste "clip"
      expect "Hello"
      expect-not "Error"
      snapshot out.txt
      snapshot
      resize 40 120
      send-exit
      expect-exit 0
      TAPE

    tape.directives[0].as(Term::VT::CLI::Tape::Rows).value.should eq(10)
    tape.directives[1].as(Term::VT::CLI::Tape::Cols).value.should eq(20)
    tape.directives[2].as(Term::VT::CLI::Tape::Run).command.should eq("sh")
    tape.directives[3].as(Term::VT::CLI::Tape::Wait).deadline.should eq(5.seconds)
    tape.directives[4].as(Term::VT::CLI::Tape::Idle).settle.should eq(50.milliseconds)
    tape.directives[5].as(Term::VT::CLI::Tape::TypeText).text.should eq("iHello\n")
    tape.directives[6].as(Term::VT::CLI::Tape::Press).key.should eq(:escape)
    click = tape.directives[7].as(Term::VT::CLI::Tape::Click)
    click.row.should eq(2)
    click.col.should eq(4)
    click.button.should eq(Term::VT::MouseButton::Left)
    tape.directives[8].as(Term::VT::CLI::Tape::Paste).text.should eq("clip")
    tape.directives[9].as(Term::VT::CLI::Tape::Expect).text.should eq("Hello")
    tape.directives[10].as(Term::VT::CLI::Tape::ExpectNot).text.should eq("Error")
    tape.directives[11].as(Term::VT::CLI::Tape::Snapshot).file.should eq("out.txt")
    tape.directives[12].as(Term::VT::CLI::Tape::Snapshot).file.should be_nil
    tape.directives[13].as(Term::VT::CLI::Tape::Resize).cols.should eq(120)
    tape.directives[14].should be_a(Term::VT::CLI::Tape::SendExit)
    tape.directives[15].as(Term::VT::CLI::Tape::ExpectExit).code.should eq(0)
  end

  it "defaults click button to left and accepts zero coordinates" do
    tape = Term::VT::CLI::Tape.parse %(run sh\nclick 0 0\n)

    click = tape.directives[1].as(Term::VT::CLI::Tape::Click)
    click.row.should eq(0)
    click.col.should eq(0)
    click.button.should eq(Term::VT::MouseButton::Left)
  end

  it "rejects unknown click buttons with line numbers" do
    expect_raises(Term::VT::CLI::UsageError, "line 2: unknown click button \"side\"") do
      Term::VT::CLI::Tape.parse "run sh\nclick 1 2 side\n"
    end
  end

  it "rejects malformed click coordinates" do
    expect_raises(Term::VT::CLI::UsageError, "line 2: click row must be a non-negative integer") do
      Term::VT::CLI::Tape.parse "run sh\nclick -1 0\n"
    end
  end

  it "rejects unquoted paste text" do
    expect_raises(Term::VT::CLI::UsageError, "line 2: paste text must be a double-quoted string") do
      Term::VT::CLI::Tape.parse "run sh\npaste bare\n"
    end
  end

  it "keeps comments out of tokens but preserves hash characters inside strings" do
    tape = Term::VT::CLI::Tape.parse <<-TAPE
      # comment only
      run printf "# not a comment" # comment
      expect "# not a comment"
      TAPE

    run = tape.directives[0].as(Term::VT::CLI::Tape::Run)
    expect = tape.directives[1].as(Term::VT::CLI::Tape::Expect)

    run.args.should eq(["# not a comment"])
    expect.text.should eq("# not a comment")
  end

  it "parses Crystal-style string escapes" do
    tape = Term::VT::CLI::Tape.parse %(run sh\nexpect "a\\n\\t\\e\\u{2713}\\x21\\"\\\\"\n)

    expect = tape.directives[1].as(Term::VT::CLI::Tape::Expect)
    expect.text.should eq("a\n\t\e\u{2713}!\"\\")
  end

  it "rejects unknown directives with line numbers" do
    expect_raises(Term::VT::CLI::UsageError, "line 2: unknown directive \"bogus\"") do
      Term::VT::CLI::Tape.parse "run sh\nbogus\n"
    end
  end

  it "rejects malformed integer arguments" do
    expect_raises(Term::VT::CLI::UsageError, "line 1: row count must be a positive integer") do
      Term::VT::CLI::Tape.parse "rows nope\nrun sh\n"
    end
  end

  it "rejects action directives before run" do
    expect_raises(Term::VT::CLI::UsageError, "line 1: expect cannot appear before run") do
      Term::VT::CLI::Tape.parse %(expect "ready"\nrun sh\n)
    end
  end

  it "rejects duplicate run directives" do
    expect_raises(Term::VT::CLI::UsageError, "line 2: duplicate run directive") do
      Term::VT::CLI::Tape.parse "run sh\nrun echo no\n"
    end
  end

  it "rejects tapes without a run directive" do
    expect_raises(Term::VT::CLI::UsageError, "tape must contain exactly one run directive") do
      Term::VT::CLI::Tape.parse "rows 24\ncols 80\n"
    end
  end

  it "rejects rows and cols after run" do
    expect_raises(Term::VT::CLI::UsageError, "line 2: rows must appear before run; use resize after run") do
      Term::VT::CLI::Tape.parse "run sh\nrows 10\n"
    end
  end

  it "rejects wait without an explicit deadline" do
    expect_raises(Term::VT::CLI::UsageError, "line 2: missing wait deadline") do
      Term::VT::CLI::Tape.parse %(run sh\nwait "ready"\n)
    end
  end

  it "rejects idle without an explicit deadline" do
    expect_raises(Term::VT::CLI::UsageError, "line 2: missing idle deadline") do
      Term::VT::CLI::Tape.parse "run sh\nidle 50ms\n"
    end
  end

  it "rejects unquoted strings for string directives" do
    expect_raises(Term::VT::CLI::UsageError, "line 2: expected text must be a double-quoted string") do
      Term::VT::CLI::Tape.parse "run sh\nexpect ready\n"
    end
  end

  it "rejects unknown key names" do
    expect_raises(Term::VT::CLI::UsageError, "line 2: unknown key \"nope\"") do
      Term::VT::CLI::Tape.parse "run sh\npress nope\n"
    end
  end

  it "rejects invalid escapes" do
    expect_raises(Term::VT::CLI::UsageError, "line 2: invalid escape sequence \\q") do
      Term::VT::CLI::Tape.parse %(run sh\nexpect "\\q"\n)
    end
  end

  it "rejects unterminated strings" do
    expect_raises(Term::VT::CLI::UsageError, "line 2: unterminated string") do
      Term::VT::CLI::Tape.parse %(run sh\nexpect "oops\n)
    end
  end
end
