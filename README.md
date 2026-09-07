# Homebrew tap for TiboTattle

This tap distributes the same signed and notarized TiboTattle Mac app published
at [tibotattle.com](https://tibotattle.com/) and in
[GitHub Releases](https://github.com/adamallcock/tibotattle/releases).

## Install

```bash
brew install --cask adamallcock/tap/tibotattle
```

The cask supports Apple silicon and Intel Macs running macOS 14 Sonoma
or later. Homebrew selects the matching native DMG and its separate checksum;
both architectures use the same command above. The cask preserves each app's
signed Sparkle update channel and does not require a Universal 2 installer.

## Uninstall

Remove the app while preserving its local state:

```bash
brew uninstall --cask tibotattle
```

The optional zap removes only TiboTattle's Application Support data, caches,
WebKit storage, and preferences:

```bash
brew uninstall --cask --zap tibotattle
```

Zap never touches `~/.codex` and deliberately preserves TiboTattle's Keychain
identities and device credentials. Use the app's two-confirmation **Identity &
Device Reset…** diagnostic flow if those credentials must be reset.

## Release updates

The `update-tibotattle.yml` workflow checks the latest immutable, non-draft,
non-prerelease TiboTattle GitHub Release. It requires both exact native DMGs,
their declared sizes and SHA-256 digests, and verifies each architecture on a
matching macOS runner. Signature, notarization, bundle identity/version, macOS
floor, executable architecture, Homebrew audit, install and uninstall checks
must all pass before automatic publication.

The inexpensive current-state check compares the version, architecture layout
and both checksums. It therefore detects missing Intel support or stale hashes
even when the version is unchanged. A manual `force_verify` option can repeat
verification of a fully current release.

Automatic commit-and-push is gated on success for both native verification
lanes. The workflow checks that the source branch has not moved before a normal,
non-forced push. Both architectures are maintained together; a missing or failed
installer prevents publication.

The updater accepts `VERSION ARM_SHA256 INTEL_SHA256`; `--check` before those
arguments returns 0 for an exact match, 1 when an update is needed, and 2 for
invalid input. Both hashes and the source layout are validated before one atomic
replacement. Version downgrades, malformed layouts and symlink targets are
refused. Uninstall and zap behavior are unchanged.

## Local validation

```bash
ruby -Itest -e 'Dir["test/*_test.rb"].sort.each { |file| require File.expand_path(file) }'
ruby -c Casks/tibotattle.rb
```

The tests use synthetic release metadata and temporary cask files. They do not
install the app, contact production services or publish anything. Native
installation qualification is kept in the separate hosted CI matrix.

The cask stays in this first-party tap until TiboTattle meets Homebrew's current
age and notability requirements for `Homebrew/homebrew-cask`.
