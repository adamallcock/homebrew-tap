---
title: Dual-architecture TiboTattle cask preparation
date: 2026-09-06
type: plan
status: native-qualified-publication-authorized
---

## Scope and authority

Update on 2026-09-07: the owner authorized native CI, cask publication and the
website instructions, then added the product README and setup documentation.
The preparation-only boundary below records the original 2026-09-06 scope;
it is superseded for this explicit publication task. The public release DMGs
remain immutable and no local application replacement is needed.

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

## Original preparation evidence (2026-09-06)

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

## Publication sequence (2026-09-07)

1. Revalidate the current immutable release pair and local tests, then open the
   tap pull request and require both native cask installation lanes to pass.
2. Merge the qualified tap source without rewriting history. Verify published
   architecture selection and run the guarded updater's two-asset verification.
3. Add the same Homebrew command to the Intel website tab and update installation
   documentation. Separate end-user installation from developer build limits.
4. Validate the website at desktop/mobile widths, deploy through its maintained
   wrapper from current production source, and check both live download tabs.
5. Record exact CI/source/publication evidence. No graph, pricing, consent,
   database, desktop release or update-feed changes belong to this task.

## Native qualification (2026-09-07)

Implementation commit `785b68c7d3fcc3d9197822a58545673d58bf7117` passed both
native Mac lanes in [cask CI](https://github.com/adamallcock/homebrew-tap/actions/runs/34141158444):
Homebrew style, online audit, architecture selection, installation, native app
trust inspection and uninstall. The local 22-test / 437-assertion suite was
also repeated without failures or skips.

The [forced updater verification](https://github.com/adamallcock/homebrew-tap/actions/runs/34141557913)
then passed on both native architectures, independently checking the actual
immutable DMG size/hash, disk-image and app signatures, Gatekeeper, stapled
notarization tickets, bundled architectures and full cask install/uninstall.
Its commit job correctly skipped on the non-main branch. These automated
distribution checks do not claim interactive app execution or replace the
desktop release's separately recorded manual-qualification boundary.

Publication is authorized through [PR #2](https://github.com/adamallcock/homebrew-tap/pull/2).
That pull request's merged state and the tap's main-branch cask are the live
publication evidence; this document alone is not proof of publication.
