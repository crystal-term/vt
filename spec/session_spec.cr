require "./spec_helper"

describe Term::VT::Session do
  it "spawns a child, reads output, and waits for exit" do
    Term::VT::Spec.with_pty do
      session = Term::VT::Session.spawn("sh", ["-c", "printf ok"], rows: 5, cols: 20)
      begin
        session.wait_for("ok", deadline: 5.seconds)
        status = session.wait_exit(deadline: 5.seconds)

        status.success?.should be_true
        session.screen.text.should eq("ok")
      ensure
        session.close
      end
    end
  end

  it "sends text, typed characters, and named keys" do
    Term::VT::Spec.with_pty do
      session = Term::VT::Session.spawn("sh", ["-c", "read line; printf 'got:%s' \"$line\""], rows: 5, cols: 40)
      begin
        session.send("he")
        session.type("llo")
        session.press(:enter)

        session.wait_for("got:hello", deadline: 5.seconds)
        session.wait_exit(deadline: 5.seconds).success?.should be_true
      ensure
        session.close
      end
    end
  end

  it "updates the screen with ANSI output from the child" do
    Term::VT::Spec.with_pty do
      session = Term::VT::Session.spawn("sh", ["-c", "printf '\\033[31mred\\033[0m'"], rows: 5, cols: 20)
      begin
        session.wait_for("red", deadline: 5.seconds)
        session.wait_for(deadline: 5.seconds) do |screen|
          screen.cell(0, 0).style.fg == Term::VT::Color.indexed(1)
        end

        session.screen.text.should eq("red")
      ensure
        session.close
      end
    end
  end

  it "waits until output has settled" do
    Term::VT::Spec.with_pty do
      session = Term::VT::Session.spawn("sh", ["-c", "printf done; read line"], rows: 5, cols: 20)
      begin
        session.wait_for("done", deadline: 5.seconds)
        session.wait_idle(settle: 50.milliseconds, deadline: 5.seconds)

        session.screen.text.should eq("done")
      ensure
        session.close
      end
    end
  end

  it "resizes the PTY and screen" do
    Term::VT::Spec.with_pty do
      session = Term::VT::Session.spawn("sh", ["-c", "stty size; read line; stty size"], rows: 12, cols: 34)
      begin
        session.wait_for("12 34", deadline: 5.seconds)
        session.resize(rows: 18, cols: 56)
        session.press(:enter)
        session.wait_for("18 56", deadline: 5.seconds)

        session.screen.rows.should eq(18)
        session.screen.cols.should eq(56)
      ensure
        session.close
      end
    end
  end

  it "closes idempotently" do
    Term::VT::Spec.with_pty do
      session = Term::VT::Session.spawn("sh", ["-c", "read line"], rows: 5, cols: 20)
      session.close
      session.close

      session.pty.closed?.should be_true
    end
  end
end
