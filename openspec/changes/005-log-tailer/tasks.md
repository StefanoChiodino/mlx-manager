# Tasks: 005-log-tailer

- [x] 1. Test: start seeks to end of file
- [x] 2. Test: new progress line emitted as event
- [x] 3. Test: non-matching lines are ignored
- [x] 4. Test: multiple lines in one read emit events in order
- [x] 5. Test: partial line (no trailing newline) is buffered
- [x] 6. Test: file truncation resets offset to 0
- [x] 7. Test: stop calls stopWatching
- [x] 8. Test: file not found at start is a no-op
