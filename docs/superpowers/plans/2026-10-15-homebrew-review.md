# Homebrew review follow-up implementation plan

> For agentic workers: use `superpowers:executing-plans` to implement this plan in the existing PR #284 worktree.

Goal: keep the cask and installation documentation independently reviewable, update the release pin, and accurately report the requested validation.

Architecture: remove the cask update job from the existing release workflow. Reuse Homebrew's own cask validation and the repository's existing checks without adding dependencies or application abstractions.

Tech stack: Ruby Homebrew cask DSL, GitHub Actions YAML, Markdown, Make, Swift.

Spec: `docs/agent-decisions.md`, PR #284 review 5438863505, and issue #283.

## Global constraints

Preserve the published branch history. Merge current upstream trunk normally; never rebase or force-push. Do not push or publish issue/PR replies. Do not install tools or bootstrap missing Homebrew developer dependencies. Do not edit generated changelogs or add comments. Keep the tap and ownership decision explicitly pending upstream approval.

## Design synthesis

Software practices: use one focused, independently reviewable change, reuse checks already maintained upstream, and distinguish local evidence from release qualification. Keep the existing PR branch and merge current trunk to obtain its checks. No feature flag is useful for a cask metadata update or deleted workflow step. Root coordinates the two required frozen-target review tracks before any push.

Ponytail: reuse the existing cask and upstream check targets; delete the release automation rather than replacing it. No new test framework, service, update abstraction, or helper script is required. Official Homebrew checks and a downloaded-artifact digest comparison test the actual distribution metadata.

Tiger-style: retain an exact release pin and SHA-256, preserve validation at Homebrew's download boundary, and limit changes to declarative configuration and documentation. No new functions, loops, or runtime invariants are introduced.

## Review focus

An obsolete pin must fail comparison with the verified stable artifact before editing. The final cask must load in Homebrew and preserve the app identifier, macOS floor, and uninstall/zap paths. Removing automation must leave release publication and cleanup intact. Merge resolution must preserve current upstream workflow behavior. Missing Homebrew dependencies or unsupported upstream distribution ownership must remain explicit gaps.

### Task 1: Resolve the Homebrew review

Files: modify `.github/workflows/release.yml`, `Casks/freeflow.rb`, `README.md`, `.gitignore`, and `docs/agent-decisions.md`; preserve this plan as the local execution record.

Interfaces: consume GitHub's v1.3.1 `FreeFlow.dmg` and public release digest; produce a cask with the same version and SHA-256, a release workflow without cask pushes, and documentation that does not claim unapproved support.

- [x] Record the baseline: run `make check`, compare the cask pin with the downloaded stable asset, and inspect Homebrew developer dependencies without installing them. The old pin comparison must fail.
- [x] Merge `upstream/main` into this existing branch using a normal merge. Resolve only relevant conflicts while preserving upstream changes.
- [x] Remove the Homebrew bump step, set version `1.3.1` and its verified SHA-256, qualify the cask install command, disclose the pending #283 decision, and ignore `graphify-out/` plus genuinely local state.
- [x] Run `make check`, `git diff --check`, Homebrew style/audit if their dependencies are already usable, and the artifact/cask consistency check. Record each outcome and any blocker in the decision record. Coordinate graph refresh with root.
- [x] Commit the changes without pushing, freeze the target for root's parallel code/security review, and provide the commit, exact scope, validation evidence, and remaining upstream decisions.

## Progress ledger

Task 1 baseline: the published branch pins v1.2.0; current stable is v1.3.1. Its Makefile has no `check` target. Root authorized a normal merge of `upstream/main` to obtain the current checks and preserve published history.

Ruling: use public-release byte verification and official cask checks for this declarative change instead of adding a test that mirrors fixed strings. No application logic changes or test dependency installations are needed.

Task 1 implementation: upstream merge `5795698` is recorded. The obsolete pin comparison failed before editing; the new pin matches the downloaded artifact and Homebrew's native cask loader. Release YAML has zero diff against current upstream. Graph refresh completed. Homebrew style/audit prerequisites are unavailable without installation. After one 180-second timeout, a fresh `make check` exited 0 in 115 seconds with `FreeFlowTests passed` and configuration/shell validation passing. Existing Swift availability and Ruby ffi extension warnings are recorded in the decision document. The implementation is ready to freeze for root's required review tracks; upstream tap approval and full Homebrew style/audit remain unresolved.

### Task 2: Refresh the final target against newer upstream

Files: merge the exact upstream source revision and update this plan plus `docs/agent-decisions.md`. Change `Casks/freeflow.rb` only if the actual published stable DMG differs from its existing verified pin. Preserve the proposed Homebrew guidance and upstream release workflow.

Interfaces: consume upstream commit `797a3f32e6b525b8d942512db2801466d3a651f7`, official release metadata, and downloaded stable DMG bytes; produce a history-preserving branch head, current check evidence, and a frozen handoff for root's final review.

- [x] Verify the existing worktree and official release endpoints. The exact v1.3.2 release endpoint returns HTTP 404; latest stable remains v1.3.1. Keep the existing cask version and checksum pending independent downloaded-byte verification.
- [x] Merge the authorized upstream SHA normally and confirm the release workflow remains byte-identical to that target.
- [x] Verify the downloaded stable asset, native Ruby/Homebrew cask checks, current `make check`, and `git diff --check`; record elapsed times and the existing Homebrew dependency gap.
- [x] Refresh the isolated graph, commit without pushing, and hand the exact head plus receipt to root for the final review tracks.

Task 2 ruling: published release metadata and downloaded artifact bytes determine the cask pin. A newer upstream source version alone does not authorize a different download URL or checksum. This mechanical refresh uses the existing design and checks without adding test scaffolding.

Task 2 implementation: merge `87ece29db92a720f18027cb7a3997d8d56b5aab2` preserves the published history and includes exact upstream `797a3f32e6b525b8d942512db2801466d3a651f7`. The re-downloaded v1.3.1 DMG matches both the existing cask and GitHub's digest, so no cask source change was made. `make check` passed in 60.25 seconds; native cask validation passed in 1.79 seconds; Ruby syntax and whitespace validation passed. The release workflow has zero diff from the new upstream target. Graph refresh reports 1,537 nodes and 3,635 edges. Style/audit still lack installed RuboCop prerequisites. Exact frozen head and command evidence are recorded in the external refresh receipt for root's coordinated review.
