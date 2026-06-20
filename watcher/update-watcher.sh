#!/usr/bin/env bash
# update-watcher.sh — FreeFlow fork upstream watcher
#
# 1. Checks the latest upstream release via GitHub API
# 2. Compares against .last-version in the fork root
# 3. If newer: clones the new tag, uses pi to apply fork.md patches, builds & installs
# 4. Pipes the git diff of applied changes to claude for review
# 5. Saves the review to watcher/last-review.md
# 6. Records the new version in .last-version
#
# Run standalone or via launchd (see plist template at the bottom of this file).
#
# Dependencies: git, curl, pi (~/.local/bin/pi or in PATH), claude (in PATH)
# Note: If curl fails with "Bad file descriptor" or similar socket errors,
#       temporarily disable LuLu (outbound firewall) and re-run.

set -euo pipefail

FORK_DIR="/Users/personal/Documents/code/freeflow-fork"
FORK_MD="$FORK_DIR/fork.md"
LAST_VERSION_FILE="$FORK_DIR/.last-version"
WATCHER_DIR="$FORK_DIR/watcher"
REVIEW_FILE="$WATCHER_DIR/last-review.md"
UPSTREAM_API="https://api.github.com/repos/zachlatta/freeflow/releases/latest"
UPSTREAM_CLONE_BASE="https://github.com/zachlatta/freeflow"
CLONE_SCRATCH="/tmp/freeflow-upstream-update"

# Resolve pi binary
PI_BIN=""
if command -v pi &>/dev/null; then
    PI_BIN="pi"
elif [[ -x "$HOME/.local/bin/pi" ]]; then
    PI_BIN="$HOME/.local/bin/pi"
else
    echo "ERROR: pi not found in PATH or ~/.local/bin/pi" >&2
    exit 1
fi

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

# ── Step 1: Fetch latest upstream version ────────────────────────────────────

log "Fetching latest upstream release from GitHub API..."

# curl may fail with socket errors if LuLu (outbound firewall) is active.
# If you see "Bad file descriptor" or similar, disable LuLu temporarily.
RELEASE_JSON=$(curl --silent --fail --max-time 30 "$UPSTREAM_API" 2>&1) || {
    echo "ERROR: curl failed fetching $UPSTREAM_API" >&2
    echo "If you see 'Bad file descriptor' or network errors, disable LuLu temporarily." >&2
    exit 1
}

# Parse tag_name — try jq first, fall back to python3, then grep/sed
if command -v jq &>/dev/null; then
    LATEST_VERSION=$(echo "$RELEASE_JSON" | jq -r '.tag_name')
elif command -v python3 &>/dev/null; then
    LATEST_VERSION=$(echo "$RELEASE_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin)['tag_name'])")
else
    # Last-resort: grep for "tag_name" field
    LATEST_VERSION=$(echo "$RELEASE_JSON" | grep -o '"tag_name"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*: *"//;s/"//')
fi

if [[ -z "$LATEST_VERSION" || "$LATEST_VERSION" == "null" ]]; then
    echo "ERROR: Could not parse tag_name from GitHub API response." >&2
    echo "Response was: $RELEASE_JSON" >&2
    exit 1
fi

log "Latest upstream version: $LATEST_VERSION"

# ── Step 2: Compare against stored version ────────────────────────────────────

STORED_VERSION=""
if [[ -f "$LAST_VERSION_FILE" ]]; then
    STORED_VERSION=$(cat "$LAST_VERSION_FILE")
fi

log "Stored version: ${STORED_VERSION:-<none>}"

if [[ "$LATEST_VERSION" == "$STORED_VERSION" ]]; then
    log "Already up to date ($LATEST_VERSION). Nothing to do."
    exit 0
fi

log "New upstream version detected: $STORED_VERSION -> $LATEST_VERSION"

# ── Step 3: Clone new tag and apply patches via pi ────────────────────────────

NEW_SRC_DIR="$CLONE_SCRATCH/$LATEST_VERSION"

if [[ -d "$NEW_SRC_DIR" ]]; then
    log "Removing stale clone at $NEW_SRC_DIR..."
    rm -rf "$NEW_SRC_DIR"
fi

mkdir -p "$CLONE_SCRATCH"
log "Cloning $UPSTREAM_CLONE_BASE at tag $LATEST_VERSION..."
git clone --depth 1 --branch "$LATEST_VERSION" "$UPSTREAM_CLONE_BASE" "$NEW_SRC_DIR" 2>&1 || {
    echo "ERROR: git clone failed. If network errors, disable LuLu temporarily." >&2
    exit 1
}

log "Applying fork patches via pi..."
"$PI_BIN" --model qwen2.5-coder:7b \
    "Read $FORK_MD. For each patch P1-P10 (and sub-patches P7a/P7b/P7c, P9a/P9b/P9c), apply the Search→Replace to the corresponding file in $NEW_SRC_DIR. Report which patches applied cleanly and which had conflicts."

log "Patches applied (see pi output above)."

# ── Step 4: Build and install ─────────────────────────────────────────────────

log "Building in $NEW_SRC_DIR..."
(cd "$NEW_SRC_DIR" && make) || {
    echo "ERROR: Build failed in $NEW_SRC_DIR" >&2
    exit 1
}

log "Installing app..."
cp -r "$NEW_SRC_DIR/build/FreeFlow Dev.app" "/Users/personal/Applications/FreeFlow Dev.app"
xattr -dr com.apple.quarantine "/Users/personal/Applications/FreeFlow Dev.app"
log "Installed: /Users/personal/Applications/FreeFlow Dev.app"

# ── Step 5: Review applied patches via claude ─────────────────────────────────

log "Generating review of applied patches..."
mkdir -p "$WATCHER_DIR"

DIFF_OUTPUT=$(git -C "$NEW_SRC_DIR" diff 2>/dev/null || true)

if [[ -z "$DIFF_OUTPUT" ]]; then
    log "WARNING: git diff returned empty — patches may not have been applied."
    REVIEW="WARNING: git diff was empty. pi may not have applied the patches, or they were already present.\n\nNo review generated."
    printf '%b' "$REVIEW" > "$REVIEW_FILE"
else
    REVIEW=$(echo "$DIFF_OUTPUT" | claude --print \
        "Review these fork patches for correctness: do they apply cleanly and preserve the intended behavior?" \
        2>&1) || {
        REVIEW="ERROR: claude review failed. Diff was:\n\n$DIFF_OUTPUT"
    }

    {
        echo "# Fork Patch Review — $LATEST_VERSION"
        echo ""
        echo "Generated: $(date '+%Y-%m-%d %H:%M:%S')"
        echo ""
        echo "## Claude Review"
        echo ""
        echo "$REVIEW"
        echo ""
        echo "## Raw Diff"
        echo ""
        echo '```diff'
        echo "$DIFF_OUTPUT"
        echo '```'
    } > "$REVIEW_FILE"
fi

log "Review saved to $REVIEW_FILE"

# ── Step 6: Record new version ────────────────────────────────────────────────

echo "$LATEST_VERSION" > "$LAST_VERSION_FILE"
log "Version updated to $LATEST_VERSION in $LAST_VERSION_FILE"
log "Done."

# ── Cleanup scratch dir ───────────────────────────────────────────────────────

rm -rf "$NEW_SRC_DIR"
log "Cleaned up $NEW_SRC_DIR"

: <<'LAUNCHD_PLIST_EXAMPLE'
# ── launchd plist example ─────────────────────────────────────────────────────
#
# Save as ~/Library/LaunchAgents/com.personal.freeflow-update-watcher.plist
# then: launchctl load ~/Library/LaunchAgents/com.personal.freeflow-update-watcher.plist
#
# <?xml version="1.0" encoding="UTF-8"?>
# <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
#   "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
# <plist version="1.0">
# <dict>
#     <key>Label</key>
#     <string>com.personal.freeflow-update-watcher</string>
#
#     <key>ProgramArguments</key>
#     <array>
#         <string>/bin/bash</string>
#         <string>/Users/personal/Documents/code/freeflow-fork/watcher/update-watcher.sh</string>
#     </array>
#
#     <!-- Run once daily at 09:00 -->
#     <key>StartCalendarInterval</key>
#     <dict>
#         <key>Hour</key>
#         <integer>9</integer>
#         <key>Minute</key>
#         <integer>0</integer>
#     </dict>
#
#     <key>StandardOutPath</key>
#     <string>/Users/personal/Documents/code/freeflow-fork/watcher/update-watcher.log</string>
#     <key>StandardErrorPath</key>
#     <string>/Users/personal/Documents/code/freeflow-fork/watcher/update-watcher.log</string>
#
#     <!-- Keep the agent alive on failure -->
#     <key>KeepAlive</key>
#     <false/>
#
#     <!-- Run immediately on load if the scheduled time was missed -->
#     <key>RunAtLoad</key>
#     <false/>
# </dict>
# </plist>
LAUNCHD_PLIST_EXAMPLE
