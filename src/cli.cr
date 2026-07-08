{% unless flag?(:unix) %}
  {% raise "term-vt CLI and Session harness are POSIX-only. On Windows, require \"term-vt\" for the in-process emulator core (Parser/Screen). See plan 033 ConPTY findings." %}
{% end %}

require "./term-vt"
require "./cli/main"

exit Term::VT::CLI::Main.run(ARGV, STDOUT, STDERR)
