require "./spec_helper"

module Term::VT::CLI::Spec
  @@binary : String?

  def self.binary : String
    @@binary ||= build_binary
  end

  def self.run(args : Array(String)) : NamedTuple(status: Process::Status, stdout: String, stderr: String)
    stdout = IO::Memory.new
    stderr = IO::Memory.new
    status = Process.run(binary, args, output: stdout, error: stderr)
    {status: status, stdout: stdout.to_s, stderr: stderr.to_s}
  end

  private def self.build_binary : String
    dir = File.tempname("term-vt-cli-spec")
    Dir.mkdir_p(dir)
    binary = File.join(dir, "term-vt")
    stdout = IO::Memory.new
    stderr = IO::Memory.new
    status = Process.run(
      "crystal",
      ["build", "src/cli.cr", "-o", binary, "--no-color"],
      output: stdout,
      error: stderr,
    )

    unless status.success?
      raise "failed to build CLI binary\nSTDOUT:\n#{stdout}\nSTDERR:\n#{stderr}"
    end

    binary
  end
end

describe "term-vt CLI" do
  it "runs a command and checks final screen and exit expectations" do
    Term::VT::Spec.with_pty do
      result = Term::VT::CLI::Spec.run([
        "run",
        "--rows", "3",
        "--cols", "20",
        "--expect", "hi",
        "--expect-exit", "0",
        "--",
        "sh", "-c", "printf hi",
      ])

      result[:status].exit_code?.should eq(0)
      result[:stdout].should eq("")
      result[:stderr].should eq("")
    end
  end

  it "exits 1 and prints a final snapshot when a run expectation fails" do
    Term::VT::Spec.with_pty do
      result = Term::VT::CLI::Spec.run([
        "run",
        "--rows", "3",
        "--cols", "20",
        "--expect", "missing",
        "--",
        "sh", "-c", "printf hi",
      ])

      result[:status].exit_code?.should eq(1)
      result[:stdout].should eq("")
      result[:stderr].should contain("expected final screen to contain \"missing\"")
      result[:stderr].should contain("Screen snapshot:")
      result[:stderr].should contain("hi")
    end
  end

  it "updates, matches, and diffs golden snapshots" do
    Term::VT::Spec.with_pty do
      dir = File.tempname("term-vt-golden-spec")
      Dir.mkdir_p(dir)
      golden = File.join(dir, "screen.txt")

      update = Term::VT::CLI::Spec.run([
        "snapshot",
        "--rows", "1",
        "--cols", "5",
        "--golden", golden,
        "--update",
        "--",
        "sh", "-c", "printf hi",
      ])
      update[:status].exit_code?.should eq(0)
      File.read(golden).should eq("hi   ")

      match = Term::VT::CLI::Spec.run([
        "snapshot",
        "--rows", "1",
        "--cols", "5",
        "--golden", golden,
        "--",
        "sh", "-c", "printf hi",
      ])
      match[:status].exit_code?.should eq(0)
      match[:stdout].should eq("")
      match[:stderr].should eq("")

      mismatch = Term::VT::CLI::Spec.run([
        "snapshot",
        "--rows", "1",
        "--cols", "5",
        "--golden", golden,
        "--",
        "sh", "-c", "printf ho",
      ])
      mismatch[:status].exit_code?.should eq(1)
      mismatch[:stderr].should contain("--- #{golden}")
      mismatch[:stderr].should contain("-hi")
      mismatch[:stderr].should contain("+ho")
      mismatch[:stderr].should contain("Screen snapshot:")
    end
  end

  it "runs a tape against sh through the compiled script verb" do
    Term::VT::Spec.with_pty do
      tape = File.tempname("term-vt-cli-spec", ".tape")
      File.write(tape, <<-TAPE)
        rows 5 cols 40
        run sh -c "read line; printf got:$line"
        type "hello"
        press enter
        wait "got:hello" 5s
        expect "got:hello"
        expect-not "Error"
        send-exit
        expect-exit 0
        TAPE

      result = Term::VT::CLI::Spec.run(["script", tape])

      result[:status].exit_code?.should eq(0)
      result[:stdout].should eq("")
      result[:stderr].should eq("")
    end
  end
end
