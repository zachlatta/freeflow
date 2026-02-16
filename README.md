<p align="center">
  <img src="Resources/AppIcon-README.png" width="128" height="128" alt="FreeFlow icon">
</p>

<h1 align="center">FreeFlow</h1>

<p align="center">
  Free and open source alternative to <a href="https://wisprflow.ai">Wispr Flow</a>, <a href="https://superwhisper.com">SuperWhisper</a>, and <a href="https://monologue.to">Monologue</a>.
</p>

<p align="center">
  <a href="https://github.com/zachlatta/freeflow/releases/latest/download/FreeFlow.dmg"><b>⬇ Download FreeFlow.dmg</b></a><br>
  <sub>Universal build — works on all Macs (Apple Silicon + Intel)</sub>
</p>

---

I vibe-coded this over the weekend because I didn't want to pay $10/month for voice-to-text. I was also annoyed with intrusive UI and frequent up-sells from other apps.

FreeFlow is a simple and free voice-to-text app that uses [Groq](https://groq.com/)'s free API. Push and hold the `Fn` key (customizable) to transcribe anywhere on your Mac.

**Features:**

- Fast and accurate transcription (uses `whisper-large-v3` + `meta-llama/llama-4-scout-17b-16e-instruct` for post-processing). Very, very fast.

- Context-aware post-processing. Ex. It'll detect if you're writing an email and correct spelling of names to how they're spelled on the rest of your screen.

- Define a custom vocabulary

- Free! Most usage will fit [Groq](https://groq.com/)'s free tier.

- Privacy friendly. Your Mac makes direct calls to Groq's API. FreeFlow doesn't have a server. No data is stored or retained because no server exists.

## License

Licensed under the MIT license.
