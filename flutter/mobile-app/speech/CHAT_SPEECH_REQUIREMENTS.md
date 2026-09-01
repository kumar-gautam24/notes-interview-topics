# Chat Speech Requirements - <AppName> Mobile

## Overview

Speech functionality integrated into the chat interface for seamless voice interaction with the AI doctor.

**Platforms:** Android & iOS  
**Features:** Speech-to-Text (STT) for input, Text-to-Speech (TTS) for responses  
**Provider:** Sarvam AI (Primary) + Native (Fallback)

---

## 1. Speech-to-Text (STT) in Chat

### Location
- **Bottom Input Bar** (`lib/features/presentation/chat/widgets/input/bottom_input_bar.dart`)
- Mic button next to text input field
- Alternative to typing messages

### User Flow

```
User Action Flow:
══════════════════

1. User taps mic button
2. Permission check (if not granted, request)
3. Show recording UI (visual feedback)
4. User speaks their question/message
5. Real-time transcription displayed
6. Transcript accumulated across speech segments
7. User taps send/done
8. Accumulated text sent to chat socket
9. Message appears in chat
```

### Requirements

#### Functional Requirements

1. **Mic Button Integration**
   - Located in bottom input bar
   - Icon changes based on state (idle/recording/processing)
   - Tap to start, tap again to stop
   - OR hold-to-speak pattern (TBD by UX)

2. **Permission Handling**
   ```dart
   // Check before recording
   final hasPermission = await _speechService.hasPermission();
   if (!hasPermission) {
     final granted = await _speechService.requestPermission();
     if (!granted) {
       // Show error message
       return;
     }
   }
   ```

3. **Real-time Transcription**
   - Display transcript as user speaks
   - Update text field with live transcription
   - Visual indicator that mic is active
   - Cancel option available

4. **Transcript Accumulation**
   ```
   KEY REQUIREMENT: Accumulate transcript across speech segments
   
   Scenario:
   - User speaks: "मुझे diabetes है"
   - API returns: "मुझे diabetes है"
   - User continues: "कौन सी medicine लूं"
   - API returns: "कौन सी medicine लूं"
   - ACCUMULATED TRANSCRIPT: "मुझे diabetes है कौन सी medicine लूं"
   ```

5. **Send to Socket**
   - Accumulated text sent as complete message
   - Not individual speech segments
   - Integrated with existing chat flow
   - Same as if user typed the message

#### Technical Implementation

```dart
class _BottomInputBarState extends State<BottomInputBar> {
  final TextEditingController _controller = TextEditingController();
  late SpeechService _speechService;
  bool _isListening = false;
  
  @override
  void initState() {
    super.initState();
    _speechService = sl<SpeechService>();
    
    // Listen to transcription stream
    _speechService.transcriptionStream.listen((transcript) {
      // Update text field in real-time
      _controller.text = transcript;
    });
    
    _speechService.isListeningStream.listen((isListening) {
      setState(() => _isListening = isListening);
    });
    
    _speechService.errorStream.listen((error) {
      if (error != null) {
        // Show error to user
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error)),
        );
      }
    });
  }
  
  Future<void> _handleMicTap() async {
    if (_isListening) {
      // Stop recording and get final transcript
      final finalText = await _speechService.stopListening();
      _controller.text = finalText;
    } else {
      // Check permission
      final hasPermission = await _speechService.hasPermission();
      if (!hasPermission) {
        final granted = await _speechService.requestPermission();
        if (!granted) return;
      }
      
      // Start listening
      final success = await _speechService.startListening();
      if (!success) {
        // Handle error
      }
    }
  }
  
  void _handleSend() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    
    // Send to chat socket (existing flow)
    widget.onSendMessage(text);
    
    // Clear input
    _controller.clear();
  }
}
```

#### UI States

| State | Mic Icon | Visual Feedback | Action |
|-------|----------|-----------------|--------|
| Idle | 🎤 Static | None | Tap to start |
| Recording | 🔴 Pulsing | Red dot, waveform | Tap to stop |
| Processing | ⏳ Loading | Spinner | Wait |
| Error | ⚠️ Alert | Error message | Tap to retry |

#### Error Handling

1. **No Permission:** Show permission dialog
2. **No Network (Sarvam fails):** Fall back to native STT
3. **Microphone Busy:** Show "Mic in use" message
4. **No Speech Detected:** Show "No speech detected, try again"
5. **Service Error:** Show generic error, allow retry

---

## 2. Text-to-Speech (TTS) in Chat

### Location
- **Chat Screen** (`lib/features/presentation/chat/screens/chat_screen.dart`)
- Speaker icon on each AI message bubble
- Read aloud AI doctor responses

### User Flow

```
User Action Flow:
══════════════════

1. User receives AI response in chat
2. Speaker icon visible on message
3. User taps speaker icon
4. Loading indicator shown
5. TTS API called (with message text)
6. Audio downloaded and cached
7. Audio plays immediately
8. Speaker icon shows playing state
9. User can tap again to stop
10. Cache reused if same message tapped again
```

### Requirements

#### Functional Requirements

1. **Speaker Button Per Message**
   - Each AI message has a speaker icon
   - Located in message action bar
   - Only on AI responses (not user messages)
   - Only on complete messages (not streaming)

2. **Loading State**
   ```dart
   // Show loading while fetching audio
   if (_ttsService.isSpeaking && 
       _ttsService.currentMessageId == messageId) {
     // Show playing icon
     return Icon(Icons.volume_up, color: Colors.blue);
   } else if (_isLoadingAudio) {
     // Show loading
     return CircularProgressIndicator(size: 16);
   } else {
     // Show default
     return Icon(Icons.volume_up);
   }
   ```

3. **Message ID Tracking**
   ```
   KEY REQUIREMENT: Track which message is currently speaking
   
   Purpose:
   - Highlight active speaker icon
   - Prevent multiple messages playing simultaneously
   - Cache management
   - Resume/stop specific message
   
   Implementation:
   - Each message has unique ID (from backend)
   - Pass messageId to speak() method
   - Service tracks currentMessageId
   - UI checks if message is active
   ```

4. **Audio Caching** *(Future Enhancement)*
   ```
   Cache Strategy (NOT IMPLEMENTED YET):
   - Key: messageId
   - Value: audio bytes (Uint8List)
   - Storage: In-memory Map or Hive
   - TTL: Session-based or time-based
   - Clear: On logout or after X minutes
   
   Benefits:
   - Instant replay on re-tap
   - Reduced API calls
   - Offline playback
   - Better UX
   ```

5. **Toggle Play/Stop**
   - Tap when idle → Start speaking
   - Tap when speaking → Stop speaking
   - Tap different message → Stop current, start new
   - Auto-stop on completion

#### Technical Implementation

```dart
class _ChatScreenState extends State<ChatScreen> {
  late final SpeechService _ttsService;
  
  @override
  void initState() {
    super.initState();
    
    _ttsService = sl<SpeechService>();
    _ttsService.initialize();
    
    // Rebuild UI when TTS state changes
    _ttsService.onStateChanged = () {
      if (mounted) setState(() {});
    };
  }
  
  Future<void> _handleSpeakerTap(String messageText, String messageId) async {
    AppLogger.d(
      'Speaker tapped - messageId: $messageId, isSpeaking: ${_ttsService.isSpeaking}, currentId: ${_ttsService.currentMessageId}',
      tag: 'ChatScreen TTS',
    );
    
    // Toggle: Stop if already speaking this message
    if (_ttsService.isSpeaking && 
        _ttsService.currentMessageId == messageId) {
      AppLogger.d('Stopping TTS', tag: 'ChatScreen TTS');
      await _ttsService.stop();
      setState(() {});
      return;
    }
    
    // Validate text
    if (messageText.isEmpty) {
      AppLogger.w('No text to speak', tag: 'ChatScreen TTS');
      return;
    }
    
    // Start speaking
    try {
      AppLogger.d('Starting TTS', tag: 'ChatScreen TTS');
      
      await _ttsService.speak(
        messageText,
        messageId: messageId,
      );
      
      setState(() {});  // Update UI to show playing state
    } catch (e) {
      AppLogger.e('TTS failed', error: e, tag: 'ChatScreen TTS');
      
      // Show error to user
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to play audio: $e')),
        );
      }
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return MessageBubble(
      text: message.text,
      onAudio: () => _handleSpeakerTap(message.text, message.id),
      // ... other parameters
    );
  }
}
```

#### UI States

| State | Icon | Color | Tooltip |
|-------|------|-------|---------|
| Idle | 🔊 volume_up | Grey | "Listen" |
| Loading | ⏳ Loading spinner | Blue | "Loading..." |
| Playing | 🔊 volume_up (animated) | Blue (pulsing) | "Stop" |
| Error | ⚠️ error_outline | Red | "Failed to load" |

#### Message Actions Bar

```
┌─────────────────────────────────────────┐
│  AI Message Bubble                      │
│  "मुझे diabetes है, आप regular..."     │
│                                         │
│  [📋 Copy] [🔊 Listen] [👍] [👎]       │
└─────────────────────────────────────────┘
         ↑
    Speaker button position
```

#### Error Handling

1. **API Failure:** Fall back to native TTS
2. **No Audio Data:** Show "Audio unavailable"
3. **Network Timeout:** Show "Connection timeout, try again"
4. **Playback Error:** Show "Playback failed"
5. **Empty Text:** Disable speaker button

---

## 3. Integration Points

### Chat Socket Integration

```dart
// When sending voice input
void _sendVoiceMessage(String transcript) {
  // Same as text input
  context.read<ChatCubit>().sendMessage(
    sessionId: currentSessionId,
    message: transcript,  // From STT
    attachments: [],
  );
}
```

### Message Model

```dart
class MessageEntity {
  final String id;              // Required for TTS tracking
  final String text;            // Required for TTS
  final bool isAI;              // To show speaker only on AI messages
  final DateTime timestamp;
  // ... other fields
}
```

### State Management

```dart
// Chat Cubit handles:
- Sending messages (text or voice)
- Receiving AI responses
- Message history
- Session management

// Speech Service handles:
- STT recording and transcription
- TTS audio playback
- Provider fallback
- Error recovery
```

---

## 4. User Experience Requirements

### STT UX

1. **Visual Feedback**
   - Clear indication that mic is active
   - Real-time transcript display
   - Cancel option always visible
   - Error messages user-friendly

2. **Performance**
   - Start recording within 500ms of tap
   - Transcript appears within 1s of speech
   - Smooth UI (no blocking)
   - Cancel is instant

3. **Accessibility**
   - Voice control for hands-free
   - Screen reader support
   - Large touch targets
   - Clear audio cues

### TTS UX

1. **Visual Feedback**
   - Loading spinner while fetching
   - Animated icon while playing
   - Progress indicator (optional)
   - Clear stop button

2. **Performance**
   - Audio starts within 2s of tap
   - Cached audio plays instantly
   - Smooth playback (no stuttering)
   - Stop is immediate

3. **Accessibility**
   - Haptic feedback on tap
   - Screen reader announces state
   - Large touch target (48x48dp min)
   - Keyboard accessible

---

## 5. Technical Constraints

### STT Constraints

1. **Audio Format**
   - PCM 16-bit, mono, 16kHz
   - Sent as base64-encoded chunks
   - Must use `{"audio": {"content": "..."}}` format

2. **Network**
   - Requires active internet for Sarvam
   - Falls back to native offline
   - Handles disconnections gracefully

3. **Permissions**
   - Microphone permission required
   - Must request before first use
   - Handle denial gracefully

### TTS Constraints

1. **Audio Format**
   - Received as base64-encoded audio
   - Decoded to bytes for playback
   - Format: Linear PCM or MP3

2. **API Limits**
   - Rate limits apply
   - Character limits per request
   - Monitor quota usage

3. **Storage**
   - Cache size limits (future)
   - Session-based or time-based TTL
   - Clear on logout

---

## 6. Future Enhancements

### STT Enhancements

1. **Voice Commands**
   - "Send message"
   - "Cancel"
   - "Start over"

2. **Language Detection**
   - Auto-detect Hindi vs English
   - Support regional languages

3. **Punctuation**
   - Auto-add punctuation
   - Sentence boundaries

### TTS Enhancements

1. **Audio Caching**
   - Implement Hive-based cache
   - Cache strategy with TTL
   - Clear cache management

2. **Playback Controls**
   - Pause/Resume
   - Speed control (0.5x to 2x)
   - Skip forward/backward

3. **Voice Selection**
   - User preference for speaker
   - Gender selection
   - Pace adjustment

4. **Background Playback**
   - Continue when app backgrounded
   - Notification controls
   - Lock screen controls

---

## 7. Testing Checklist

### STT Testing

- [ ] Mic button visible and accessible
- [ ] Permission request works
- [ ] Recording starts/stops correctly
- [ ] Transcript updates in real-time
- [ ] Accumulated text is complete
- [ ] Message sends correctly
- [ ] Error handling works
- [ ] Fallback to native works
- [ ] Hindi speech recognized
- [ ] English speech recognized
- [ ] Hinglish (code-mixed) works
- [ ] Cancel works correctly
- [ ] Network loss handled

### TTS Testing

- [ ] Speaker icon on AI messages
- [ ] Loading indicator shows
- [ ] Audio plays correctly
- [ ] messageId tracking works
- [ ] Multiple taps toggle play/stop
- [ ] Different messages work
- [ ] Fallback to native works
- [ ] Error messages clear
- [ ] Hindi pronunciation good
- [ ] English pronunciation good
- [ ] Code-mixed speech works
- [ ] Auto-stop on completion
- [ ] Network loss handled

---

## 8. Success Metrics

### User Engagement

- **STT Usage:** % of messages sent via voice
- **TTS Usage:** % of AI responses listened to
- **Completion Rate:** % of voice messages sent (not canceled)
- **Replay Rate:** % of messages replayed

### Technical Performance

- **STT Latency:** Time from speech end to transcript
- **TTS Latency:** Time from tap to audio start
- **Error Rate:** % of failures
- **Fallback Rate:** % of times native used
- **API Cost:** Per-minute STT, per-character TTS

### User Satisfaction

- **Voice Quality:** User feedback score
- **Accuracy:** Transcript correctness
- **Pronunciation:** TTS quality rating
- **Ease of Use:** NPS score

---

## 9. Implementation Status

### Completed ✅

- [x] STT mic button in bottom input bar
- [x] Permission handling
- [x] Real-time transcription display
- [x] Transcript accumulation
- [x] Speaker button on messages
- [x] TTS play/stop toggle
- [x] messageId tracking
- [x] Loading states
- [x] Error handling
- [x] Sarvam API integration
- [x] Native fallback
- [x] Hybrid provider architecture
- [x] Comprehensive logging

### Pending 🔄

- [ ] Audio caching for TTS
- [ ] Playback controls (pause/resume)
- [ ] Voice speed adjustment
- [ ] Background playback
- [ ] Usage analytics
- [ ] A/B testing
- [ ] User preferences (voice, speed)

---

## 10. Architecture Summary

```
Chat Speech Architecture
════════════════════════

┌─────────────────────────────────────────────┐
│           Chat UI Components                │
│  - Bottom Input Bar (STT mic button)       │
│  - Message Bubbles (TTS speaker icons)     │
└──────────────┬──────────────────────────────┘
               │
               ▼
┌─────────────────────────────────────────────┐
│           SpeechService                     │
│  (Unified facade for STT & TTS)            │
└──────────────┬──────────────────────────────┘
               │
       ┌───────┴────────┐
       ▼                ▼
┌──────────────┐  ┌─────────────┐
│ Hybrid STT   │  │ Hybrid TTS  │
│ Provider     │  │ Provider    │
└──┬────────┬──┘  └──┬───────┬──┘
   │        │        │       │
   ▼        ▼        ▼       ▼
┌──────┐ ┌──────┐ ┌─────┐ ┌──────┐
│Sarvam│ │Native│ │Sarvam│ │Native│
│ STT  │ │ STT  │ │ TTS │ │ TTS  │
└──────┘ └──────┘ └─────┘ └──────┘
```

**Key Principles:**
- **Single Responsibility:** Each component has one job
- **Dependency Injection:** Services injected, not created
- **Stream-based State:** Reactive updates
- **Smart Fallback:** Automatic recovery
- **User-Centric:** Error messages, loading states
- **Observable:** Comprehensive debug logging

---

**Document Version:** 1.0  
**Last Updated:** February 10, 2026  
**Status:** Production Ready  
**Next Review:** After user feedback and metrics
