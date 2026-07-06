require "./spec_helper"

describe Term::VT::Session do
  it "spawns children with a tty and the requested window size" do
    Term::VT::Spec.with_pty do
      session = Term::VT::Session.spawn("sh", ["-c", "test -t 0 && tty && stty size"], rows: 33, cols: 77)
      begin
        session.wait_for("33 77", deadline: 5.seconds)
        status = session.wait_exit(deadline: 5.seconds)

        status.success?.should be_true
        session.screen.text.should contain("/dev/")
        session.screen.text.should contain("33 77")
      ensure
        session.close
      end
    end
  end

  it "delivers Ctrl-C through terminal signal semantics" do
    Term::VT::Spec.with_pty do
      session = Term::VT::Session.spawn(
        "sh",
        ["-c", "trap 'printf INT; exit 130' INT; printf ready; read line; printf after"],
        rows: 24,
        cols: 80
      )
      begin
        session.wait_for("ready", deadline: 5.seconds)
        session.send("\x03")
        session.wait_for("INT", deadline: 5.seconds)
        status = session.wait_exit(deadline: 5.seconds)

        status.exit_code?.should eq(130)
        session.screen.text.should_not contain("after")
      ensure
        session.close
      end
    end
  end
end
