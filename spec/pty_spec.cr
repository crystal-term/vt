require "./spec_helper"

describe Term::VT::PTY do
  it "opens a master and slave pair with the requested winsize" do
    Term::VT::Spec.with_pty do
      pty = Term::VT::PTY.open(rows: 17, cols: 43)
      begin
        pty.master.closed?.should be_false
        pty.slave.closed?.should be_false
        pty.winsize.should eq({rows: 17, cols: 43})
      ensure
        pty.close
      end
    end
  end

  it "resizes the terminal window" do
    Term::VT::Spec.with_pty do
      pty = Term::VT::PTY.open(rows: 10, cols: 20)
      begin
        pty.resize(rows: 31, cols: 99)
        pty.rows.should eq(31)
        pty.cols.should eq(99)
        pty.winsize.should eq({rows: 31, cols: 99})
      ensure
        pty.close
      end
    end
  end

  it "closes both ends idempotently" do
    Term::VT::Spec.with_pty do
      pty = Term::VT::PTY.open
      pty.close
      pty.close

      pty.closed?.should be_true
      pty.master.closed?.should be_true
      pty.slave.closed?.should be_true
    end
  end
end
