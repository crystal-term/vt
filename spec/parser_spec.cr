require "./spec_helper"

private class RecordingPerformer
  include Term::VT::Performer

  getter events = [] of String

  def print(char : Char)
    @events << "print:#{char}"
  end

  def execute(byte : UInt8)
    @events << "execute:#{byte}"
  end

  def esc_dispatch(intermediates : String, final : Char)
    @events << "esc:#{intermediates}:#{final}"
  end

  def csi_dispatch(params : Array(Term::VT::CSIParam), intermediates : String, final : Char)
    encoded = params.map { |param| "#{param.value}[#{param.subparams.join(',')}]" }.join(";")
    @events << "csi:#{intermediates}:#{encoded}:#{final}"
  end

  def osc_dispatch(data : String)
    @events << "osc:#{data}"
  end
end

private def parse_events(input)
  performer = RecordingPerformer.new
  parser = Term::VT::Parser.new(performer)
  parser.feed(input)
  performer.events
end

describe Term::VT::Parser do
  it "prints UTF-8 text and executes C0 controls" do
    parse_events("a\n\u{3042}").should eq([
      "print:a",
      "execute:10",
      "print:\u{3042}",
    ])
  end

  it "keeps escape and CSI state across feed calls" do
    split = RecordingPerformer.new
    parser = Term::VT::Parser.new(split)
    parser.feed("\e[")
    parser.feed("2J")

    split.events.should eq(parse_events("\e[2J"))
    split.events.should eq(["csi::2[]:J"])
  end

  it "keeps UTF-8 decoder state across feed calls" do
    performer = RecordingPerformer.new
    parser = Term::VT::Parser.new(performer)

    bytes = Bytes[0xf0, 0x9f, 0x98, 0x80]
    parser.feed(bytes[0, 2])
    parser.feed(bytes[2, 2])

    performer.events.should eq(["print:\u{1f600}"])
  end

  it "emits replacement characters for invalid UTF-8 and resynchronizes" do
    performer = RecordingPerformer.new
    parser = Term::VT::Parser.new(performer)

    parser.feed(Bytes[0xe2, 0x28, 0x41])

    performer.events.should eq([
      "print:\u{fffd}",
      "print:(",
      "print:A",
    ])
  end

  it "dispatches ESC sequences with intermediates" do
    parse_events("\e(0").should eq(["esc:(:0"])
  end

  it "parses CSI missing params, clamps large params, and preserves colon subparams" do
    parse_events("\e[;99999999;38:2::1:2:3m").should eq([
      "csi::0[];65535[];38[2,0,1,2,3]:m",
    ])
  end

  it "limits CSI params to the first sixteen" do
    events = parse_events("\e[1;2;3;4;5;6;7;8;9;10;11;12;13;14;15;16;17m")
    events.first.should eq("csi::1[];2[];3[];4[];5[];6[];7[];8[];9[];10[];11[];12[];13[];14[];15[];16[]:m")
  end

  it "dispatches private CSI markers as intermediates" do
    parse_events("\e[?25l").should eq(["csi:?:25[]:l"])
  end

  it "dispatches OSC strings terminated by BEL or ST" do
    parse_events("\e]2;title\a\e]0;other\e\\").should eq([
      "osc:2;title",
      "osc:0;other",
    ])
  end

  it "caps OSC payloads at four KiB" do
    events = parse_events("\e]2;#{"x" * 5000}\a")
    events.first.size.should eq("osc:".size + 4096)
  end

  it "consumes DCS, SOS, PM, and APC strings until ST" do
    parse_events("a\ePignored\e\\b\eXignored\e\\c\e^ignored\e\\d\e_ignored\e\\e").should eq([
      "print:a",
      "print:b",
      "print:c",
      "print:d",
      "print:e",
    ])
  end

  it "aborts sequences with CAN or SUB and lets ESC restart one" do
    parse_events("\e[2\u{18}J\e[1\e[2K").should eq([
      "print:J",
      "csi::2[]:K",
    ])
  end
end
