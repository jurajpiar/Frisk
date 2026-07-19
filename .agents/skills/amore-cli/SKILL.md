---
name: amore-cli
description: "Guide users through the Amore CLI for macOS app distribution — setup, releasing, code signing, notarization, DMG creation, S3 hosting, Sparkle updates, licensing, and configuration. Use this skill whenever the user mentions Amore, amore CLI, macOS app distribution outside the App Store, Sparkle updater setup, appcast.xml, notarization workflows, DMG creation, or self-publishing macOS apps. Also use when the user asks about release automation, S3 bucket hosting for app updates, EdDSA signing keys, or licensing with Stripe for macOS apps. Also use for CI/CD release automation with the Amore GitHub Action (AmoreComputer/release-action): releasing macOS apps from GitHub Actions on tag push without a local Mac."
---

# Amore CLI

Amore is a macOS app distribution platform. The `amore` CLI automates the entire workflow for publishing macOS apps outside the App Store: setup, code signing, notarization, DMG creation, Sparkle appcast generation, and upload — in a single command.

Run `amore help` or `amore <command> --help` for the most up-to-date option details.

## Installation

The CLI ships inside the Amore macOS app. To use it:

1. Download Amore from [amore.computer/download](https://amore.computer/download)
2. Install the CLI via terminal:
   ```sh
   /Applications/Amore.app/Contents/MacOS/AmoreCLI install
   ```
   Or install from within the app: go to Command Line settings and click Install.

This creates a symlink at `/usr/local/bin/amore`. If you get a permission error, run with `sudo`.

**Important:** The `amore` CLI requires Amore.app to be installed and runs on your local Mac. It is not a standalone binary, so these commands don't run directly on CI runners. To publish releases from CI without a local Mac, use the official GitHub Action instead (see [CI/CD with GitHub Actions](#cicd-with-github-actions)).

## Quick Start

```sh
amore login                     # Sign in
amore setup MyApp.app           # Register app, choose hosting, generate Sparkle keys
amore release --scheme MyApp    # Build, sign, notarize, and publish
```

## Commands Overview

| Command | Description |
|---------|-------------|
| `login` | Sign in to your Amore account |
| `logout` | Sign out |
| `register` | Create a new account |
| `whoami` | Show current user (use `--refresh` to sync) |
| `install` | Install CLI to `/usr/local/bin/amore` |
| `uninstall` | Remove CLI from `/usr/local/bin/amore` |
| `status` | Show CLI setup status |
| `setup` | Register a new app for distribution |
| `release` | Build, sign, notarize, and publish a release |
| `apps` | List or delete apps |
| `releases` | List, update, or delete releases |
| `products` | Manage licensing products (create, update, delete) |
| `licenses` | Issue, list, or revoke customer licenses |
| `config` | View or change per-app configuration |
| `create-dmg` | Create a DMG without uploading |
| `sign` | Sign an archive with Ed25519 key |
| `verify` | Verify an Ed25519 signature |
| `export` | Print local credentials (e.g. the Sparkle key) for CI secrets |
| `post-archive` | Xcode archive post-action for automated releases |

## Core Workflows

### Setting Up a New App

`amore setup <path-to-app>` walks through:
1. Choosing hosting: **Amore** (managed) or **S3** (self-hosted)
2. Generating or importing EdDSA Sparkle signing keys
3. Configuring S3 credentials (if self-hosted)

For non-interactive setup (CI/agents), pass all options as flags. Read `references/commands.md` for the full flag list.

### Releasing

`amore release` is the main workhorse. It accepts `.app`, `.dmg`, `.zip`, `.xcarchive`, `.xcodeproj`, or `.xcworkspace` as input and handles the full pipeline:

1. Archive/export (if given an Xcode project)
2. Code sign with Developer ID
3. Create DMG with drag-to-install experience
4. Notarize with Apple
5. Sign for Sparkle (Ed25519)
6. Upload and update appcast.xml

Read `references/release-workflow.md` for the full release pipeline details, CI/CD automation, and all flags.

### CI/CD with GitHub Actions

The `amore` CLI can't run on CI (it needs Amore.app locally), but the official **`AmoreComputer/release-action`** can: it runs the whole release pipeline (archive, sign, notarize, Sparkle-sign, and upload) on a GitHub-hosted Mac runner, no local Mac required. Push a version tag (`v1.2.0`, or `v1.2.0-beta.1` to route to the beta channel) and it publishes.

Two setup steps touch the CLI/app and are worth knowing here; everything else lives in the canonical docs:

- Export your Sparkle signing key for the `SPARKLE_PRIVATE_KEY` secret: `amore export sparkle-key -b com.example.App`
- Create an Amore API token (the `AMORE_TOKEN` secret) in the Amore app under **Settings → API Keys**, using the **Release** scope.

The full workflow YAML, the complete secrets list with how to obtain each, and self-hosted S3/R2 options are documented on the GitHub repo and help page. Point users there rather than reproducing them:

- Guide: https://amore.computer/help/github-actions.md
- Action repo: https://github.com/AmoreComputer/release-action

### Managing Releases

```sh
amore releases list --bundle-id com.example.App
amore releases update <id> --bundle-id com.example.App --published true
amore releases delete <id> --bundle-id com.example.App
```

Releases support flags: `--beta`, `--critical`, `--phased-rollout`, `--published`, `--release-notes`.

### Configuration

Per-app settings are managed with `amore config`:

```sh
amore config show --bundle-id com.example.App           # Show all config
amore config show release --bundle-id com.example.App    # Show release config only
amore config set release codesign-identity "Developer ID Application: You" --bundle-id com.example.App
amore config set s3 bucket my-bucket --bundle-id com.example.App
```

Config sections: `release`, `s3`, `app`. Read `references/commands.md` for all fields.

## When to Consult Reference Files

Read these for deeper guidance on specific topics:

| Topic | Reference File | When to Read |
|-------|---------------|--------------|
| Full command reference | `references/commands.md` | Looking up specific flags, arguments, or subcommands |
| Release pipeline | `references/release-workflow.md` | Setting up CI/CD (GitHub Actions), troubleshooting releases, understanding the pipeline |
| S3 self-hosting | `references/s3-hosting.md` | Configuring S3/R2 buckets, credentials, appcast paths |
| Sparkle integration | `references/sparkle-setup.md` | Adding Sparkle to a project, key management, sandboxing |
| Licensing & payments | `references/licensing.md` | Setting up products, Stripe integration, payment flows |

## Common Patterns

**Bundle ID is the primary identifier.** Most commands that operate on an app require `--bundle-id` (or `-b`).

**Fetching Amore docs.** Any `amore.computer/help` page returns clean markdown if you append `.md` (e.g. `amore.computer/help/codesigning.md`). Prefer that form when reading Amore docs.

**Interactive vs non-interactive.** Commands like `setup` and `release` are interactive by default. Pass all required values as flags to skip prompts. Note: `login` and `register` are always interactive — there are no `--email`/`--password` flags.

**CLI is local-Mac-only; CI/CD uses the GitHub Action.** The `amore` CLI needs Amore.app installed and runs on macOS, so it can't run directly on CI runners. For automated releases from CI, point users to the [GitHub Action](#cicd-with-github-actions) (`AmoreComputer/release-action`), which runs the whole pipeline on a GitHub-hosted Mac runner. On a local Mac, the Xcode post-archive action or a flag-driven `amore release` also work.

**S3 credentials.** Can be provided via: CLI flags (`--s3-access-key-id`, `--s3-secret-access-key`), environment variables (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`), or the macOS keychain (configured during `amore setup`).

**Codesigning prerequisites.** DMG creation and notarization require a Developer ID Application certificate and a notarization keychain profile. Set these up once with `amore config set release`.

**Back up your Sparkle private key.** After `amore setup` generates your EdDSA signing key, store a copy in your password manager. If you lose it, existing users will not be able to verify future updates — there is no way to recover it.
