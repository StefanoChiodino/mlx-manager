# Tasks: 011-uv-env

## T1–T3 — UVLocator

- [x] RED: write `test_locate_whenFirstCandidateExists_returnsIt`
- [x] RED: write `test_locate_whenFirstMissingSecondExists_returnsSecond`
- [x] RED: write `test_locate_whenNoneExist_returnsNil`
- [x] GREEN: implement `UVLocator`

## T4 — CommandRunner protocol + ProcessCommandRunner

- [x] RED: write `test_install_usesUVVenvAndUVPipInstall` (stub runner, uv present)
- [x] GREEN: extract `CommandRunner` protocol; implement `ProcessCommandRunner`
- [x] GREEN: refactor `EnvironmentInstaller` to thin adapter over `EnvironmentBootstrapper`

## T5 — EnvironmentBootstrapper: skips uv install when uv is found

- [x] RED: write `test_install_whenUVFound_skipsInstallStep`
- [x] GREEN: implement locate-then-skip logic

## T6 — EnvironmentBootstrapper: runs uv install when uv is absent

- [x] RED: write `test_install_whenUVMissing_runsInstallStep`
- [x] GREEN: implement install-then-retry logic
