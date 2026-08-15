# Homebrew tap for TiboTattle

This tap distributes the same signed and notarized TiboTattle Mac app published
at [tibotattle.com](https://tibotattle.com/) and in
[GitHub Releases](https://github.com/adamallcock/tibotattle/releases).

## Install

```bash
brew install --cask adamallcock/tap/tibotattle
```

TiboTattle supports Apple silicon Macs running macOS 14 Sonoma or later. The
cask preserves the app's signed Sparkle update channel.

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

`update-tibotattle.yml` checks the latest non-draft TiboTattle GitHub Release
hourly and can also be dispatched manually. It verifies the exact arm64 DMG,
signature, stapled notarization ticket, Homebrew audit, install, and uninstall
before committing a changed version and SHA-256.

The cask stays in this first-party tap until TiboTattle meets Homebrew's current
age and notability requirements for `Homebrew/homebrew-cask`.
