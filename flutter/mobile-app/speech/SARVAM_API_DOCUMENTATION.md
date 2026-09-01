# Sarvam AI API - Official Documentation & Guidelines

## Overview

Sarvam AI provides Speech-to-Text (STT) and Text-to-Speech (TTS) APIs optimized for Indian languages and code-mixed speech (Hinglish, Tanglish, etc.).

**Official Website:** https://www.sarvam.ai/  
**API Base URL:** `https://api.sarvam.ai`  
**Authentication:** API Key via `api-subscription-key` header

---

## 1. Speech-to-Text (Saarika v2.5)

### Overview

**Saarika** is Sarvam's STT model optimized for:
- Indian accents
- Code-mixed speech (Hindi+English, Tamil+English, etc.)
- Real-time streaming via WebSocket
- High accuracy for regional languages

### WebSocket Streaming API

**Endpoint:** `wss://api.sarvam.ai/speech-to-text/ws`

**Connection:**
```
WebSocket URL: wss://api.sarvam.ai/speech-to-text/ws?<query_params>
Headers:
  api-subscription-key: <your_api_key>
```

**Query Parameters:**

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `language-code` | string | No | `unknown` | Language code (hi-IN, en-IN, ta-IN, etc.). Use `unknown` for auto-detection |
| `model` | string | Yes | - | Model name: `saarika:v2.5` |
| `high_vad_sensitivity` | boolean | No | `false` | Enable high Voice Activity Detection sensitivity |
| `vad_signals` | boolean | No | `false` | Receive VAD event signals (speech started/ended) |
| `flush_signal` | boolean | No | `false` | Enable flush signal support for forcing transcription |
| `sample_rate` | integer | Yes | - | Audio sample rate in Hz (16000 recommended) |
| `input_audio_codec` | string | Yes | - | Audio codec: `wav`, `opus`, `pcm16bits` |

**Example Connection URL:**
```
wss://api.sarvam.ai/speech-to-text/ws?language-code=unknown&model=saarika:v2.5&high_vad_sensitivity=true&vad_signals=true&flush_signal=true&sample_rate=16000&input_audio_codec=wav
```

### Audio Streaming Format

**Send audio chunks:**
```json
{
  "audio": {
    "content": "<base64_encoded_audio_bytes>"
  }
}
```

**CRITICAL:** Audio must be wrapped in `{"audio": {"content": "..."}}` format, NOT just `{"audio": "..."}`.

**Audio Requirements:**
- Format: PCM 16-bit, mono channel
- Sample rate: 16000 Hz
- Encoding: Base64
- Chunk size: Small chunks (100-500ms) for real-time

### Flush Signal

Force transcription of buffered audio:
```json
{
  "flush": true
}
```

**Use cases:**
- User stops speaking (end of utterance)
- Need immediate transcription
- Session ending

### Response Format

**Data Message (Transcription):**
```json
{
  "type": "data",
  "data": {
    "transcript": "मुझे diabetes है, how can I control it?"
  }
}
```

**Events (VAD Signals):**
```json
{
  "type": "events",
  "data": {
    "speech_started": true
  }
}
```

```json
{
  "type": "events",
  "data": {
    "speech_ended": true
  }
}
```

**Error Message:**
```json
{
  "type": "error",
  "data": {
    "message": "Error description",
    "error": "error_code"
  }
}
```

### Best Practices

1. **Connection Lifecycle:**
   - Open WebSocket per session
   - Keep connection alive during recording
   - Close gracefully with flush signal
   - Reconnect on connection loss

2. **Audio Streaming:**
   - Stream in real-time (don't buffer entire audio)
   - Use small chunks (100-500ms)
   - Maintain consistent sample rate
   - Monitor buffer size

3. **Error Handling:**
   - Handle connection errors (network loss)
   - Retry with exponential backoff
   - Fall back to alternative provider
   - Monitor `onDone` and `onError` callbacks

4. **Performance:**
   - Use `high_vad_sensitivity` for better speech detection
   - Enable `vad_signals` to know when user speaks
   - Send flush signal to get immediate results
   - Use `language-code=unknown` for auto-detection

---

## 2. Text-to-Speech (Bulbul v3)

### Overview

**Bulbul** is Sarvam's TTS model with:
- Natural-sounding Indian voices
- Code-mixed speech support
- Multiple speaker voices
- Adjustable speech pace

### REST API

**Endpoint:** `POST https://api.sarvam.ai/text-to-speech`

**Headers:**
```
api-subscription-key: <your_api_key>
Content-Type: application/json
```

**Request Body:**
```json
{
  "text": "मुझे fever है, kya medicine लूं?",
  "target_language_code": "hi-IN",
  "model": "bulbul:v3",
  "speaker": "priya",
  "pace": 1.0
}
```

**Parameters:**

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `text` | string | Yes | - | Text to convert to speech |
| `target_language_code` | string | Yes | - | Language code (hi-IN, en-IN, ta-IN, etc.) |
| `model` | string | Yes | - | Model name: `bulbul:v3` |
| `speaker` | string | No | `priya` | Voice name (see available speakers below) |
| `pace` | float | No | `1.0` | Speech speed (0.5 to 2.0) |

**Available Speakers (Bulbul v3):**

| Speaker | Gender | Language | Description |
|---------|--------|----------|-------------|
| `priya` | Female | Hindi/English | Natural, friendly tone |
| `aarav` | Male | Hindi/English | Professional, clear |
| `meera` | Female | Hindi/English | Warm, conversational |
| `arjun` | Male | Hindi/English | Energetic, dynamic |

**IMPORTANT:** Speaker names are **case-sensitive** and must be lowercase.

### Response Format

**Success (200 OK):**
```json
{
  "audios": [
    "<base64_encoded_audio_data>"
  ]
}
```

**Audio Format:**
- Encoding: Base64
- Format: Linear PCM or MP3 (depends on API)
- Sample rate: 22050 Hz or 16000 Hz
- Channels: Mono

**Error Response (4xx/5xx):**
```json
{
  "error": "Error description",
  "message": "Detailed error message"
}
```

### Usage Example

**1. Make API Request:**
```dart
final response = await dio.post(
  '/text-to-speech',
  data: {
    'text': 'Hello, how are you?',
    'target_language_code': 'hi-IN',
    'model': 'bulbul:v3',
    'speaker': 'priya',
    'pace': 1.0,
  },
  options: Options(
    headers: {
      'api-subscription-key': apiKey,
      'Content-Type': 'application/json',
    },
  ),
);
```

**2. Extract Audio:**
```dart
final responseData = response.data as Map<String, dynamic>;
final audios = responseData['audios'] as List<dynamic>;
final base64Audio = audios[0] as String;
final audioBytes = base64Decode(base64Audio);
```

**3. Play Audio:**
```dart
await audioPlayer.play(BytesSource(audioBytes));
```

### Best Practices

1. **Text Processing:**
   - Limit text length (API may have limits)
   - Break long text into sentences
   - Handle special characters properly
   - Test with code-mixed content

2. **Caching:**
   - Cache generated audio for reuse
   - Use messageId as cache key
   - Clear cache periodically
   - Consider storage limits

3. **Error Handling:**
   - Handle network timeouts (30s recommended)
   - Fall back to native TTS on failure
   - Retry with exponential backoff
   - Validate response format

4. **Performance:**
   - Show loading indicator during API call
   - Preload audio for frequently used phrases
   - Use appropriate pace for readability
   - Monitor API rate limits

---

## 3. Authentication

**API Key Management:**

1. Get API key from Sarvam AI dashboard
2. Store in environment variables (`.env` files)
3. Never commit API keys to version control
4. Rotate keys periodically

**Environment Variables:**
```env
SARVAM_API_KEY=sk_xxxxxxxx_xxxxxxxxxxxxxxxx
SARVAM_STT_WS_URL=wss://api.sarvam.ai/speech-to-text/ws
SARVAM_TTS_URL=https://api.sarvam.ai
```

**Header Format:**
```
api-subscription-key: sk_xxxxxxxx_xxxxxxxxxxxxxxxx
```

---

## 4. Error Handling

### Common Errors

| Status Code | Error | Cause | Solution |
|-------------|-------|-------|----------|
| 400 | Bad Request | Invalid parameters | Check payload format |
| 401 | Unauthorized | Invalid API key | Verify key is correct |
| 403 | Forbidden | Quota exceeded | Check billing/limits |
| 404 | Not Found | Wrong endpoint | Verify URL |
| 429 | Too Many Requests | Rate limit | Implement backoff |
| 500 | Internal Server Error | Server issue | Retry after delay |
| 503 | Service Unavailable | Maintenance | Retry later |

### STT-Specific Errors

```json
{
  "type": "error",
  "data": {
    "message": "Error in Pipeline: validation error",
    "error": "validation_error"
  }
}
```

**Common causes:**
- Wrong audio format
- Invalid sample rate
- Missing required parameters
- Corrupted audio data

### TTS-Specific Errors

```json
{
  "error": "Invalid speaker name",
  "message": "Speaker 'Priya' not found. Use lowercase: 'priya'"
}
```

**Common causes:**
- Case-sensitive speaker name
- Invalid language code
- Text too long
- Unsupported characters

---

## 5. Rate Limits & Quotas

**Typical Limits (verify with Sarvam):**
- STT: X minutes per month
- TTS: Y characters per month
- Concurrent connections: Z per API key
- Rate: N requests per minute

**Monitoring:**
- Track usage via dashboard
- Set up billing alerts
- Log API call counts
- Monitor error rates

---

## 6. Pricing

**Pricing Model (as of 2026 - verify current):**
- **STT:** Per minute of audio processed
- **TTS:** Per character converted
- **Free tier:** Limited usage for testing
- **Paid plans:** Based on volume

**Cost Optimization:**
- Cache TTS audio for reuse
- Use VAD to reduce STT processing
- Implement fallback to reduce API calls
- Monitor and optimize usage

---

## 7. Supported Languages

### Full Support:
- Hindi (hi-IN)
- English (en-IN)
- Tamil (ta-IN)
- Telugu (te-IN)
- Kannada (kn-IN)
- Malayalam (ml-IN)
- Bengali (bn-IN)
- Marathi (mr-IN)
- Gujarati (gu-IN)

### Code-Mixed:
- Hinglish (Hindi + English)
- Tanglish (Tamil + English)
- And other combinations

---

## 8. SDK & Tools

**Official Resources:**
- API Documentation: https://docs.sarvam.ai
- Dashboard: https://dashboard.sarvam.ai
- Support: support@sarvam.ai
- Status Page: https://status.sarvam.ai

**Community:**
- GitHub: (if available)
- Discord: (if available)
- Forum: (if available)

---

## 9. Migration Guide (v2 → v2.5)

**Saarika v2.5 Changes:**
- Improved accuracy for code-mixed speech
- Better VAD sensitivity
- Faster response time
- Enhanced error messages

**Breaking Changes:**
- Audio format now requires `{"audio": {"content": "..."}}` wrapper
- Some query parameters renamed
- Response format unchanged

**Migration Steps:**
1. Update model parameter to `saarika:v2.5`
2. Fix audio payload format
3. Test with code-mixed content
4. Monitor error logs

---

## 10. Testing & Debugging

**Testing Tips:**
1. Use POC implementation first
2. Test with short audio clips
3. Verify API key is valid
4. Check network connectivity
5. Monitor WebSocket lifecycle
6. Test fallback scenarios

**Debug Logging:**
```dart
if (kDebugMode) {
  AppLogger.d('Request: $url', tag: 'Sarvam');
  AppLogger.d('Payload: $data', tag: 'Sarvam');
  AppLogger.d('Response: $response', tag: 'Sarvam');
}
```

**Common Issues:**
- WebSocket closes immediately → Check API key
- Validation errors → Check audio format
- No transcription → Check sample rate
- TTS fails → Check speaker name case

---

## 11. Production Checklist

- [ ] API keys stored in environment variables
- [ ] Error handling implemented
- [ ] Fallback mechanism in place
- [ ] Logging enabled in debug, disabled in release
- [ ] Rate limiting implemented
- [ ] Usage monitoring set up
- [ ] Billing alerts configured
- [ ] Network timeout handling
- [ ] Connection retry logic
- [ ] Audio format validated
- [ ] Testing completed
- [ ] Documentation updated

---

**Last Updated:** February 10, 2026  
**API Version:** Saarika v2.5, Bulbul v3  
**Documentation Status:** Based on implementation and testing
