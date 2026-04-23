# FreeFlow iOS

iOS port of FreeFlow — Groq-powered voice-to-text as a custom iOS keyboard. Transcribes via `whisper-large-v3`, cleans up with `openai/gpt-oss-20b` (with `llama-4-scout` fallback), and inserts the result at the cursor in any app.

Superwhisper-style, same backend as the macOS parent project. Minus the three features that iOS cannot provide from a keyboard extension: global shortcuts, context-aware cleanup (no access to other apps), and edit mode (no access to selected text).

The macOS app in the repo root is untouched.

## Layout

```
ios/
  FreeFlowShared/   Swift sources compiled into both targets (transcription, post-processing, storage)
  FreeFlowApp/      Main iOS app (settings, API key, custom prompt, history)
  FreeFlowKeyboard/ Custom keyboard extension (mic button, pipeline)
  project.yml       XcodeGen spec — generates FreeFlow.xcodeproj
```

---

## One-time setup on this Mac

1. **Install Xcode 16+** from the Mac App Store (≈ 10 GB). Already done per prior setup.
2. **Point `xcode-select` at the full Xcode install** (currently set to Command Line Tools):
   ```
   sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
   sudo xcodebuild -license accept
   ```
3. **Install XcodeGen** (generates the `.xcodeproj` from `project.yml`):
   ```
   brew install xcodegen
   ```
4. **Open Xcode once**, sign in at *Xcode → Settings → Accounts* with your Apple ID. This creates the free personal team used to sign builds.

## Generate the Xcode project

From `ios/`:
```
cd ios
xcodegen generate
open FreeFlow.xcodeproj
```

In Xcode, select both the `FreeFlowApp` and `FreeFlowKeyboard` targets under *Signing & Capabilities* and set **Team** to your personal team. Xcode will auto-create provisioning profiles for both bundle IDs:
- `com.shebetoff.freeflow.ios` (main app)
- `com.shebetoff.freeflow.ios.keyboard` (keyboard extension)

If Xcode warns about the App Group / Keychain Sharing capabilities being unavailable on a free team, see the **Free-account caveats** section below.

---

## Install on your iPhone (free account path — your current setup)

1. Connect your iPhone over cable.
2. iPhone → Settings → Privacy & Security → **Developer Mode: On** (iOS 16+ requirement). Your phone reboots.
3. In Xcode, select your device in the target dropdown (top toolbar).
4. Select the `FreeFlowApp` scheme, press **⌘R** (or the Play button). The app builds, installs, and launches.
5. On first launch the iPhone shows *"Untrusted Developer"*. Dismiss, then go to **Settings → General → VPN & Device Management**, tap your Apple ID under *Developer App*, and **Trust**.
6. Reopen FreeFlow on the iPhone.

**Expires after 7 days.** Re-run ⌘R in Xcode with the iPhone connected to refresh. No way around this without a paid developer account.

## Configure the app

1. Open the **FreeFlow** app on iPhone.
2. Tap *Setup* tab:
   - Paste your Groq API key (get one free at https://console.groq.com/keys).
   - Tap **Validate key** — should go green.
   - Tap **Request** on the microphone row — grant permission.
3. Add the FreeFlow keyboard:
   - iOS Settings → General → Keyboard → Keyboards → **Add New Keyboard…** → FreeFlow
   - Tap the FreeFlow row → toggle **Allow Full Access** on (required for network + microphone)
4. (Optional) Under the Settings tab, edit the *Custom system prompt* — this is the headline feature. Leave empty to use the built-in prompt.

## Dictate in any app

iOS does not let keyboard extensions access the microphone directly (Apple has blocked this since 2014 for privacy — keyboards can't silently listen). FreeFlow works around this the same way Superwhisper does: the **main app** owns the microphone, the **keyboard** just sends start/stop commands to it via an App Group. After the first tap, the main app stays primed in the background for a few minutes (configurable) so subsequent taps don't need an app-switch.

1. Open any app with a text field (Notes, Messages, Mail).
2. Long-press the globe key → pick **FreeFlow**.
3. **First tap of the mic button**: FreeFlow briefly opens and immediately backgrounds itself; iOS returns you to your original app with the keyboard still up. The keyboard's mic is now green ("Ready to dictate — session stays primed for Xs").
4. **Tap the mic again**: recording starts (the main app is recording in the background). Speak. Tap once more to stop.
5. Cleaned text appears at the cursor ~1–2 seconds later.
6. For the next few minutes, the mic button works instantly with no app-switch. After the primed-session expires (default 5 min, configurable in Settings → Keyboard), the first tap will briefly open FreeFlow again to re-prime.
7. Tap the globe to switch back to the Apple keyboard for typing.

### Notes on the workaround
- The main app uses `UIBackgroundModes: audio` so iOS keeps it alive while an audio session is active. When the session expires or iOS reclaims resources, the next dictation triggers a quick re-prime cycle.
- The "immediate return to original app" step uses the private `UIApplication.suspend` selector. This is fine for self-signed / TestFlight builds but is not App Store-legal — not a concern for your distribution plan.
- If you see "Opening FreeFlow…" on the keyboard but it never primes, switch back to FreeFlow manually once — iOS sometimes needs the user to confirm a URL-scheme handoff the first time.

---

## Free-account caveats

Xcode signs with your free personal team for 7 days. On a free team the following entitlements are flaky:
- **App Groups** — the keyboard and main app share settings via `group.com.shebetoff.freeflow`. If Xcode refuses to sign because of this, the code falls back to per-extension storage: you will have to enter the API key in the keyboard UI as well as in the main app.
- **Keychain Sharing** — same issue. If it fails to sign, open `FreeFlowApp.entitlements` and `FreeFlowKeyboard.entitlements` and remove the `keychain-access-groups` entry, then re-generate with XcodeGen. The Keychain will then be per-process (iOS still persists it; cross-target sharing just breaks — the API key must be entered twice).

If you get the error `Provisioning profile … doesn't include the com.apple.security.application-groups entitlement`, that's the flaky-free-team symptom. Options:
- Remove the App Group from the keyboard entitlements file (the app will use per-extension defaults — history will not appear in the main app).
- Upgrade to the paid Apple Developer Program (see TestFlight section).

## Upgrade to TestFlight (paid path)

TestFlight requires a paid **Apple Developer Program** membership ($99/year — https://developer.apple.com/programs/). It also removes the 7-day expiry and the App Group flakiness.

Once enrolled:

1. In **App Store Connect** (https://appstoreconnect.apple.com/) → *Apps* → **+** → New App:
   - Bundle ID: `com.shebetoff.freeflow.ios` (select it from the dropdown — it will appear automatically after your first Xcode archive)
   - SKU: anything (e.g. `freeflow-ios-1`)
   - Primary language: English
2. In Xcode, select **Any iOS Device (arm64)** as the run destination.
3. **Product → Archive**. Wait for build to finish.
4. In the Organizer window that opens, select your archive → **Distribute App** → *App Store Connect* → *Upload*. Xcode auto-creates provisioning profiles for both the app and the keyboard extension.
5. After ~10 min, the build appears in App Store Connect → your app → *TestFlight* tab.
6. In App Store Connect → *TestFlight* → **Internal Testing**, create a group, add your Apple ID as a tester. Up to 100 internal testers; no beta app review needed.
7. On your iPhone, install **TestFlight** from the App Store (once). Sign in with the same Apple ID, accept the invite email, install FreeFlow.
8. TestFlight builds stay valid **90 days**; upload a new archive before expiry.

---

## What's in scope / skipped

**Ported from macOS:**
- Groq transcription (`whisper-large-v3`, configurable)
- LLM post-processing with primary + fallback model
- **Custom user-editable post-processing prompt**
- Custom vocabulary
- Voice macros (exact-match command → payload)
- OpenAI-compatible providers (custom base URL / models)
- Pipeline history
- Hallucination filter

**Skipped (no iOS equivalent from a keyboard extension):**
- Custom keyboard shortcuts — iOS keyboards do not receive global keypresses
- Context-aware cleanup — sandboxed keyboards cannot inspect other apps' UI, windows, or screenshots
- Edit mode — sandboxed keyboards cannot read selected text in the host app

---

## Troubleshooting

- **Keyboard shows "Enable Full Access"** — Settings → General → Keyboard → Keyboards → FreeFlow → toggle *Allow Full Access* on. Required for network + App Group sharing.
- **Keyboard shows "No API key"** — open the FreeFlow app, paste your Groq key on the Setup tab, relaunch any app using the keyboard.
- **Mic tap opens FreeFlow but doesn't return to my app** — iOS sometimes requires confirming a URL handoff the first time. Manually switch back to your original app; subsequent taps should auto-return.
- **Keyboard stays on "Opening FreeFlow…"** — tap the mic again, or manually switch to FreeFlow once. After the first successful prime, the flow stabilizes.
- **Session expires too quickly / too slowly** — adjust Settings → Keyboard → Primed session duration (1–15 minutes).
- **Cleaned text doesn't reflect the custom prompt** — tap *Save* after editing the prompt. The keyboard re-reads settings on every dictation.
- **Network errors / 401** — the API key is invalid or expired. Re-paste and re-validate in the main app.
- **`Provisioning profile doesn't include ... application-groups`** — see *Free-account caveats*.
