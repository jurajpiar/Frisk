# Frisk

A tiny sandboxed macOS tool for peeking inside archives without extracting them.

Supported formats: `.zip`, `.tar`, `.tar.gz`/`.tgz`, `.tar.bz2`/`.tbz`, `.tar.xz`/`.txz`,
`.gz`, `.bz2`, `.xz`, and `.7z`.

- **Browse** an archive's entries in a window (name / size / modified).
- **Drag** any entry out to Finder to extract *just that entry* at the drop point — nothing
  is extracted until the drop lands, and cancelled drags write nothing.
- **Preview** entries with the spacebar: the system Quick Look panel for most types, and a
  built-in renderer for **Markdown** (rendered via Apple's swift-markdown) including
  **mermaid** diagrams (offline).
- A **Quick Look preview extension**: press space on a supported archive in Finder to see an
  HTML listing of its contents (no extraction).

## Building

The Xcode project is generated from `project.yml` with [XcodeGen](https://github.com/yonaskolb/XcodeGen):

```sh
brew install xcodegen        # once
cp Config/Signing.xcconfig.example Config/Signing.xcconfig
# edit Config/Signing.xcconfig and set DEVELOPMENT_TEAM to your Apple Development Team ID
xcodegen generate
open Frisk.xcodeproj        # or: xcodebuild -scheme Frisk build
```

A free personal Apple ID team is sufficient (no paid Developer Program membership).

## Requirements

- macOS 14.0+
- Xcode 16+ (developed with Xcode 26)

## Dependencies

- [ZIPFoundation](https://github.com/weichsel/ZIPFoundation) — pure-Swift zip reading (MIT).
- [SWCompression](https://github.com/tsolomko/SWCompression) — pure-Swift tar/gzip/bzip2/xz/7z reading (MIT).
- [swift-markdown](https://github.com/swiftlang/swift-markdown) — Markdown parsing (Apache 2.0).
- [mermaid](https://github.com/mermaid-js/mermaid) — vendored offline for diagram rendering (MIT).
