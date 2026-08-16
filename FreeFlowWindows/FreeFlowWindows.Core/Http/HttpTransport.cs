using System.Net;
using System.Net.Http.Headers;
using System.Text;

namespace FreeFlowWindows.Core.Http;

/// <summary>
/// HTTP transport wrapper providing configurable timeout and multipart form-data support.
/// Matches macOS LLMAPITransport patterns.
/// </summary>
public class HttpTransport : IDisposable
{
    private readonly HttpClient _httpClient;
    private readonly TimeSpan _timeout;
    private bool _disposed;

    /// <summary>
    /// Creates a new HTTP transport with the specified timeout.
    /// </summary>
    /// <param name="timeout">Request timeout. Defaults to 60 seconds.</param>
    public HttpTransport(TimeSpan? timeout = null)
    {
        _timeout = timeout ?? TimeSpan.FromSeconds(60);

        var handler = new HttpClientHandler
        {
            AutomaticDecompression = DecompressionMethods.GZip | DecompressionMethods.Deflate
        };

        _httpClient = new HttpClient(handler)
        {
            Timeout = _timeout
        };
    }

    /// <summary>
    /// Creates a new HTTP transport with timeout in seconds.
    /// </summary>
    /// <param name="timeoutSeconds">Request timeout in seconds.</param>
    public HttpTransport(double timeoutSeconds)
        : this(TimeSpan.FromSeconds(timeoutSeconds))
    {
    }

    /// <summary>
    /// Gets the configured timeout for this transport.
    /// </summary>
    public TimeSpan Timeout => _timeout;

    /// <summary>
    /// Sends a POST request with JSON content.
    /// </summary>
    /// <param name="url">The request URL.</param>
    /// <param name="jsonContent">The JSON content to send.</param>
    /// <param name="apiKey">The API key for authorization.</param>
    /// <param name="cancellationToken">Cancellation token.</param>
    /// <returns>The response body as a string, or an error.</returns>
    public async Task<HttpResult<string>> PostJsonAsync(
        string url,
        string jsonContent,
        string apiKey,
        CancellationToken cancellationToken = default)
    {
        try
        {
            using var request = new HttpRequestMessage(HttpMethod.Post, url);
            request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", apiKey);
            request.Content = new StringContent(jsonContent, Encoding.UTF8, "application/json");

            using var response = await _httpClient.SendAsync(request, cancellationToken);

            var responseBody = await response.Content.ReadAsStringAsync(cancellationToken);

            if (response.IsSuccessStatusCode)
            {
                return HttpResult<string>.Ok(responseBody);
            }

            var host = new Uri(url).Host;
            return HttpResult<string>.Fail(HttpError.FromStatusCode(
                (int)response.StatusCode,
                host,
                responseBody));
        }
        catch (TaskCanceledException ex) when (ex.InnerException is TimeoutException || !cancellationToken.IsCancellationRequested)
        {
            return HttpResult<string>.Fail(HttpError.TimeoutFailure(_timeout.TotalSeconds));
        }
        catch (HttpRequestException ex)
        {
            return HttpResult<string>.Fail(HttpError.NetworkFailure(
                ex.Message ?? "Network connection failed. Check your internet connection."));
        }
        catch (OperationCanceledException)
        {
            throw; // Re-throw user cancellation
        }
        catch (Exception ex)
        {
            return HttpResult<string>.Fail(HttpError.NetworkFailure(
                $"Request failed: {ex.Message}"));
        }
    }

    /// <summary>
    /// Uploads a file using multipart form-data.
    /// </summary>
    /// <param name="url">The request URL.</param>
    /// <param name="filePath">The path to the file to upload.</param>
    /// <param name="fileFieldName">The form field name for the file (default: "file").</param>
    /// <param name="additionalFields">Additional form fields to include.</param>
    /// <param name="apiKey">The API key for authorization.</param>
    /// <param name="cancellationToken">Cancellation token.</param>
    /// <returns>The response body as a string, or an error.</returns>
    public async Task<HttpResult<string>> UploadFileAsync(
        string url,
        string filePath,
        string fileFieldName,
        Dictionary<string, string>? additionalFields,
        string apiKey,
        CancellationToken cancellationToken = default)
    {
        try
        {
            using var content = BuildMultipartContent(filePath, fileFieldName, additionalFields);
            using var request = new HttpRequestMessage(HttpMethod.Post, url);
            request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", apiKey);
            request.Content = content;

            using var response = await _httpClient.SendAsync(request, cancellationToken);

            var responseBody = await response.Content.ReadAsStringAsync(cancellationToken);

            if (response.IsSuccessStatusCode)
            {
                return HttpResult<string>.Ok(responseBody);
            }

            var host = new Uri(url).Host;
            return HttpResult<string>.Fail(HttpError.FromStatusCode(
                (int)response.StatusCode,
                host,
                responseBody));
        }
        catch (TaskCanceledException ex) when (ex.InnerException is TimeoutException || !cancellationToken.IsCancellationRequested)
        {
            return HttpResult<string>.Fail(HttpError.TimeoutFailure(_timeout.TotalSeconds));
        }
        catch (HttpRequestException ex)
        {
            return HttpResult<string>.Fail(HttpError.NetworkFailure(
                ex.Message ?? "Network connection failed. Check your internet connection."));
        }
        catch (FileNotFoundException)
        {
            return HttpResult<string>.Fail(HttpError.NetworkFailure(
                $"Audio file not found: {filePath}"));
        }
        catch (OperationCanceledException)
        {
            throw; // Re-throw user cancellation
        }
        catch (Exception ex)
        {
            return HttpResult<string>.Fail(HttpError.NetworkFailure(
                $"Upload failed: {ex.Message}"));
        }
    }

    /// <summary>
    /// Uploads audio file data using multipart form-data.
    /// </summary>
    /// <param name="url">The request URL.</param>
    /// <param name="audioData">The audio file data.</param>
    /// <param name="fileName">The filename to use in the upload.</param>
    /// <param name="contentType">The content type of the audio (default: audio/wav).</param>
    /// <param name="fileFieldName">The form field name for the file (default: "file").</param>
    /// <param name="additionalFields">Additional form fields to include.</param>
    /// <param name="apiKey">The API key for authorization.</param>
    /// <param name="cancellationToken">Cancellation token.</param>
    /// <returns>The response body as a string, or an error.</returns>
    public async Task<HttpResult<string>> UploadAudioDataAsync(
        string url,
        byte[] audioData,
        string fileName,
        string contentType,
        string fileFieldName,
        Dictionary<string, string>? additionalFields,
        string apiKey,
        CancellationToken cancellationToken = default)
    {
        try
        {
            using var content = BuildMultipartContentFromData(audioData, fileName, contentType, fileFieldName, additionalFields);
            using var request = new HttpRequestMessage(HttpMethod.Post, url);
            request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", apiKey);
            request.Content = content;

            using var response = await _httpClient.SendAsync(request, cancellationToken);

            var responseBody = await response.Content.ReadAsStringAsync(cancellationToken);

            if (response.IsSuccessStatusCode)
            {
                return HttpResult<string>.Ok(responseBody);
            }

            var host = new Uri(url).Host;
            return HttpResult<string>.Fail(HttpError.FromStatusCode(
                (int)response.StatusCode,
                host,
                responseBody));
        }
        catch (TaskCanceledException ex) when (ex.InnerException is TimeoutException || !cancellationToken.IsCancellationRequested)
        {
            return HttpResult<string>.Fail(HttpError.TimeoutFailure(_timeout.TotalSeconds));
        }
        catch (HttpRequestException ex)
        {
            return HttpResult<string>.Fail(HttpError.NetworkFailure(
                ex.Message ?? "Network connection failed. Check your internet connection."));
        }
        catch (OperationCanceledException)
        {
            throw; // Re-throw user cancellation
        }
        catch (Exception ex)
        {
            return HttpResult<string>.Fail(HttpError.NetworkFailure(
                $"Upload failed: {ex.Message}"));
        }
    }

    /// <summary>
    /// Builds multipart form-data content from a file path.
    /// </summary>
    private static MultipartFormDataContent BuildMultipartContent(
        string filePath,
        string fileFieldName,
        Dictionary<string, string>? additionalFields)
    {
        var content = new MultipartFormDataContent();

        // Add additional form fields first
        if (additionalFields != null)
        {
            foreach (var field in additionalFields)
            {
                content.Add(new StringContent(field.Value), field.Key);
            }
        }

        // Add the file
        var fileContent = new ByteArrayContent(File.ReadAllBytes(filePath));
        var fileName = Path.GetFileName(filePath);
        var mimeType = GetMimeType(filePath);
        fileContent.Headers.ContentType = new MediaTypeHeaderValue(mimeType);
        content.Add(fileContent, fileFieldName, fileName);

        return content;
    }

    /// <summary>
    /// Builds multipart form-data content from byte array data.
    /// </summary>
    private static MultipartFormDataContent BuildMultipartContentFromData(
        byte[] data,
        string fileName,
        string contentType,
        string fileFieldName,
        Dictionary<string, string>? additionalFields)
    {
        var content = new MultipartFormDataContent();

        // Add additional form fields first
        if (additionalFields != null)
        {
            foreach (var field in additionalFields)
            {
                content.Add(new StringContent(field.Value), field.Key);
            }
        }

        // Add the file data
        var fileContent = new ByteArrayContent(data);
        fileContent.Headers.ContentType = new MediaTypeHeaderValue(contentType);
        content.Add(fileContent, fileFieldName, fileName);

        return content;
    }

    /// <summary>
    /// Gets the MIME type for a file based on its extension.
    /// </summary>
    private static string GetMimeType(string filePath)
    {
        var extension = Path.GetExtension(filePath).ToLowerInvariant();
        return extension switch
        {
            ".wav" => "audio/wav",
            ".mp3" => "audio/mpeg",
            ".m4a" => "audio/mp4",
            ".webm" => "audio/webm",
            ".ogg" => "audio/ogg",
            ".flac" => "audio/flac",
            _ => "application/octet-stream"
        };
    }

    /// <summary>
    /// Maps an HTTP status code to a user-friendly error message.
    /// Ports the macOS friendlyHTTPMessage function.
    /// </summary>
    /// <param name="statusCode">The HTTP status code.</param>
    /// <param name="host">The API host name (optional).</param>
    /// <returns>A user-friendly error message.</returns>
    public static string FriendlyHttpMessage(int statusCode, string? host)
    {
        var provider = host ?? "the provider";

        return statusCode switch
        {
            401 => $"Invalid API key for {provider}. Open Settings to fix it.",
            403 => $"Key lacks permission for this endpoint at {provider} (HTTP 403). Check the key's scopes.",
            404 => $"Endpoint not found at {provider} (HTTP 404). Base URL is likely wrong for this provider.",
            413 => $"Audio file too large for {provider} (HTTP 413). Try a shorter recording.",
            400 => "Provider rejected the request (HTTP 400). Check your model name and Base URL in Settings.",
            429 => $"Rate limit reached at {provider} (HTTP 429). Wait a moment and try again.",
            >= 500 and < 600 => $"Provider error at {provider} (HTTP {statusCode}). Try again in a moment.",
            _ => $"Request failed at {provider} (HTTP {statusCode})."
        };
    }

    /// <summary>
    /// Disposes the HTTP client.
    /// </summary>
    public void Dispose()
    {
        if (!_disposed)
        {
            _httpClient.Dispose();
            _disposed = true;
        }
        GC.SuppressFinalize(this);
    }
}
