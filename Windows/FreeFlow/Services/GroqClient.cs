using System;
using System.IO;
using System.Net.Http;
using System.Net.Http.Headers;
using System.Text;
using System.Threading.Tasks;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;

namespace FreeFlow.Services;

public class GroqClient
{
    private readonly string _apiKey;
    private readonly HttpClient _httpClient;
    private const string BaseUrl = "https://api.groq.com/openai/v1";

    public GroqClient(string apiKey)
    {
        _apiKey = apiKey;
        _httpClient = new HttpClient();
        _httpClient.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", _apiKey);
    }

    public async Task<string> TranscribeAsync(string filePath)
    {
        using var content = new MultipartFormDataContent();
        var fileContent = new ByteArrayContent(await File.ReadAllBytesAsync(filePath));
        fileContent.Headers.ContentType = MediaTypeHeaderValue.Parse("audio/wav");
        content.Add(fileContent, "file", Path.GetFileName(filePath));
        content.Add(new StringContent("whisper-large-v3"), "model");

        var response = await _httpClient.PostAsync($"{BaseUrl}/audio/transcriptions", content);
        response.EnsureSuccessStatusCode();

        var json = await response.Content.ReadAsStringAsync();
        var result = JsonConvert.DeserializeObject<JObject>(json);
        return result?["text"]?.ToString() ?? "";
    }

    public async Task<string> PostProcessAsync(string transcript, string contextSummary, string? screenshotBase64 = null, string customVocabulary = "")
    {
        var model = "llama-3.2-11b-vision-preview";

        var vocabularyPrompt = !string.IsNullOrEmpty(customVocabulary) ? $"\n\nThe following vocabulary must be treated as high-priority terms while rewriting. Use these spellings exactly in the output when relevant:\n{customVocabulary}" : "";

        var systemPrompt = $@"You are a dictation post-processor. You receive raw speech-to-text output and return clean text ready to be typed into an application.

Your job:
- Remove filler words (um, uh, you know, like) unless they carry meaning.
- Fix spelling, grammar, and punctuation errors.
- When the transcript already contains a word that is a close misspelling of a name or term from the context or custom vocabulary, correct the spelling. Never insert names or terms from context that the speaker did not say.
- Preserve the speaker's intent, tone, and meaning exactly.

Output rules:
- Return ONLY the cleaned transcript text, nothing else.
- If the transcription is empty, return exactly: EMPTY
- Do not add words, names, or content that are not in the transcription. The context is only for correcting spelling of words already spoken.
- Do not change the meaning of what was said.{vocabularyPrompt}";

        var userMessageContent = new JArray();
        userMessageContent.Add(new JObject
        {
            ["type"] = "text",
            ["text"] = $"Instructions: Clean up this RAW_TRANSCRIPTION. Return EMPTY if there should be no result.\n\nCONTEXT: \"{contextSummary}\"\n\nRAW_TRANSCRIPTION: \"{transcript}\""
        });

        if (!string.IsNullOrEmpty(screenshotBase64))
        {
            userMessageContent.Add(new JObject
            {
                ["type"] = "image_url",
                ["image_url"] = new JObject
                {
                    ["url"] = $"data:image/jpeg;base64,{screenshotBase64}"
                }
            });
        }

        var payload = new JObject
        {
            ["model"] = model,
            ["temperature"] = 0.0,
            ["messages"] = new JArray
            {
                new JObject { ["role"] = "system", ["content"] = systemPrompt },
                new JObject { ["role"] = "user", ["content"] = userMessageContent }
            }
        };

        var content = new StringContent(payload.ToString(), Encoding.UTF8, "application/json");
        var response = await _httpClient.PostAsync($"{BaseUrl}/chat/completions", content);

        if (!response.IsSuccessStatusCode)
        {
             // Fallback if vision model fails or is unavailable
             return transcript;
        }

        var json = await response.Content.ReadAsStringAsync();
        var result = JsonConvert.DeserializeObject<JObject>(json);
        var cleaned = result?["choices"]?[0]?["message"]?["content"]?.ToString()?.Trim() ?? "";

        if (cleaned == "EMPTY") return "";

        // Strip quotes if LLM added them
        if (cleaned.StartsWith("\"") && cleaned.EndsWith("\"") && cleaned.Length > 1)
        {
            cleaned = cleaned.Substring(1, cleaned.Length - 2).Trim();
        }

        return cleaned;
    }
}
