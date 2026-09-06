---
title: Dual-architecture TiboTattle cask preparation
date: 2026-09-06
type: plan
status: prepared-local-validation-passed-native-qualification-pending
---

## Scope and authority

Prepare one ARM/Intel cask in an isolated clone, branch
`codex/tibotattle-intel-cask`, based on public tap main
`ea8a6dad8a960bc71a11558aa17c277bc43a5844`. No push, pull request,
workflow dispatch, cask publication, app installation or production-service
change is authorized by this preparation task. Existing installed tap and
released app artifacts remain unchanged.

## Implementation

- One cask maps Apple silicon to `arm64` and Intel to `x64` download names,
  with independent SHA-256 values and the existing macOS 14 floor.
- The updater checks all inputs and supported source layouts, detects same-
  version architecture/hash drift, rejects downgrades, and updates atomically.
- Release automation validates both immutable release assets and uses native
  ARM/Intel verification lanes before a candidate is considered qualified.
- Uninstall/zap scope, bundle identity and in-app update authority are unchanged.

## Published artifact evidence

Live GitHub metadata for `v0.1.18` is immutable, non-draft and non-prerelease.
Both asset names, sizes and digests match the already-qualified release:

| Architecture | Bytes | SHA-256 |
|---|---:|---|
| ARM | 49,908,061 | `2ea8eca02df7cc5210b6b6ce3d6e44016bffd9d081544a4efc6fa1afeeb0f1ae` |
| Intel | 52,128,441 | `70630ba90e92a1cd8cb904e66e1aebe85b04e9d23a50bef7e4e41aca84c4d2f6` |

Sources: [Homebrew architecture support](https://docs.brew.sh/Cask-Cookbook#handling-different-system-configurations),
[published release](https://github.com/adamallcock/tibotattle/releases/tag/v0.1.18).

## Local validation and remaining gates

The combined local regression suite passes 22 tests and 437 assertions without
skips; Ruby/Bash syntax and whitespace checks pass. Regression coverage includes
both architecture hashes, legacy same-version upgrades, refusal before writes,
native verification failures, scoped CI cleanup and publication job dependencies.
The coordinating review inspected every changed file and independently repeated
the 22-test / 437-assertion suite successfully. The prepared local commit is not
publication or native installation qualification.
The installed Homebrew rejects
candidate files outside a registered tap; do not bypass that path guard.
Homebrew also requires explicit trust for a non-official cask. No local tap or
trust grant was created. Exact temporary-cask trust/untrust is prepared only in
the ephemeral hosted jobs; actual Homebrew loading/audit/install is unverified.

An initial synthetic native-verifier test run failed when a Ruby mock of xcrun
recursively invoked the system Ruby launcher. Only that verified owned process
tree was stopped; its fixture-path follow-up found no residual processes. That
run is failed evidence, not qualification. Shell-only mocks replaced it and
the full suite above passed. No TiboTattle installer or application was run.

The safety review initially rejected retention of scheduled commit/push behavior
under preparation-only authority. The owner subsequently explicitly approved
retaining that existing behavior in the prepared workflow after both installers
pass verification, without pushing, running or publishing it in this turn.
Only the final gated job may have repository-write authority. Hosted native
install/uninstall checks and actual publication are not local test passes.
