# Amore Release Workflow

The `amore release` command handles the entire pipeline for publishing a macOS app update. This reference covers the pipeline stages, input formats, and CI/CD integration.

## Pipeline Stages

When you run `amore release`, it executes these steps in order:

1. **Import** — Accepts `.app`, `.dmg`, `.zip`, `.xcarchive`, `.xcodeproj`, or `.xcworkspace`
2. **Archive/Export** — If given an Xcode project/workspace, builds and exports the app
3. **Code Sign** — Signs the app with a Developer ID Application certificate
4. **Create DMG** — Packages the app into a DMG with a drag-to-install background
5. **Notarize** — Submits the DMG to Apple's notarization service and staples the ticket
6. **Sign for Sparkle** — Generates an Ed25519 signature for the Sparkle updater
7. **Upload** — Pushes the binary to Amore servers or your S3 bucket
8. **Update Appcast** — Regenerates `appcast.xml` with the new release entry

Steps 3-5 are skipped when using `--no-dmg` (outputs ZIP instead).

## Input Formats

| Format | What Happens |
|--------|-------------|
| `.xcodeproj` / `.xcworkspace` | Archived, exported, then full pipeline. Requires `--scheme`. |
| `.xcarchive` | Exported, then full pipeline. |
| `.app` | Full pipeline from code signing onward. |
| `.dmg` | Used as-is (no new DMG created). Signed for Sparkle and uploaded. |
| `.zip` | Used as-is. Signed for Sparkle and uploaded. |

## Prerequisites

For the full pipeline (with DMG and notarization), you need:

1. **Developer ID Application certificate** — Created in Xcode > Settings > Accounts > Manage Certificates
2. **Notarization keychain profile** — Created once with:
   ```sh
   xcrun notarytool store-credentials "my-notary-profile"
   ```
3. **Sparkle EdDSA keys** — Generated during `amore setup` or with `--generate-sparkle-key`

Configure these per-app:
```sh
amore config set release codesign-identity "Developer ID Application: You (TeamID)" -b com.example.App
amore config set release keychain-profile "my-notary-profile" -b com.example.App
```

Or pass them as flags to `amore release`.

## Automation

### GitHub Actions (recommended for CI)

The official **`AmoreComputer/release-action`** runs the entire release pipeline on a GitHub-hosted Mac runner, no local Mac required. Tag a release (`git tag v1.2.0 && git push origin v1.2.0`) and it archives, signs, notarizes, Sparkle-signs, and publishes. Beta tags (`v1.2.0-beta.1`) route to the beta channel.

You supply the signing material as repository secrets: the Developer ID certificate, an App Store Connect API key, your Sparkle private key (`amore export sparkle-key -b com.example.App`), and an Amore API token (created in the Amore app under Settings → API Keys, Release scope). Self-hosted S3/R2 is supported via extra inputs.

The complete workflow file, the secret-by-secret setup, and every input are documented at the canonical sources, linked here:

- Guide: https://amore.computer/help/github-actions.md
- Action repo: https://github.com/AmoreComputer/release-action

```sh
amore release --scheme MyApp \
  --codesign-identity "Developer ID Application: Company (TeamID)" \
  --keychain-profile "notary-profile" \
  --release-notes "Bug fixes and performance improvements"
```

S3 credentials can be provided via flags (`--s3-access-key-id`, `--s3-secret-access-key`) or environment variables (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`).

**Build-only (no upload):** Use `--output <dir>` to produce the artifact locally without uploading:
```sh
amore release --scheme MyApp --output ./build
```

## Xcode Post-Archive Action

For automatic releases after archiving in Xcode, add this post-action:

```sh
amore post-archive
```

Set it up in: Product > Scheme > Edit Scheme > Archive > Post-actions.

The command reads `PRODUCT_NAME` and `ARCHIVE_PATH` from the Xcode environment. It requires a codesign identity and keychain profile to be configured.

## Release Flags

| Flag | Effect |
|------|--------|
| `--beta` | Marks the release as beta (only delivered to beta testers) |
| `--critical` | Marks as critical update (shown prominently to users) |
| `--phased-rollout` | Gradually rolls out to users |
| `--draft` | Uploads but does not publish |
| `--no-dmg` | Outputs ZIP, skips codesigning and notarization |
| `--release-notes <text>` | Adds release notes to the appcast entry |

## Standalone DMG Creation

To create a DMG without releasing:

```sh
amore create-dmg MyApp.app
amore create-dmg MyApp.app --output ~/Desktop/MyApp.dmg --open
```

The DMG includes a custom background with drag-to-install experience. Free tier DMGs include an "Built with amore.computer" watermark.
