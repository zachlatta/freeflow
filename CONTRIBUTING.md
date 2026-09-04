# Contributing to FreeFlow

Thanks for your interest in contributing to FreeFlow! FreeFlow is a free and open-source macOS dictation app, and community contributions are welcome.

This guide describes how to set up the project, what conventions to follow, and how to submit your changes.

## Prerequisites

FreeFlow is a macOS app built with Swift and the macOS SDK. To build and test locally you need:

- A Mac running macOS 13.0 or later
- Xcode Command Line Tools (`xcode-select --install`)
- [create-dmg](https://github.com/sindresorhus/create-dmg) (only needed for producing disk images)
- A free [Groq API key](https://groq.com/) (or another OpenAI-compatible provider) to exercise end-to-end dictation

## Getting the Source

1. Fork this repository on GitHub.
2. Clone your fork:

   ```bash
   git clone https://github.com/<your-username>/freeflow.git
   cd freeflow
   git remote add upstream https://github.com/zachlatta/freeflow.git
   ```

3. Keep your fork in sync with upstream before starting new work:

   ```bash
   git fetch upstream
   git checkout main
   git merge upstream/main
   git push origin main
   ```

## Building

```bash
make            # builds FreeFlow.app into build/
make run        # builds and opens the app
```

The Makefile builds a `.app` bundle under `build/` using `swiftc` against the macOS SDK. It codesigns with a local "FreeFlow Dev" identity for development builds.

To produce a universal (Apple Silicon + Intel) binary:

```bash
make ARCH=universal
```

## Testing

```bash
make test
```

The test runner is a standalone Swift executable built from `Sources/AppContextService.swift`, `Sources/LLMAPITransport.swift`, `Sources/ModelConfiguration.swift`, and `Tests/AppContextServiceTests.swift`. It runs without a simulator or test host.

When adding features or fixing bugs, add or update tests in `Tests/` that cover the changed behavior. If your change touches code outside the currently tested files, extend the Makefile's `$(TEST_RUNNER)` target to include the new source files.

## Development Conventions

### Branches

Create a branch from `main` for each change. Descriptive names are helpful, for example:

- `feat/preserve-exact-wording`
- `fix/model-picker`
- `docs/contributing`

### Commit Messages

Write clear, concise commit messages in the imperative mood (e.g., "Add preserve-exact-wording toggle" rather than "Added preserve-exact-wording toggle"). There is no enforced commit-message format, but the existing history favors a short subject line optionally followed by a blank line and a body explaining the *why*.

### Code Style

- Swift code follows standard Swift formatting and naming conventions.
- Prefer small, focused changes that address a single issue or feature.
- Avoid unrelated refactors mixed into a feature or fix PR — if a refactor is needed, open a separate PR.

### Changelog

Add an entry under the `## [Unreleased]` section in [`CHANGELOG.md`](CHANGELOG.md) under the appropriate subsection:

- **Added** — new user-visible features or improvements.
- **Improved** — enhancements to existing behavior.
- **Fixed** — bug fixes.

Follow the existing entry style (one line per change, sentence case, no trailing period).

## Submitting Changes

1. Open a [pull request](https://github.com/zachlatta/freeflow/compare) against `zachlatta/freeflow:main`.
2. Include a description that covers:
   - **Summary** — what the PR does, in a sentence or two.
   - **Motivation** — why the change is needed (link the issue if one exists, e.g., `Closes #123`).
   - **Behavior** — what changes for users, especially anything that differs from the previous behavior.
   - **Changes** — the files touched and the nature of each change.
   - **Test plan** — how you verified the change works (manual testing steps, `make test` output, edge cases checked).
3. Keep PRs focused and small. An automated labeler flags PRs over 1000 lines with a reminder that large PRs may be rejected — if your change is large, consider splitting it into multiple PRs.
4. A bot ([CodeRabbit](https://coderabbit.ai)) posts an automated review on new PRs. Addressing its actionable comments helps move the review forward.
5. Be responsive to feedback from maintainers and other contributors.

## Reporting Issues

- Search [existing issues](https://github.com/zachlatta/freeflow/issues) before opening a new one to avoid duplicates.
- Include the FreeFlow build number and macOS version (both are shown in the app's About or Settings window).
- Describe what you expected, what happened, and the steps to reproduce.
- Feature requests are welcome — label them as `enhancement` and explain the use case.

## Discussions

For ideas, questions, and show-and-tell that don't fit a specific issue, use [GitHub Discussions](https://github.com/zachlatta/freeflow/discussions).

## License

By contributing, you agree that your contributions are licensed under the [MIT license](LICENSE) that covers the project.