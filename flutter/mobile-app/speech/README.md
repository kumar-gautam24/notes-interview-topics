# Sarvam AI POC - Speech Services

This directory contains Proof of Concept (POC) implementations for Sarvam AI's speech services.

## Overview

**Goal**: Compare Sarvam AI's Indian language-optimized STT/TTS with native Flutter implementations.

### Services Included

1. **SarvamSTTPocService** - Saarika v2.5 Speech-to-Text
   - WebSocket-based real-time transcription
   - Auto-detects Hindi, English, and Hinglish (code-mixed)
   - Supports Voice Activity Detection (VAD)
   - Optimized for Indian accents and medical terminology

2. **SarvamTTSPocService** - Bulbul v3 Text-to-Speech
   - REST API-based audio synthesis
   - 30+ natural voices for Indian languages
   - Pace control (0.5x - 2.0x)
   - Up to 2500 characters per request

## Setup

### 1. Environment Variables

Already configured in `env.dev`:
```
SARVAM_API_KEY=[REDACTED-SARVAM-API-KEY]
SARVAM_STT_WS_URL=wss://api.sarvam.ai/speech-to-text/ws
SARVAM_TTS_URL=https://api.sarvam.ai/text-to-speech
```

### 2. Dependencies

Added to `pubspec.yaml`:
- `web_socket_channel: ^3.0.1` (for STT WebSocket)
- `audioplayers: ^6.1.0` (for TTS audio playback)
- `record: ^6.1.2` (for audio recording)
- `flutter_dotenv: ^6.0.0` (for env variables)

## Testing the POC

### Access the Test Screen

1. Navigate to the "Consult Doctor" screen (Bottom Sheet Test Screen)
2. Tap the **"🎤 Sarvam AI POC"** button at the top
3. A bottom sheet will open with side-by-side comparisons

### Speech-to-Text Testing

**Test Scenarios:**
```
1. English: "How can I control my cholesterol levels?"
2. Hindi: "मुझे diabetes है, कौन सी medicine लूं?"
3. Hinglish: "मेरा BP high है, kya karu?"
4. Medical Terms: "I have hypertension and need medication"
```

**Metrics to Compare:**
- ✅ Accuracy (especially for medical terms)
- ✅ Latency (time from stop to result)
- ✅ Code-mixing handling (Hinglish)
- ✅ Indian accent recognition

### Text-to-Speech Testing

**Test with the default text:**
```
"मुझे diabetes है, कौन सी medicine लूं? How can I control cholesterol?"
```

**Compare:**
- ✅ Voice naturalness
- ✅ Pronunciation of medical terms
- ✅ Code-mixed text handling
- ✅ Latency (time to first audio)

## Key Features

### Sarvam STT (Saarika v2.5)

**Advantages over Native:**
1. **Indian Language Optimization**
   - Native code-mixing support (no manual language switching)
   - Better accuracy for Indian accents
   - Medical terminology preservation

2. **Smart Features**
   - Automatic language detection
   - Voice Activity Detection (speech start/end events)
   - Flush signals for immediate results

3. **Benchmarks** ([Sarvam Docs](https://docs.sarvam.ai))
   - English WER: 8.26% (vs ~15-20% native)
   - Hindi WER: 11.81%
   - Supports 11 Indian languages

### Sarvam TTS (Bulbul v3)

**Features:**
- 30+ voices (male/female)
- Natural prosody
- Pace control
- High-quality audio output

**Tradeoffs:**
- REST API (not streaming) → Higher latency
- Network dependency
- API costs

## Technical Implementation

### STT (SarvamSTTPocService)

```dart
// Initialize
final sttService = SarvamSTTPocService();
await sttService.initialize();

// Start listening
await sttService.startListening();

// Listen to transcription stream
sttService.transcriptionStream.listen((text) {
  print('Transcription: $text');
});

// Stop and get result
final result = await sttService.stopListening();
```

**WebSocket Flow:**
1. Connect with query params (language, model, VAD settings)
2. Stream audio chunks (PCM 16-bit, 16kHz)
3. Receive real-time transcription events
4. Send flush signal for immediate results

### TTS (SarvamTTSPocService)

```dart
// Initialize
final ttsService = SarvamTTSPocService();
await ttsService.initialize();

// Speak text
await ttsService.speak(
  'मुझे diabetes है',
  languageCode: 'hi-IN',
  speaker: 'meera',
  pace: 1.0,
);

// Stop
await ttsService.stop();
```

**API Flow:**
1. POST to `/text-to-speech` with text and params
2. Receive base64-encoded audio
3. Decode and play via audioplayers

## Comparison with Native

### Native STT (speech_to_text: ^7.0.0)

**Pros:**
- Free (device-native)
- Works offline
- No API dependency

**Cons:**
- Lower accuracy for Indian accents
- No code-mixing support
- Platform-specific issues (Android 3-5s auto-stop)

### Native TTS (flutter_tts: ^4.2.0)

**Pros:**
- Free (device-native)
- Instant playback (no network latency)
- Works offline

**Cons:**
- Robotic voice quality
- Poor handling of code-mixed text
- Limited voice options

## Next Steps

### If POC is Successful (>90% accuracy):

1. **Create Abstraction Layer**
   - `SpeechProvider` interface
   - Refactor existing services to use provider pattern

2. **Implement Production Integration**
   - `SarvamSpeechProvider` (production-ready)
   - `HybridSpeechProvider` (automatic fallback)

3. **Testing & Rollout**
   - Feature flag for gradual rollout
   - A/B testing with real users
   - Cost monitoring dashboard

4. **Decision Point for TTS**
   - Based on user feedback
   - If streaming API becomes available
   - Cost vs quality tradeoff analysis

## Cost Analysis

### Estimated Costs (10K MAU)

**Assumptions:**
- 5 voice messages per user per month
- 30 seconds average duration
- Total: 50,000 messages = 25,000 minutes/month

**STT (Saarika):**
- Est: ₹0.30/minute
- Monthly: ₹7,500 (~$90)

**TTS (Bulbul):** (If used)
- Est: ₹0.05/1000 chars
- Monthly: ₹2,000-5,000 (~$25-60)

**Total: ~$100-150/month** for 10K users

## Documentation

- [Sarvam Saarika Docs](https://docs.sarvam.ai/api-reference-docs/getting-started/models/saarika)
- [Sarvam Streaming API](https://docs.sarvam.ai/api-reference-docs/api-guides-tutorials/speech-to-text/streaming-api)
- [Sarvam Bulbul Docs](https://docs.sarvam.ai/api-reference-docs/getting-started/models/bulbul)

## Troubleshooting

### STT Issues

**Problem: No transcription received**
- Check API key in `env.dev`
- Verify WebSocket connection in logs
- Ensure microphone permission granted

**Problem: Poor accuracy**
- Test with clear audio (quiet environment)
- Speak at normal pace
- Try different test phrases

### TTS Issues

**Problem: Audio not playing**
- Check API key
- Verify network connectivity
- Check audio player initialization

**Problem: High latency**
- This is expected (REST API, not streaming)
- Consider keeping native TTS for instant playback

## Files Modified

1. `env.dev` - Added Sarvam API credentials
2. `pubspec.yaml` - Added audioplayers dependency
3. `lib/core/services/speech/poc/` - New POC services
4. `lib/features/presentation/widgets/common/bottom_sheets/sarvam_poc_bottom_sheet.dart` - Test UI
5. `lib/features/presentation/bottom_sheet_test/bottom_sheet_test_screen.dart` - Added test button

## Contact

For questions or issues with the POC:
- Review logs with tag `[Sarvam STT POC]` or `[Sarvam TTS POC]`
- Check network requests in Dio logs
- Verify API key validity with Sarvam support
