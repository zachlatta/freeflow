<p align="center">
  <img src="Resources/AppIcon-Source.png" width="128" height="128" alt="FreeFlow icon">
</p>

<h1 align="center">FreeFlow</h1>

<p align="center">
  Free and open source alternative to <a href="https://wisprflow.ai">Wispr Flow</a>, <a href="https://superwhisper.com">Superwhisper</a>, and <a href="https://monologue.to">Monologue</a>.
</p>

<p align="center">
  <a href="https://github.com/zachlatta/freeflow/releases/latest/download/FreeFlow.dmg"><b>⬇ Download FreeFlow.dmg</b></a><br>
  <sub>Works on all Macs (Apple Silicon + Intel)</sub>
</p>

---

<p align="center">
  <img src="Resources/demo.gif" alt="FreeFlow demo" width="600">
</p>

<p align="center">
  <i>Thank you to <a href="https://github.com/marcbodea">@marcbodea</a> for maintaining FreeFlow!</i>
</p>

## Overview

FreeFlow is a free Mac dictation app inspired by [Wispr Flow](https://wisprflow.ai/), [Superwhisper](https://superwhisper.com/), and [Monologue](https://www.monologue.to/). It gives you fast AI transcription, context-aware cleanup, and voice-driven text editing without a monthly subscription.

## Quick Start

1. Download the app from above or [click here](https://github.com/zachlatta/freeflow/releases/latest/download/FreeFlow.dmg)
2. Get a free Groq API key from [groq.com](https://groq.com/)
3. Hold `Fn` to talk, or tap `Command-Fn` to start and stop dictation, and have whatever you say pasted into the current text field

## Features

- **Custom shortcuts:** Customize both hold-to-talk and toggle dictation shortcuts. If your toggle shortcut extends your hold shortcut, you can start in hold mode and press the extra modifier keys to latch into tap mode without stopping the recording.
- **Context-aware cleanup:** FreeFlow can read nearby app context so names, terms, and phrases are spelled correctly when you dictate into email, terminals, docs, and other apps.
- **Custom vocabulary:** Add names, jargon, and project-specific words that FreeFlow should preserve during cleanup.
- **OpenAI-compatible providers:** Use Groq by default, or configure a custom model and API URL in settings.

## Edit Mode

Edit Mode lets you highlight existing text and transform it with a spoken instruction, like "make this shorter" or "turn this into bullets." Enable it in settings, then use your normal dictation shortcut on selected text, or choose Manual mode to require an extra modifier key.

## Privacy

There is no FreeFlow server, so FreeFlow does not store or retain your data. The only information that leaves your computer are API calls to your configured transcription and LLM provider.

## Custom Cleanup

If you'd rather keep cleanup more literal and less context-aware, you can paste this simpler prompt into the custom system prompt setting:

<details>
  <summary>Simple post-processing prompt</summary>

  <pre><code>You are a dictation post-processor. You receive raw speech-to-text output and return clean text ready to be typed into an application.

Your job:
- Remove filler words (um, uh, you know, like) unless they carry meaning.
- Fix spelling, grammar, and punctuation errors.
- When the transcript already contains a word that is a close misspelling of a name or term from the context or custom vocabulary, correct the spelling. Never insert names or terms from context that the speaker did not say.
- Preserve the speaker's intent, tone, and meaning exactly.

Output rules:
- Return ONLY the cleaned transcript text, nothing else. So NEVER output words like "Here is the cleaned transcript text:"
- If the transcription is empty, return exactly: EMPTY
- Do not add words, names, or content that are not in the transcription. The context is only for correcting spelling of words already spoken.
- Do not change the meaning of what was said.

Example:
RAW_TRANSCRIPTION: "hey um so i just wanted to like follow up on the meating from yesterday i think we should definately move the dedline to next friday becuz the desine team still needs more time to finish the mock ups and um yeah let me know if that works for you ok thanks"

Then your response would be ONLY the cleaned up text, so here your response is ONLY:
"Hey, I just wanted to follow up on the meeting from yesterday. I think we should definitely move the deadline to next Friday because the design team still needs more time to finish the mockups. Let me know if that works for you. Thanks."</code></pre>
</details>

## Using a Local Model

FreeFlow can use OpenAI-compatible local or self-hosted providers instead of Groq. In settings, configure the API base URL and model IDs for your local LLM provider, such as Ollama, LM Studio, or another OpenAI-compatible server. If your transcription backend uses a different endpoint from your LLM backend, set the transcription API URL separately.

Local models are often slower than hosted providers, especially on cold start, long recordings, or busy hardware.

<details>
  <summary>Configure longer timeouts for local models</summary>

  FreeFlow keeps the default network timeout at 20 seconds, but you can extend it with macOS defaults:

```bash
defaults write com.zachlatta.freeflow transcription_timeout_seconds -float 120
defaults write com.zachlatta.freeflow post_processing_timeout_seconds -float 120
defaults write com.zachlatta.freeflow context_request_timeout_seconds -float 120
```

The timeout keys are:

- `transcription_timeout_seconds`: audio transcription requests
- `post_processing_timeout_seconds`: transcript cleanup and edit mode requests
- `context_request_timeout_seconds`: nearby app context requests

Only positive values are used. Remove a custom timeout to return to the 20-second default:

```bash
defaults delete com.zachlatta.freeflow transcription_timeout_seconds
defaults delete com.zachlatta.freeflow post_processing_timeout_seconds
defaults delete com.zachlatta.freeflow context_request_timeout_seconds
```

</details>

## Configuring Without the Settings Window

The preferences and credentials documented below can be written from a shell, so a machine can be set up from dotfiles, a setup script, or a Nix or Homebrew module. Launch at Login is managed separately through macOS service registration.

Settings live in two places:

- **macOS defaults**, under `com.zachlatta.freeflow` for release builds or `com.zachlatta.freeflow.dev` for the default development build
- **API credentials**, in `~/Library/Application Support/FreeFlow/.settings` for release builds or `~/Library/Application Support/FreeFlow Dev/.settings` for the default development build, kept at mode `600`

Quit the matching app before changing settings externally and start it afterwards. FreeFlow loads transcription, shortcut, and macro settings at launch; external edits while it is running can be overwritten. Examples below target the release app. For `make` or `make run`, use `com.zachlatta.freeflow.dev` in every `defaults` command and `FreeFlow Dev` in the credential path. Custom `BUNDLE_ID` and `APP_NAME` builds use their configured domain and app directory.

```bash
defaults write com.zachlatta.freeflow preserve_exact_wording -bool true
defaults write com.zachlatta.freeflow post_processing_model -string "openai/gpt-oss-120b"
defaults write com.zachlatta.freeflow shortcut_start_delay -float 0.15
```

<details>
  <summary>All available keys</summary>

**Transcription**

| Key | Type | Notes |
|---|---|---|
| `transcription_model` | string | e.g. `whisper-large-v3-turbo` |
| `transcription_language` | string | empty for auto-detect |
| `output_language` | string | empty to keep the spoken language |
| `selected_microphone_id` | string | `default` for the system default |
| `realtime_streaming_enabled` | bool | |
| `realtime_streaming_model` | string | |

**Cleanup and context**

| Key | Type | Notes |
|---|---|---|
| `post_processing_model` | string | |
| `post_processing_fallback_model` | string | used when the primary model fails |
| `context_model` | string | model for nearby app context |
| `custom_system_prompt` | string | empty for the built-in prompt |
| `custom_context_prompt` | string | empty for the built-in prompt |
| `custom_vocabulary` | string | newline-separated terms |
| `instruction_execution_guard_enabled` | bool | |
| `preserve_exact_wording` | bool | |
| `context_screenshot_max_dimension` | integer | `1024`, `768`, `640`, or `512`; other values use `1024` |
| `context_desktop_screenshot_fallback_enabled` | bool | default `true`; capture the desktop when the active window cannot be captured |

**Edit Mode**

| Key | Type | Notes |
|---|---|---|
| `command_mode_enabled` | bool | |
| `command_mode_style` | string | automatic or manual |
| `command_mode_manual_modifier` | string | modifier for manual mode |

**Behaviour**

| Key | Type | Notes |
|---|---|---|
| `preserve_clipboard` | bool | restore the clipboard after pasting |
| `keep_dictation_in_clipboard_history` | bool | |
| `press_enter_voice_command_enabled` | bool | |
| `dictation_audio_interruption_enabled` | bool | |
| `shortcut_start_delay` | float | seconds |
| `hotkey_option` | string | |

**Appearance and sound**

| Key | Type | Notes |
|---|---|---|
| `show_menu_bar_icon` | bool | |
| `use_compact_overlay` | bool | |
| `show_recording_timer` | bool | default `false`; show elapsed recording time |
| `overlay_display_id` | integer | `0` for the active display |
| `alert_sounds_enabled` | bool | |
| `sound_volume` | float | `0` to `1` |

**Timeouts** are documented under [Using a Local Model](#using-a-local-model): `transcription_timeout_seconds`, `post_processing_timeout_seconds` and `context_request_timeout_seconds`.

</details>

### Shortcuts and voice macros

These are stored as JSON. Write them as a plain string:

```bash
defaults write com.zachlatta.freeflow hold_shortcut -string \
  '{"modifiers":0,"kind":"modifierKey","keyCode":63,"keyDisplay":"Fn","preset":"fn"}'

defaults write com.zachlatta.freeflow voice_macros -string \
  '[{"command":"my address","payload":"221B Baker Street, London"}]'
```

The keys are `hold_shortcut`, `toggle_shortcut`, `copy_again_shortcut`, their `saved_*_custom_shortcut` counterparts, and `voice_macros`.

A voice macro's `id` is generated when you leave it out, so you only need `command` and `payload`.

The simplest way to find the JSON for a shortcut is to set it once in Settings and read it back. FreeFlow writes these keys as binary data, which `defaults read` prints as hex, so decode it:

```bash
defaults export com.zachlatta.freeflow - \
  | plutil -extract hold_shortcut raw -o - - \
  | base64 --decode
```

A value you wrote yourself with `-string` is stored as text, so plain `defaults read com.zachlatta.freeflow hold_shortcut` shows it as-is.

### API credentials

These are not stored in `defaults`. Run the constant command below, then enter the key at its hidden terminal prompt. For provisioning, pipe the key directly from your secret manager to this command. Do not put the key in the command text, a shell variable, or the environment. The installed macOS Ruby reads one UTF-8 line from stdin and encodes it as JSON data. Use `FreeFlow Dev` in the path for the default development app.

The recipe updates the general key and URL, preserves other string entries, and adds missing migration metadata as described below. It restricts an existing file to owner read/write before reading it, stages the update in a private 0600 sibling file, and replaces the original only after validation and a complete write. Malformed JSON, non-string values, keys over 16 KiB, existing files over 1 MiB, and empty or cancelled input fail without replacing the original contents. Permission tightening may still occur on failure.

```bash
/usr/bin/ruby -rjson -rio/console -rtempfile -rfileutils -e '
begin
  File.umask(0o077)
  settings = File.join(ENV.fetch("HOME"), "Library/Application Support/FreeFlow/.settings")
  directory = File.dirname(settings)
  FileUtils.mkdir_p(directory, mode: 0o700)
  raise IOError if File.symlink?(settings)
  values = {}
  if File.exist?(settings)
    raise IOError unless File.file?(settings)
    File.chmod(0o600, settings)
    raw = File.binread(settings, 1_048_577).force_encoding(Encoding::UTF_8)
    raise ArgumentError unless raw.bytesize <= 1_048_576 && raw.valid_encoding?
    values = JSON.parse(raw)
  end
  raise TypeError unless values.is_a?(Hash) &&
    values.all? { |name, value| name.is_a?(String) && value.is_a?(String) }
  STDIN.set_encoding(Encoding::UTF_8)
  key = if STDIN.tty?
    STDIN.noecho do
      STDERR.print("API key: ")
      STDIN.gets(16_386)
    end
  else
    STDIN.gets(16_386)
  end
  STDERR.puts if STDIN.tty?
  raise ArgumentError if key.nil?
  key = key.chomp
  raise ArgumentError unless key.valid_encoding? &&
    key.bytesize <= 16_384 && !key.strip.empty?
  values["groq_api_key"] = key
  values["api_base_url"] = "https://api.groq.com/openai/v1"
  values["keychain_migration_done"] = "true" unless values.key?("keychain_migration_done")
  Tempfile.create([".settings.", ".tmp"], directory) do |file|
    file.chmod(0o600)
    file.write(JSON.generate(values))
    file.flush
    file.fsync
    file.close
    File.rename(file.path, settings)
  end
rescue StandardError, Interrupt
  STDERR.puts("Credential update cancelled or failed.")
  exit 1
end
'
```

The recognised keys are `groq_api_key`, `api_base_url`, `transcription_api_url` and `transcription_api_key`. Omit any you do not need.

Successful provisioning also sets `keychain_migration_done` to the string `true` if that entry is absent, preserving an existing value exactly. This global marker prevents first-launch legacy Keychain migration from overwriting the explicit key. Its presence suppresses import for every account, including transcription overrides you have not provisioned. The recipe does not merge or delete legacy Keychain entries, and it leaves the runtime migration behavior unchanged.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for how to set up the project, build, test, and submit changes.

## License

Licensed under the MIT license.
