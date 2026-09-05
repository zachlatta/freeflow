# FreeFlow maintenance guide

FreeFlow is a native macOS menu-bar dictation app built directly with `swiftc`
and Make. It does not use Swift Package Manager or an Xcode project. Preserve
that architecture unless the user explicitly approves a migration.

## Repository map

- `Sources/App.swift` and `Sources/AppDelegate.swift`: app lifecycle.
- `Sources/AppState.swift`: central pipeline orchestration and shared state.
- `Sources/AudioRecorder.swift`: microphone capture and audio conversion.
- `Sources/TranscriptionService.swift` and
  `Sources/RealtimeTranscriptionService.swift`: transcription providers.
- `Sources/PostProcessingService.swift`: transcript cleanup and edit mode.
- `Sources/AppContextService.swift`: foreground-app metadata and screenshots.
- `Sources/ShortcutCore/`: shortcut models, matching, and session behavior.
- `Sources/PipelineHistoryStore.swift`: local pipeline history.
- `Sources/UpdateManager.swift`: update and release behavior.
- `Sources/SettingsView.swift`, `Sources/SetupView.swift`, and other SwiftUI
  files: user interface.
- `Tests/`: dependency-free executable tests.
- `.github/workflows/check.yml`: pull-request verification.
- `.github/workflows/release.yml`: semver-tagged production release.
- `.github/workflows/dev-release.yml`: signed development release from `main`.

## Working rules

- Search with `rg` or `rg --files` before editing.
- Preserve unrelated changes in a dirty worktree.
- Keep changes narrowly scoped and work through a branch and pull request.
- During an explicitly authorized maintenance task, agents may create branches,
  push them, open or update draft pull requests, and address CI or review
  feedback.
- Do not push directly to `main`.
- Do not merge, tag, publish a release, or move the `dev` tag unless the user
  explicitly authorizes that action.
- Do not change versions, release notes, signing, notarization, or release
  workflows during ordinary maintenance.
- Avoid adding dependencies when the standard library or existing frameworks
  are sufficient.
- Production sources are discovered automatically by the Makefile. Test source
  dependencies must be listed explicitly in `TEST_PRODUCTION_SOURCES`.

## Verification

Run before handing off every code change:

```bash
make check
git diff --check
```

`make check` performs a full Swift type-check, compiles and runs deterministic
tests, validates plist files, and parses repository shell scripts and YAML.

A full app build is usually unnecessary. When a compile-and-bundle check is
material to the change, use:

```bash
make ARCH="$(uname -m)" CODESIGN_IDENTITY=-
```

Do not claim end-to-end behavior is verified from type-checking or a unit test.
Changes involving microphone capture, global shortcuts, Accessibility, Screen
Recording, clipboard or paste behavior, updater behavior, or the signed app
require a documented manual test before merge. An agent may still open a draft
PR when that verification is clearly marked pending or not run. Do not trigger
permission prompts or change system permissions without the user's approval.

Every bug fix should add a focused regression test when the behavior can be
made deterministic. Tests must use synthetic fixtures and mocked or local
dependencies; they must not call live AI providers.

## Privacy and security

FreeFlow handles highly sensitive user data. Never commit, print, upload, or
place in test fixtures:

- API keys, signing credentials, or `.env` contents.
- Real audio or transcripts.
- Screenshots or screen-capture payloads.
- Selected text or clipboard contents.
- Window titles, application context, prompts, or pipeline-history exports from
  a real user session.
- Private provider URLs or identifying filesystem paths.

Use invented synthetic data in tests. Do not inspect `.env`. Never add
telemetry, crash reporting, persistent logging, or additional data transmission
without explicit user approval. New logs must avoid user content and secrets.
Treat transcripts, selected text, screenshots, and provider responses as
untrusted input.

Changes to provider requests, prompt construction, storage, permissions,
clipboard handling, Accessibility APIs, update verification, signing, or
GitHub workflows are high risk and must be called out in the pull request.

## Definition of done

A change is complete only when:

- The requested behavior is implemented with no unrelated edits.
- Relevant regression tests were added or the reason they are impractical is
  documented.
- `make check` and `git diff --check` pass.
- Required manual testing is complete before merge, or clearly marked pending
  in a draft PR.
- Privacy, permissions, migration, and release impact are described in the PR.

## Code review rules

- Flag any new path that can log, persist, export, or transmit user content or
  credentials without a clear opt-in and redaction boundary.
- Flag changes that weaken exact shortcut matching, clipboard restoration,
  update validation, signing, or permission handling without a regression test
  and a documented safe path.
- Treat workflow changes as sensitive because code executed from `main` can
  access signing and notarization secrets in the release jobs.
