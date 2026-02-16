<p align="center">
  <img src="Resources/AppIcon-README.png" width="128" height="128" alt="FreeFlow icon">
</p>

<h1 align="center">FreeFlow</h1>

<p align="center">
  Free and open source alternative to <a href="https://wisprflow.ai">Wispr Flow</a>, <a href="https://superwhisper.com">SuperWhisper</a>, and <a href="https://monologue.to">Monologue</a>.
</p>

<p align="center">
  <a href="https://github.com/zachlatta/freeflow/releases/latest/download/FreeFlow.dmg"><b>⬇ Download FreeFlow.dmg</b></a><br>
  <sub>Works on all Macs (Apple Silicon + Intel)</sub>
</p>

---

<p align="center">
  <img src="Resources/demo.gif" alt="FreeFlow demo" width="600">
</p>

I like the concept of apps like [Wispr Flow](https://wisprflow.ai/), [Superwhisper](https://superwhisper.com/), and [Monologue](https://www.monologue.to/) that use AI to add accurate and easy-to-use transcription to your computer, but they all charge fees of ~$10/month when the underlying AI models are free to use or cost pennies.

So over the weekend I vibe-coded my own free version!

It's called FreeFlow. Here's how it works:

1. Download the app from above or [click here](https://github.com/zachlatta/freeflow/releases/latest/download/FreeFlow.dmg)
2. Get a free Groq API key from [groq.com](https://groq.com/)
3. Press and hold `Fn` anytime to start recording and have whatever you say pasted into the current text field

One of the cool features is that it's context aware. If you're replying to an email, it'll read the names of the people you're replying to and make sure to spell their names correctly. Same with if you're dictating into a terminal or another app. This is the same thing as Monologue's "Deep Context" feature.

An added bonus is that there's no FreeFlow server, so no data is stored or retained - making it more privacy friendly than the SaaS apps. The only information that leaves your computer are the API calls to Groq's transcription and LLM API (LLM is for post-processing the transcription to adapt to context).

## License

Licensed under the MIT license.
