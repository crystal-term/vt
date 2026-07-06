require "../src/term-vt"

session = Term::VT::Session.spawn(
  "sh",
  ["-i"],
  rows: 12,
  cols: 80,
  env: {"PS1" => "$ ", "TERM" => "xterm"}
)

begin
  session.wait_for("$", deadline: 5.seconds)
  session.type("ls")
  session.press(:enter)
  session.wait_for("README.md", deadline: 5.seconds)
  session.wait_idle(settle: 50.milliseconds, deadline: 5.seconds)

  puts session.screen.snapshot
ensure
  session.close
end
