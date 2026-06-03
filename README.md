# Ghostty Tab Bar Preview

This repository is a fork of [ghostty-org/ghostty](https://github.com/ghostty-org/ghostty).

This fork only documents the changes made in this repository. For Ghostty's
upstream documentation, architecture, and general project information, see the
original project.

## Changes in This Fork

- Adds a macOS-only configuration option:

  ```text
  macos-tab-bar-position = top
  macos-tab-bar-position = left
  macos-tab-bar-position = right
  ```

- Adds a vertical tab bar for `left` and `right` tab placement on macOS.
- Supports reloading the tab bar position at runtime with
  `Ghostty -> Reload Configuration`.
- Adds vertical tab interactions:
  - select tabs
  - close tabs
  - rename tabs
  - drag to reorder tabs
  - create a new tab
  - scroll when there are many tabs
  - close other tabs, close tabs to the right, and close all tabs
- Adds a GitHub Actions workflow that builds and publishes a macOS Apple
  Silicon DMG for preview releases.

## macOS Configuration

Ghostty's preferred macOS config path is:

```text
~/Library/Application Support/com.mitchellh.ghostty/config.ghostty
```

Example:

```text
macos-tab-bar-position = left
```

After changing the value, use `Ghostty -> Reload Configuration` to apply it
without restarting the app.

## Release Notes

Preview DMG builds in this fork are built with Ghostty's local macOS release
configuration. They are not Developer ID notarized unless release signing and
notarization secrets are configured separately.
