# Contributing to FreeFlow

## Building and running locally

```bash
make run
```

This compiles the app and code-signs it with the identity named in `CODESIGN_IDENTITY` (`FreeFlow Dev` by default).

### Accessibility (or Microphone/Screen Recording) permission keeps disappearing after every rebuild

If you build from source without a matching signing identity in your keychain, `make` falls back to an ad-hoc signature. Ad-hoc signatures have no stable subject, so macOS treats every rebuild as a new, different app — any Accessibility/Microphone/Screen Recording grant you gave the previous build silently stops applying, even though System Settings may still show an old, now-stale entry.

**Fix: create a local self-signed code-signing certificate named `FreeFlow Dev`** so every rebuild shares the same signing identity, and macOS remembers your permission grants across rebuilds:

1. Open **Keychain Access** → menu bar **Keychain Access → Certificate Assistant → Create a Certificate…**
2. Name: `FreeFlow Dev`. Identity Type: **Self Signed Root**. Certificate Type: **Code Signing**.
3. Leave the rest at their defaults and click **Create**.
4. Run `make clean && make` — the build log should now say `build/FreeFlow Dev.app: replacing existing signature` and `codesign -dv "build/FreeFlow Dev.app"` should show `Authority=FreeFlow Dev` instead of an `adhoc` flag.
5. Launch the app and grant Accessibility/Microphone/Screen Recording once more. Future rebuilds will keep this same identity, so you should not need to re-grant them again.

If you ever see a stale, disabled entry for FreeFlow (or FreeFlow Dev) in System Settings → Privacy & Security, remove it with the **−** button rather than just toggling it — a leftover ad-hoc entry can conflict with the newly-signed build.
