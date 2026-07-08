# In-process emulator core — portable pure Crystal (including Windows).
require "./vt/version"
require "./vt/style"
require "./vt/cell"
require "./vt/width"
require "./vt/keys"
require "./vt/mouse"
require "./vt/performer"
require "./vt/parser"
require "./vt/tab_stops"
require "./vt/screen"
require "./vt/snapshot"
require "./vt/captured_tty"

# POSIX PTY / Session harness — openpty, signals, vt-ctty shim.
# Not available on Windows; use ConPTY for a real Session port (plan 033).
{% if flag?(:unix) %}
  require "./vt/libc_pty"
  require "./vt/pty"
  require "./vt/session"
{% end %}
