# Crystal's Windows target flag is :win32; some older docs also mention :windows.
{% if flag?(:win32) || flag?(:windows) %}
  exit
{% else %}
  shard_root = File.expand_path("..", __DIR__)
  source = File.join(shard_root, "src", "vt", "ctty_exec.c")
  helper = File.join(shard_root, ".term-vt", "bin", "vt-ctty")

  Dir.mkdir_p(File.dirname(helper))

  output = IO::Memory.new
  error = IO::Memory.new
  status = Process.run("cc", [source, "-o", helper], output: output, error: error)

  unless status.success?
    STDERR.puts(error.to_s.empty? ? output.to_s : error.to_s)
    exit status.exit_code? || 1
  end
{% end %}
