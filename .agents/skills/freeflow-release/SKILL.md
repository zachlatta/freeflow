---
name: freeflow-release
description: Prepare and publish FreeFlow app releases. Use when the user asks to release FreeFlow, prepare a new version, bump the FreeFlow version, write or update FreeFlow changelog entries, validate a FreeFlow semver release, create a vX.Y.Z tag, or publish a signed FreeFlow DMG through the repository GitHub Actions release workflow.
---

# FreeFlow Release

## Overview

Use this skill to prepare a FreeFlow release from the local repository. FreeFlow releases are semver-tag driven: pushing a tag like `v0.3.1` triggers `.github/workflows/release.yml`, which stamps the app bundle, extracts the matching `CHANGELOG.md` section, builds/signs/notarizes the DMG, and creates the GitHub Release.

## Ground Rules

- Treat `CHANGELOG.md` as the release notes source of truth.
- Keep changelog language user-facing. Avoid implementation details unless they affect maintainers or troubleshooting.
- Do not edit `README.md` or unrelated docs unless the user explicitly asks.
- Do not push tags or branches until the user has approved the exact release version and changelog.
- Never use `git reset --hard` or destructive cleanup while preparing a release.
- Preserve unrelated working tree changes. If unrelated changes exist, report them and avoid staging them.

## Release Workflow

1. Inspect current state:
   ```bash
   git status --short --branch
   git log --oneline --decorate -n 20
   ```

2. Find the last version bump:
   ```bash
   git log --oneline --decorate -- Info.plist CHANGELOG.md .github/workflows/release.yml
   git blame -L 11,14 Info.plist
   ```
   Use the last commit that changed `CFBundleShortVersionString`, `CFBundleVersion`, or the prior release section as the start of the changelog range.

3. Determine the next version:
   - `PATCH` for fixes, polish, release-system updates, and small user-visible improvements.
   - `MINOR` for notable new user-facing capabilities.
   - `MAJOR` only for breaking behavior or major compatibility changes.
   Confirm the version with the user if it was not specified.

4. Build the changelog from the commit range:
   ```bash
   git log --first-parent --reverse --oneline <last-version-commit>..HEAD
   git log --reverse --oneline <last-version-commit>..HEAD
   git diff --stat <last-version-commit>..HEAD
   ```
   Prefer first-parent merge commits for feature grouping, then inspect individual commits for details. Write a concise section:
   ```md
   ## [0.3.1] - YYYY-MM-DD

   ### Added
   - User-facing new capabilities.

   ### Improved
   - User-facing improvements and reliability work.

   ### Fixed
   - User-visible bugs and update/release fixes.
   ```

5. Validate locally before commit/tag:
   ```bash
   .github/scripts/changelog-section.sh <version>
   ~/.codex/skills/freeflow-release/scripts/freeflow-release-check.sh <version>
   git diff --check
   make clean
   make ARCH="$(uname -m)" CODESIGN_IDENTITY=-
   ```

6. Commit only release-prep files:
   ```bash
   git add CHANGELOG.md
   git commit -m "Prepare v<version> release"
   ```
   Include other files only when they are deliberately part of the release prep.

7. After user approval, tag and push:
   ```bash
   git tag v<version>
   git push origin main
   git push origin v<version>
   ```

8. After GitHub Actions finishes, verify:
   - GitHub Release `v<version>` exists and is marked latest.
   - `FreeFlow.dmg` is attached.
   - Release body starts with the matching `CHANGELOG.md` section.
   - A previous app version detects the update and shows What’s New.

## Helper Script

Run `scripts/freeflow-release-check.sh <version>` from the FreeFlow repo root to check release preconditions. It validates semver shape, required files, changelog extraction, workflow trigger basics, and tag availability.
