> **Work in progress.** FreeFlow is under active development and not ready for others to use yet.

<p align="center">
  <img src="Resources/AppIcon-README.png" width="128" height="128" alt="FreeFlow icon">
</p>

<h1 align="center">FreeFlow</h1>

<p align="center">
  Free and open source voice-to-text for Mac.<br>
  A free alternative to <a href="https://wisprflow.ai">Wispr Flow</a>, <a href="https://superwhisper.com">SuperWhisper</a>, and <a href="https://monologue.to">Monologue</a>.
</p>

<p align="center">
  Hold a key to record, release to transcribe. Works everywhere on your Mac.
</p>

<div align="center">

| | Download | Mac Compatibility |
|:-:|:-:|:-:|
| **Apple Silicon** | [**⬇ FreeFlow-arm64.dmg**](https://github.com/zachlatta/freeflow/releases/latest/download/FreeFlow-arm64.dmg) | M1, M2, M3, M4, M5 Chips |
| **Universal** | [**⬇ FreeFlow-universal.dmg**](https://github.com/zachlatta/freeflow/releases/latest/download/FreeFlow-universal.dmg) | Intel & All Macs |

</div>

---

**Fast and accurate transcription** — powered by Groq's lightning-fast inference, your speech is transcribed in moments.

**Context-aware** — FreeFlow captures what's on your screen so it understands where you are. In a terminal, it formats commands correctly. In an email, it spells names and technical terms properly. The context around your cursor directly improves transcription quality.

**Private** — no cloud services besides the Groq API for transcription and LLM post-processing. Everything else runs locally on your Mac.

**Free** — most usage fits comfortably within Groq's free tier. No subscriptions, no usage fees. Just grab a free API key and go.

## Setup

1. Download the latest build: [Apple Silicon](https://github.com/zachlatta/freeflow/releases/latest/download/FreeFlow-arm64.dmg) · [Universal](https://github.com/zachlatta/freeflow/releases/latest/download/FreeFlow-universal.dmg) (or [build from source](#building-from-source))
2. Open the app and follow the setup wizard
3. Get a free API key from [console.groq.com/keys](https://console.groq.com/keys)
4. Grant the requested permissions (microphone, accessibility, screen recording)
5. Pick your push-to-talk key and start dictating

## Building from Source

```bash
git clone https://github.com/zachlatta/freeflow.git
cd freeflow
swift build
```

## License

MIT
