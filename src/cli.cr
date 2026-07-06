require "./term-vt"
require "./cli/main"

exit Term::VT::CLI::Main.run(ARGV, STDOUT, STDERR)
