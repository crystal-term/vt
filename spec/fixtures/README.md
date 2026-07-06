# Fixtures

These `.bin` files are captured byte streams from sibling crystal-term shards.
They seed dogfooding for the in-process emulator without introducing a PTY
harness.

Regenerate from the repository root after installing sibling shard
dependencies:

```sh
cd shards/spinner && shards install
crystal eval 'require "./src/term-spinner"
class CaptureIO < IO
  getter output = ""
  def read(slice : Bytes) : Int32; 0; end
  def write(slice : Bytes) : Nil; @output += String.new(slice); end
  def tty?; true; end
  def flush; end
end
io = CaptureIO.new
spinner = Term::Spinner.new("[:spinner] Loading", output: io, hide_cursor: true)
spinner.spin
spinner.success("done")
File.write("../../shards/vt/spec/fixtures/spinner_success.bin", io.output)'

cd ../progress && shards install
crystal eval 'require "./src/term-progress"
class CaptureIO < IO
  getter output = ""
  def read(slice : Bytes) : Int32; 0; end
  def write(slice : Bytes) : Nil; @output += String.new(slice); end
  def tty?; true; end
  def flush; end
end
io = CaptureIO.new
bar = Term::Progress::Bar.new(total: 10_i64, format: "Build [:bar] :percent", width: 10, output: io)
bar.update(5_i64)
bar.finish("done")
File.write("../../shards/vt/spec/fixtures/progress_finish.bin", io.output)'
```
