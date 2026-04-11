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

I like the concept of apps like [Wispr Flow](https://wisprflow.ai/), [Superwhisper](https://superwhisper.com/), and [Monologue](https://www.monologue.to/) that use AI to add accurate and easy-to-use transcription to your computer, but they all charge fees of ~$10/month when the underlying AI models are free to use or cost pennies.

So over the weekend I vibe-coded my own free version!

It's called FreeFlow. Here's how it works:

1. Download the app from above or [click here](https://github.com/zachlatta/freeflow/releases/latest/download/FreeFlow.dmg)
2. Get a free Groq API key from [groq.com](https://groq.com/)
3. Hold `Fn` to talk, or tap `Command-Fn` to start and stop dictation, and have whatever you say pasted into the current text field

You can also customize both shortcuts. If your toggle shortcut extends your hold shortcut, you can start in hold mode and press the extra modifier keys to latch into tap mode without stopping the recording.

One of the cool features is that it's context aware. If you're replying to an email, it'll read the names of the people you're replying to and make sure to spell their names correctly. Same with if you're dictating into a terminal or another app. This is the same thing as Monologue's "Deep Context" feature.

An added bonus is that there's no FreeFlow server, so no data is stored or retained - making it more privacy friendly than the SaaS apps. The only information that leaves your computer are the API calls to Groq's transcription and LLM API (LLM is for post-processing the transcription to adapt to context).

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

### FAQ

**Why does this use Groq instead of a local transcription model?**

I love this idea, and originally planned to build FreeFlow using local models, but to have post-processing (that's where you get correctly spelled names when replying to emails / etc), you need to have a local LLM too.

If you do that, the total pipeline takes too long for the UX to be good (5-10 seconds per transcription instead of <1s). I also had concerns around battery life.

Some day!

**Update:** You can now use a custom model with FreeFlow by configuring the LLM API URL in the FreeFlow settings to use Ollama. Thank you @taciturnaxolotl!

## License

Licensed under the MIT license.
