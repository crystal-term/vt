# term-vt

Terminal (VT/ANSI) emulation: escape-sequence parser and cell-grid screen
model, built for testing terminal apps.

`term-vt` can be used as an in-process emulator core. Feed bytes from a
terminal UI and assert on the screen a user would see:

```crystal
require "term-vt"

screen = Term::VT::Screen.new(rows: 5, cols: 80)
screen.feed(File.read("spinner_success.bin").to_slice)

screen.text.should eq("[\u{2714}] Loading done")
screen.contains?("Loading").should be_true
screen.cursor.should eq({row: 1, col: 0})
```

It also includes a POSIX PTY-backed black-box harness for driving real
terminal programs end to end:

```crystal
session = Term::VT::Session.spawn("sh", ["-c", "printf 'ok\\n'"])
session.wait_for("ok", deadline: 5.seconds)
session.screen.text.should eq("ok")
session.wait_exit(deadline: 5.seconds).success?.should be_true
session.close
```

## CLI

Build the binary with `shards build`, then use `bin/term-vt` to drive any
CLI or TUI from the shell without writing Crystal code.

Global flags: `--rows N` (default `24`), `--cols N` (default `80`),
`--timeout SPAN` (default `10s`, accepts `500ms`, `5s`, `1m`), `--styled`,
and `--quiet`. `--quiet` suppresses stdout snapshot emission; failure
diagnostics still go to stderr.

| Verb | Purpose |
| --- | --- |
| `run [flags] [--expect TEXT ...] [--expect-exit N] -- CMD ARGS...` | Run to exit, then assert final screen text and/or exit code. With no expectations, exit 0 only when the child exits 0 before timeout. |
| `snapshot [flags] [--golden FILE] [--update] [--idle SETTLE] -- CMD ARGS...` | Print the final padded screen snapshot, compare/update a golden file, or capture a long-running app after the screen idles. |
| `script FILE.tape` | Execute a line-based tape against one spawned session. |

Exit codes are a public contract:

| Code | Meaning |
| --- | --- |
| `0` | Success; all assertions held. |
| `1` | Assertion, expectation, golden mismatch, nonzero child exit where checked, or timeout. The final screen snapshot is printed to stderr. |
| `2` | Usage error or spawn failure. |

Examples:

```sh
bin/term-vt run --expect "ready" --expect-exit 0 -- sh -c 'printf ready'
bin/term-vt snapshot --rows 10 --cols 40 -- sh -c 'printf hi'
bin/term-vt snapshot --golden spec/fixtures/screen.txt --update -- my-tui --demo
bin/term-vt script examples/shell.tape
```

### Tape DSL

Tapes are line-based. `#` starts a comment outside double-quoted strings.
Strings must be double-quoted and support Crystal-style escapes such as
`\n`, `\t`, `\e`, `\"`, `\\`, `\x21`, and `\u{2713}`. A tape has exactly
one `run`; `rows` and `cols` may appear before it, and every action after
that runs against the same session. `wait` and `idle` always require explicit
deadlines.

```text
rows 24
cols 80
run vim --clean -u NONE
wait "~" 5s
idle 50ms 5s
type "iHello"
press escape
press enter
expect "Hello"
expect-not "Error"
snapshot out.txt
snapshot
resize 40 120
send-exit
expect-exit 0
```

Supported directives:

| Directive | Meaning |
| --- | --- |
| `rows N`, `cols N` | Initial screen size before `run`. |
| `run CMD ARGS...` | Spawn the one child command for the tape. |
| `wait "TEXT" DEADLINE` | Wait until the screen contains text. |
| `idle SETTLE DEADLINE` | Wait until the screen has not changed for `SETTLE`. |
| `type "TEXT"` | Send text bytes to the child. |
| `press KEY` | Send a named key from the supported key table. |
| `expect "TEXT"` / `expect-not "TEXT"` | Assert current screen contents without waiting. |
| `snapshot [FILE]` | Write the current snapshot to `FILE`, or stdout when no file is given. |
| `resize ROWS COLS` | Resize the PTY and screen. |
| `send-exit` | Close the session and assert that the child exits. |
| `expect-exit N` | Assert the child exit code. |

## API

- `Term::VT::Parser` is a stateful VT/ANSI byte parser. It accepts
  `feed(String)` and `feed(Bytes)` and calls a `Term::VT::Performer`.
- `Term::VT::Screen` includes `Performer` and maintains a cell grid, primary
  and alternate buffers, scrollback, cursor state, current style, title,
  bell count, and a bounded `unhandled` debug list.
- `Term::VT::PTY.open(rows, cols)` allocates a POSIX master/slave PTY pair,
  applies the initial winsize, supports `resize`, and closes both ends
  idempotently.
- `Term::VT::Session.spawn(command, args, rows:, cols:, env:)` starts a child
  process attached to a controlling TTY, pumps PTY output through a reader
  fiber into a mutex-guarded `Screen`, and provides `send`, `press`, `type`,
  `wait_for`, `wait_idle`, `wait_exit`, `resize`, and `close`.
- `Term::VT::Keys.sequence(:up)` exposes the harness key-name table used by
  `Session#press`.
- `Term::VT::Width.of(char)` returns terminal cell width `0`, `1`, or `2`.
- `Term::VT::Style`, `Term::VT::Color`, and `Term::VT::Cell` are value
  structs used by the grid and snapshot APIs.

Useful screen methods:

```crystal
screen.feed(bytes_or_string)  # => self
screen.row_text(0)            # visible row, trailing whitespace trimmed
screen.rows_text              # Array(String)
screen.text                   # rows joined with newlines, trailing blank rows trimmed
screen.snapshot               # exact padded grid
screen.styled_snapshot        # run-length style rendering
screen.cell(row, col)         # Term::VT::Cell
screen.find("Done")           # {row: Int32, col: Int32}?
screen.contains?("Done")      # Bool
screen.scrollback_text        # Array(String)
screen.unhandled              # bounded debug list for skipped sequences
```

## Black-box Testing

`Session` is intended for integration tests that need a real terminal device:
raw-mode behavior, `tty?` checks, shell programs, readline-style DSR queries,
or key sequences flowing through a PTY.

```crystal
session = Term::VT::Session.spawn("sh", ["-i"],
  rows: 24,
  cols: 80,
  env: {"PS1" => "$ ", "TERM" => "xterm"})

begin
  session.wait_for("$", deadline: 5.seconds)
  session.type("printf hello")
  session.press(:enter)
  session.wait_for("hello", deadline: 5.seconds)
  session.wait_idle(settle: 50.milliseconds, deadline: 5.seconds)
  session.screen.contains?("hello").should be_true
ensure
  session.close
end
```

Every wait primitive polls with a deadline and raises `Term::VT::TimeoutError`
with the current `screen.snapshot` in the message. `wait_idle` uses the
screen change counter rather than comparing grids.

The PTY/session harness is POSIX-only. It uses the rung-2 controlling-TTY
strategy from plan 023: a small `vt-ctty` shim built into `.term-vt/bin/`
that runs `setsid`, attaches the PTY slave with `TIOCSCTTY`, sets the
foreground process group, then `execvp`s the requested command. Rung 1
(`Process.new` with the slave as stdio and no `setsid`) was rejected because
it passed `tty` and `stty size` but did not deliver Ctrl-C as terminal signal
semantics on macOS.

PTY-dependent specs mark themselves pending when PTY allocation or helper
build support is unavailable.

## Supported Keys

`Session#press` accepts these names:

| Group | Names |
| --- | --- |
| Editing | `enter`, `tab`, `escape`, `backspace` |
| Arrows | `up`, `down`, `left`, `right` |
| Navigation | `home`, `end`, `page_up`, `page_down` |
| Functions | `f1` through `f12` |
| Control | `ctrl_a` through `ctrl_z` |

## Supported Sequences

| Family | Sequences |
| --- | --- |
| UTF-8 | Ground-state UTF-8, including split code points and invalid-byte replacement. |
| C0 | `BEL`, `BS`, `HT`, `LF`/`VT`/`FF`, `CR`, `CAN`, `SUB`, `ESC`. |
| ESC | `DECSC`/`DECRC` (`ESC 7`/`ESC 8`), `IND`, `RI`, `NEL`, `HTS` (`ESC H`), `RIS`, charset designations consumed and ignored. |
| CSI cursor | `CUU`, `CUD`, `CUF`, `CUB`, `CNL`, `CPL`, `CHA`, `VPA`, `CUP`, `HVP`. |
| CSI erase/edit | `ED` `0`/`1`/`2`/`3`, `EL` `0`/`1`/`2`, `ICH`, `DCH`, `ECH`, `IL`, `DL`, `SU`, `SD`. |
| CSI scroll region | `DECSTBM` (`CSI Pt ; Pb r`); defaults and full-screen reset; invalid regions ignored. |
| CSI tab stops | `TBC` (`CSI g` params `0`/`3`), `CHT` (`CSI I`), `CBT` (`CSI Z`); `HT` uses the stop table. |
| CSI modes | ANSI `SM`/`RM` mode `4` (`IRM` insert/replace). |
| CSI save/restore | `CSI s`, `CSI u`. |
| CSI reports | `DSR` cursor position query (`CSI 6 n`) emits CPR through `screen.on_report` when set. |
| SGR | Reset, text flags, flag resets, 8-color, bright-color, indexed color, truecolor, `39`, `49`; semicolon and colon extended-color forms. |
| Private modes | `?25` cursor visibility, `?7` autowrap, `?6` origin mode (`DECOM`), `?47`/`?1047` alternate screen, `?1049` alternate screen with cursor save/restore. |
| OSC | `OSC 0` and `OSC 2` set `screen.title`; other OSC commands are consumed. |
| Strings | DCS/SOS/PM/APC payloads are consumed and discarded until `ST`. |

Unknown or unsupported sequences are consumed silently and appended to
`screen.unhandled` when they are useful for debugging. The list is capped at
100 entries.

## Snapshot Format

`screen.snapshot` is the exact grid contract for golden files: every row is
present, every row is padded to `screen.cols`, and rows are joined by `\n`.
Styling is ignored.

`screen.styled_snapshot` is a run-length style contract. It emits one line per
visible row, trims trailing default blank cells, and writes segments as:

```text
{attrs}text{attrs}more
```

The default style is `{}`. Attribute names are emitted in this order:
`bold dim italic underline blink inverse hidden strike fg=<n|#rrggbb>
bg=<n|#rrggbb>`.

Example:

```text
{bold fg=2}Done{} in {fg=#010203}3s
```

## Unsupported

These are intentionally out of scope and should be added without changing the
public parser/screen split:

- Left/right margins (`DECSLRM`) and rectangle operations.
- Mouse protocols.
- Grapheme clusters; width-0 combining marks are dropped.
- Resize reflow; `resize` truncates/pads and clamps the cursor.
- Windows/ConPTY.
