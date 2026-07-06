require "./spec_helper"

if ENV["TERM_VT_DSR_CHILD"]? == "1"
  STDIN.raw!
  STDOUT.write("\e[2;5H\e[6n".to_slice)
  STDOUT.flush

  reply = Bytes.new(6)
  STDIN.read_timeout = 5.seconds
  STDIN.read_fully(reply)
  STDOUT << "reply:" << reply.map(&.to_s).join(',')
  STDOUT.flush
  LibC._exit(0)
end

describe "DSR cursor position report" do
  it "lets Screen report CPR bytes for CSI 6 n" do
    reported = Bytes.empty
    screen = Term::VT::Screen.new(rows: 5, cols: 10)
    screen.on_report = ->(bytes : Bytes) { reported = bytes.dup }

    screen.feed("\e[3;4H\e[6n")

    String.new(reported).should eq("\e[3;4R")
  end

  it "wires Session DSR reports back to the child process" do
    Term::VT::Spec.with_pty do
      session = Term::VT::Session.spawn(
        Process.executable_path.not_nil!,
        [] of String,
        rows: 8,
        cols: 80,
        env: {"TERM_VT_DSR_CHILD" => "1"}
      )
      begin
        session.wait_for("reply:27,91,50,59,53,82", deadline: 5.seconds)
        session.wait_exit(deadline: 5.seconds).success?.should be_true
      ensure
        session.close
      end
    end
  end
end
