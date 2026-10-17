# Sprint 004 hotfix — Android workflow exit 127

## Diagnosis

The failed run is [39037369508](https://github.com/Indarto324/SurvivalGame/actions/runs/39037369508),
at the Sprint 001–003 regression step. Exit 127 means a command could not be found.
`tests/run.sh` requires ripgrep (`rg`) to reject engine errors and check each
suite's completion summary, but the workflow installed only Vulkan/Xvfb packages.
The Ubuntu 24.04 runner inventory lists coreutils (including `timeout`) but does
not list ripgrep. Godot had already executed in the preceding import step.

Locally, running the original runner with every required command available except
`rg` reproduced the failure exactly: all 59 Sprint 001 checks passed, then both
`rg` calls printed `command not found` and the script exited **127**. The first
call was in an `if` condition, so Bash continued; the second unguarded call ended
the run. This establishes a missing-ripgrep failure path matching the report.
Direct confirmation from the hosted runner's stderr was unavailable: GitHub API
requests returned 403 and detailed web logs required sign-in. Do not confuse the
local reproduction with a downloaded hosted log.

## Changes

- `.github/workflows/android-debug.yml`: explicitly install `ripgrep`, `coreutils`,
  `curl`, `unzip`, `python3`, `xauth` and existing Vulkan/Xvfb dependencies. Check
  command paths and versions before tests. Use Bash with pipefail; stream import,
  regression and build output through `tee`. Display retained logs on failure and
  upload artifacts even on failure. A failing runner cannot be hidden by tee's
  successful exit. Push triggers and branch guards still target only `kawanan-island`.
- `tests/run.sh`: diagnose missing tools, including the selected Godot executable,
  before loading scenes. All gameplay test scenes, assertions and timeout limits
  are preserved.
- `docs/SPRINT_004_HOTFIX.md`: this diagnosis and validation record.

## Validation

- Original failure reproduced without `rg`: exit 127 after Sprint 001 passed.
- Updated runner without `rg` or `timeout`: explicit missing-command diagnostic and
  exit 127 before gameplay starts.
- Actual workflow regression command exercised with a controlled exit-43 script:
  stderr reached both console and retained log, and pipeline status stayed 43.
- Godot 4.4 Sprint 001: **59 checks, zero failures**.
- Godot 4.4 Sprint 002: **46 checks, zero failures**.
- Godot 4.4 Sprint 003: **60 checks, zero failures**.
- Shell syntax, workflow YAML and target-branch guard checked locally.

Local build evidence is under `/workspace/artifacts/kawanan-hotfix004/`, separate
from the original Sprint 004 artifacts. The pushed hotfix triggers a fresh Android
Actions build. Consult that run's status and Artifacts section for hosted results;
local regression/build success alone does not establish hosted success. Hosted
artifact name is `kawanan-island-debug-<full commit SHA>`, retained for seven days.
No changes to main, gameplay, signing credentials or test assertions are required.
No physical-device testing or Google Play publication is performed by this fix.
