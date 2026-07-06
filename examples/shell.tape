# Run with: bin/term-vt script examples/shell.tape
rows 5 cols 40
run sh -c "read line; printf got:$line"
type "hello"
press enter
wait "got:hello" 5s
expect "got:hello"
expect-not "Error"
send-exit
expect-exit 0
