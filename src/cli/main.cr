require "./options"
require "./runner"

module Term::VT::CLI
  module Main
    def self.run(argv : Array(String), stdout : IO = STDOUT, stderr : IO = STDERR) : Int32
      global, command = Options.parse(argv)
      Runner.new(global, stdout, stderr).execute(command)
      0
    rescue ex : Failure
      stderr.puts ex.message
      if snapshot = ex.snapshot
        stderr.puts "Screen snapshot:"
        stderr.print snapshot
        stderr.puts unless snapshot.ends_with?('\n')
      end
      1
    rescue ex : UsageError
      stderr.puts ex.message
      2
    end
  end
end
