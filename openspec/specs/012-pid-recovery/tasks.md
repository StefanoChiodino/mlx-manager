# Tasks: PID File Recovery

**Change ID:** 012-pid-recovery

## PIDFile

- [x] T1: `PIDFile.write(pid:)` writes PID as decimal string to file, creating parent dirs
- [x] T2: `PIDFile.read()` returns PID from file contents
- [x] T3: `PIDFile.read()` returns nil when file does not exist
- [x] T4: `PIDFile.read()` returns nil when file contains non-numeric content
- [x] T5: `PIDFile.delete()` removes the file
- [x] T6: `PIDFile.delete()` is a no-op when file does not exist
- [x] T7: `PIDFile.isProcessAlive(pid:)` returns true for a living process
- [x] T8: `PIDFile.isProcessAlive(pid:)` returns false for a dead PID

## PIDRecovery

- [x] T9: `recover()` returns `.noFile` when PID file does not exist
- [x] T10: `recover()` returns `.staleFile` when PID file exists but process is dead, and deletes file
- [x] T11: `recover()` returns `.adopted(pid)` when PID file exists and process is alive

## ServerManager — PID file integration

- [x] T12: `start()` writes PID to PID file after successful launch
- [x] T13: `stop()` deletes PID file
- [x] T14: process exit callback deletes PID file

## ServerManager — adopt mode

- [x] T15: `adoptProcess(pid:)` sets `isRunning` to true and `pid` to adopted PID
- [x] T16: `stop()` on adopted process sends SIGTERM and clears state
- [x] T17: `start()` while adopted throws `alreadyRunning`
- [x] T18: `adoptProcess(pid:)` when already running throws `alreadyRunning`

## AppDelegate integration

- [x] T19: Wire PID recovery into `applicationDidFinishLaunching` (manual verification)

(End of file - total 37 lines)
