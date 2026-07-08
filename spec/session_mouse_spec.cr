require "./spec_helper"

describe "Session mouse / paste / focus senders" do
  it "sends an SGR click when the child enables mouse tracking" do
    Term::VT::Spec.with_pty do
      # Child enables normal tracking + SGR in raw mode, then dumps 9 stdin
      # bytes (one SGR press) via od.
      session = Term::VT::Session.spawn(
        "sh",
        ["-c", %(stty raw -echo; printf '\\033[?1000h\\033[?1006hREADY\\r\\n'; dd bs=1 count=9 2>/dev/null | od -An -tx1; printf '\\r\\nDONE\\r\\n')],
        rows: 12,
        cols: 80,
      )
      begin
        session.wait_for("READY", deadline: 5.seconds)
        session.screen.mouse_tracking.should eq(Term::VT::MouseTracking::Normal)
        session.screen.mouse_encoding.should eq(Term::VT::MouseEncoding::Sgr)

        session.mouse_down(2, 4, :left)
        session.wait_for("DONE", deadline: 5.seconds)
        session.wait_exit(deadline: 5.seconds)

        text = session.screen.text.gsub(/\s+/, " ").strip
        # Bytes of ESC [ < 0 ; 5 ; 3 M
        text.should contain("1b 5b 3c 30 3b 35 3b 33 4d")
      ensure
        session.close
      end
    end
  end

  it "sends bracketed paste markers when ?2004 is enabled" do
    Term::VT::Spec.with_pty do
      # \e[200~hi\e[201~ = 14 bytes
      session = Term::VT::Session.spawn(
        "sh",
        ["-c", %(stty raw -echo; printf '\\033[?2004hREADY\\r\\n'; dd bs=1 count=14 2>/dev/null | od -An -c; printf '\\r\\nDONE\\r\\n')],
        rows: 12,
        cols: 100,
      )
      begin
        session.wait_for("READY", deadline: 5.seconds)
        session.screen.bracketed_paste?.should be_true

        session.paste("hi")
        session.wait_for("DONE", deadline: 5.seconds)
        session.wait_exit(deadline: 5.seconds)

        # od -c prints each char spaced: "2   0   0" not "200"
        text = session.screen.text.gsub(/\s+/, " ")
        text.should contain("2 0 0")
        text.should contain("2 0 1")
        text.should contain(" h ")
        text.should contain(" i ")
      ensure
        session.close
      end
    end
  end

  it "sends raw paste when bracketed paste is off" do
    Term::VT::Spec.with_pty do
      session = Term::VT::Session.spawn(
        "sh",
        ["-c", "stty raw -echo; dd bs=1 count=2 2>/dev/null | od -An -c; printf '\\r\\nDONE\\r\\n'"],
        rows: 8,
        cols: 40,
      )
      begin
        session.paste("hi")
        session.wait_for("DONE", deadline: 5.seconds)
        session.wait_exit(deadline: 5.seconds)

        text = session.screen.text
        text.should match(/h/)
        text.should match(/i/)
        text.should_not contain("200")
      ensure
        session.close
      end
    end
  end

  it "raises when clicking without mouse tracking enabled" do
    Term::VT::Spec.with_pty do
      session = Term::VT::Session.spawn("sh", ["-c", "read line"], rows: 5, cols: 20)
      begin
        expect_raises(ArgumentError, /mouse tracking is not enabled/) do
          session.click(0, 0)
        end
      ensure
        session.close
      end
    end
  end

  it "raises when focus is sent without focus reporting enabled" do
    Term::VT::Spec.with_pty do
      session = Term::VT::Session.spawn("sh", ["-c", "read line"], rows: 5, cols: 20)
      begin
        expect_raises(ArgumentError, /focus reporting is not enabled/) do
          session.focus(true)
        end
      ensure
        session.close
      end
    end
  end

  it "sends focus sequences when reporting is enabled" do
    Term::VT::Spec.with_pty do
      session = Term::VT::Session.spawn(
        "sh",
        ["-c", %(stty raw -echo; printf '\\033[?1004hREADY\\r\\n'; dd bs=1 count=3 2>/dev/null | od -An -c; printf '\\r\\nDONE\\r\\n')],
        rows: 8,
        cols: 40,
      )
      begin
        session.wait_for("READY", deadline: 5.seconds)
        session.screen.focus_reporting?.should be_true

        session.focus(true)
        session.wait_for("DONE", deadline: 5.seconds)
        session.wait_exit(deadline: 5.seconds)

        session.screen.text.should contain("I")
      ensure
        session.close
      end
    end
  end
end
