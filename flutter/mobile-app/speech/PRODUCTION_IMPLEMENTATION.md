# Production Implementation - Hybrid Speech Service

## Overview

The production implementation is a **hybrid speech service** that uses Sarvam AI as the primary provider with native STT/TTS as an intelligent fallback. It follows clean architecture principles with dependency injection, stream-based state management, and comprehensive error handling.

**Status:** ✅ Production Ready  
**Architecture:** Provider Pattern (Strategy Pattern)  
**Fallback:** Smart automatic fallback to native services  
**Platform:** Android & iOS

---

## Architecture Overview

```
Production Architecture (Hybrid with Fallback)
═══════════════════════════════════════════════

                    ┌──────────────────┐
                    │  Consumer Apps   │
                    │  (UI Screens)    │
                    └────────┬─────────┘
                             │
                    ┌────────▼─────────┐
                    │  SpeechService   │  ← Unified Facade
                    │  (Wrapper)       │
                    └────────┬─────────┘
                             │
        ┌────────────────────┴────────────────────┐
        │                                         │
  ┌─────▼──────┐                          ┌──────▼─────┐
  │  STT       │                          │  TTS       │
  │  Provider  │                          │  Provider  │
  └─────┬──────┘                          └──────┬─────┘
        │                                        │
  ┌─────▼──────────────┐              ┌─────────▼──────────┐
  │  Hybrid STT        │              │  Hybrid TTS        │
  │  Provider          │              │  Provider          │
  └─────┬──────────────┘              └─────┬──────────────┘
        │                                   │
  ┌─────┴──────┬──────┐            ┌───────┴───────┬──────┐
  │            │      │            │               │      │
┌─▼──────┐ ┌──▼───────▼─┐      ┌──▼─────┐  ┌──────▼──────▼┐
│Sarvam  │ │   Native   │      │Sarvam  │  │   Native    │
│STT     │ │   STT      │      │TTS     │  │   TTS       │
│(Primary)│ │(Fallback) │      │(Primary)│  │(Fallback)   │
└────────┘ └────────────┘      └────────┘  └─────────────┘
     │           │                  │             │
     ▼           ▼                  ▼             ▼
  WebSocket   speech_to_text    REST API   flutter_tts
  Streaming   Package          (Dio)        Package
```

---

## File Structure

```
lib/core/services/speech/
├── providers/
│   ├── speech_provider.dart              # Abstract interfaces
│   ├── native_speech_provider.dart       # Native wrappers
│   ├── sarvam_speech_provider.dart       # Sarvam implementations
│   └── hybrid_speech_provider.dart       # Hybrid with fallback
├── speech_service.dart                   # Unified facade
├── speech_to_text_service.dart          # Legacy (kept for compatibility)
└── text_to_speech_service.dart          # Legacy (kept for compatibility)

lib/config/
└── injection_container.dart              # Dependency injection setup

docs/speech/
├── HYBRID_ARCHITECTURE.md                # Architecture details
├── CRITICAL_FIXES.md                     # Bug fixes applied
├── AUDIO_FORMAT_FIX.md                   # Format corrections
└── MIGRATION_COMPLETE.md                 # Migration summary
```

---

## Layer 1: Provider Interfaces

**File:** `lib/core/services/speech/providers/speech_provider.dart`

### Abstract Contracts

```dart
/// Speech-to-Text provider interface
abstract class SpeechToTextProvider {
  Future<void> initialize();
  Future<bool> hasPermission();
  Future<bool> requestPermission();
  Future<bool> startListening();
  Future<String> stopListening();        // Returns final transcript
  Future<void> cancelListening();
  
  Stream<String> get transcriptionStream;  // Real-time transcripts
  Stream<bool> get isListeningStream;      // Listening state
  Stream<String?> get errorStream;         // Errors
  
  bool get isListening;
  void dispose();
}

/// Text-to-Speech provider interface
abstract class TextToSpeechProvider {
  Future<void> initialize();
  Future<void> speak(String text, {String? messageId});
  Future<void> stop();
  
  bool get isSpeaking;
  String? get currentMessageId;
  
  set onStateChanged(Function()? callback);  // State change notifications
  void dispose();
}
```

**Design Philosophy:**
- **Interface Segregation:** Clear contracts
- **Dependency Inversion:** Depend on abstractions
- **Substitutability:** Any provider can replace another
- **Testability:** Easy to mock

---

## Layer 2: Native Providers

**File:** `lib/core/services/speech/providers/native_speech_provider.dart`

### Adapter Pattern

Wraps existing native services to conform to new interfaces:

```dart
class NativeSpeechToTextProvider implements SpeechToTextProvider {
  final SpeechToTextService _service;
  
  NativeSpeechToTextProvider(this._service);
  
  @override
  Future<void> initialize() => _service.initialize();
  
  @override
  Future<bool> startListening() => _service.startListening();
  
  @override
  Future<String> stopListening() => _service.stopListening();
  
  @override
  Stream<String> get transcriptionStream => _service.transcriptionStream;
  
  @override
  bool get isListening => _service.isListening;
  
  // ... all other methods delegate to _service
}

class NativeTextToSpeechProvider implements TextToSpeechProvider {
  final TextToSpeechService _service;
  
  NativeTextToSpeechProvider(this._service);
  
  @override
  Future<void> speak(String text, {String? messageId}) =>
      _service.speak(text, messageId: messageId);
  
  // ... all other methods delegate to _service
}
```

**Purpose:**
- **Backward Compatibility:** Reuse existing services
- **Zero Code Change:** Native services unchanged
- **Adapter Pattern:** Adapt old interface to new
- **Fallback Ready:** Reliable fallback provider

---

## Layer 3: Sarvam Providers

**File:** `lib/core/services/speech/providers/sarvam_speech_provider.dart`

### STT Implementation

```dart
class SarvamSpeechToTextProvider implements SpeechToTextProvider {
  final String apiKey;
  final String wsUrl;
  
  // Dependencies
  final AudioRecorder _audioRecorder = AudioRecorder();
  IOWebSocketChannel? _channel;
  StreamSubscription? _audioStreamSubscription;
  
  // State
  bool _isListening = false;
  bool _isInitialized = false;
  String _accumulatedTranscription = '';
  
  // Streams
  final _transcriptionController = StreamController<String>.broadcast();
  final _isListeningController = StreamController<bool>.broadcast();
  final _errorController = StreamController<String?>.broadcast();
  
  @override
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      final hasPermission = await _audioRecorder.hasPermission();
      if (!hasPermission) {
        throw Exception('Microphone permission required');
      }
      
      _isInitialized = true;
      
      if (kDebugMode) {
        AppLogger.d('Initialized', tag: 'Sarvam STT');
      }
    } catch (e) {
      if (kDebugMode) {
        AppLogger.e('Initialization failed', error: e, tag: 'Sarvam STT');
      }
      rethrow;
    }
  }
  
  @override
  Future<bool> startListening() async {
    if (_isListening) return false;
    
    if (!_isInitialized) {
      await initialize();
    }
    
    try {
      _accumulatedTranscription = '';
      _transcriptionController.add('');
      
      await _connectWebSocket();
      await _startAudioStreaming();
      
      _isListening = true;
      _isListeningController.add(true);
      
      if (kDebugMode) {
        AppLogger.d('Started listening', tag: 'Sarvam STT');
      }
      
      return true;
    } catch (e) {
      if (kDebugMode) {
        AppLogger.e('Failed to start', error: e, tag: 'Sarvam STT');
      }
      
      _isListening = false;
      _isListeningController.add(false);
      _errorController.add('Failed to start: $e');
      return false;
    }
  }
  
  Future<void> _connectWebSocket() async {
    final uri = Uri(
      scheme: 'wss',
      host: 'api.sarvam.ai',
      path: '/speech-to-text/ws',
      queryParameters: {
        'language-code': 'unknown',
        'model': 'saarika:v2.5',
        'high_vad_sensitivity': 'true',
        'vad_signals': 'true',
        'flush_signal': 'true',
        'sample_rate': '16000',
        'input_audio_codec': 'wav',
      },
    );
    
    if (kDebugMode) {
      AppLogger.d('Connecting WebSocket...', tag: 'Sarvam STT');
    }
    
    final webSocket = await WebSocket.connect(
      uri.toString(),
      headers: {'api-subscription-key': apiKey},
    );
    
    _channel = IOWebSocketChannel(webSocket);
    
    if (kDebugMode) {
      AppLogger.success('WebSocket connected', tag: 'Sarvam STT');
    }
    
    _channel!.stream.listen(
      _handleWebSocketMessage,
      onError: (error) {
        if (kDebugMode) {
          AppLogger.e('WebSocket error', error: error, tag: 'Sarvam STT');
        }
        _isListening = false;
        _isListeningController.add(false);
        _errorController.add('Connection error: $error');
      },
      onDone: () {
        if (kDebugMode) {
          AppLogger.d('WebSocket closed', tag: 'Sarvam STT');
        }
        if (_isListening) {
          _isListening = false;
          _isListeningController.add(false);
          _errorController.add('Connection closed unexpectedly');
        }
      },
      cancelOnError: false,  // Keep stream active on errors
    );
  }
  
  Future<void> _startAudioStreaming() async {
    if (kDebugMode) {
      AppLogger.d('Starting audio stream...', tag: 'Sarvam STT');
    }
    
    final stream = await _audioRecorder.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 16000,
        numChannels: 1,
      ),
    );
    
    if (kDebugMode) {
      AppLogger.success('Audio stream started', tag: 'Sarvam STT');
    }
    
    _audioStreamSubscription = stream.listen(
      (audioChunk) {
        if (_channel != null && _isListening) {
          final base64Audio = base64Encode(audioChunk);
          
          // CRITICAL: Correct format for Sarvam API
          _channel!.sink.add(jsonEncode({
            'audio': {
              'content': base64Audio,
            }
          }));
        }
      },
      onError: (error) {
        if (kDebugMode) {
          AppLogger.e('Audio stream error', error: error, tag: 'Sarvam STT');
        }
        _isListening = false;
        _isListeningController.add(false);
        _errorController.add('Microphone error: $error');
      },
      cancelOnError: false,
    );
  }
  
  void _handleWebSocketMessage(dynamic message) {
    try {
      if (kDebugMode) {
        AppLogger.d('Received: $message', tag: 'Sarvam STT');
      }
      
      final data = jsonDecode(message as String) as Map<String, dynamic>;
      final type = data['type'] as String?;
      
      if (type == 'data') {
        final responseData = data['data'] as Map<String, dynamic>?;
        final transcript = responseData?['transcript'] as String?;
        
        if (transcript != null && transcript.isNotEmpty) {
          _accumulatedTranscription = transcript;
          _transcriptionController.add(transcript);
          
          if (kDebugMode) {
            AppLogger.success('Transcript: "$transcript"', tag: 'Sarvam STT');
          }
        }
      } else if (type == 'error') {
        final errorData = data['data'] as Map<String, dynamic>?;
        final errorMsg = errorData?['error'] as String? ?? 'Unknown error';
        
        _isListening = false;
        _isListeningController.add(false);
        _errorController.add(errorMsg);
        
        if (kDebugMode) {
          AppLogger.e('Server error: $errorMsg', tag: 'Sarvam STT');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        AppLogger.e('Failed to parse message', error: e, tag: 'Sarvam STT');
      }
    }
  }
  
  @override
  Future<String> stopListening() async {
    if (!_isListening) return _accumulatedTranscription;
    
    try {
      // Send flush signal for final transcription
      if (_channel != null) {
        _channel!.sink.add(jsonEncode({'flush': true}));
      }
      
      await _audioStreamSubscription?.cancel();
      await _audioRecorder.stop();
      _channel?.sink.close();
      
      _isListening = false;
      _isListeningController.add(false);
      
      if (kDebugMode) {
        AppLogger.d(
          'Stopped. Final: "$_accumulatedTranscription"',
          tag: 'Sarvam STT',
        );
      }
      
      return _accumulatedTranscription;
    } catch (e) {
      if (kDebugMode) {
        AppLogger.e('Error stopping', error: e, tag: 'Sarvam STT');
      }
      return _accumulatedTranscription;
    }
  }
  
  @override
  void dispose() {
    _audioStreamSubscription?.cancel();
    _audioRecorder.dispose();
    _channel?.sink.close();
    _transcriptionController.close();
    _isListeningController.close();
    _errorController.close();
  }
}
```

### TTS Implementation

```dart
class SarvamTextToSpeechProvider implements TextToSpeechProvider {
  final String apiKey;
  final String baseUrl;
  
  final Dio _dio = Dio();
  final AudioPlayer _audioPlayer = AudioPlayer();
  
  bool _isSpeaking = false;
  String? _currentMessageId;
  Function()? _onStateChanged;
  
  @override
  Future<void> initialize() async {
    if (kDebugMode) {
      AppLogger.d('Initializing with baseUrl: $baseUrl', tag: 'Sarvam TTS');
    }
    
    _dio.options.baseUrl = baseUrl;
    _dio.options.connectTimeout = const Duration(seconds: 30);
    _dio.options.receiveTimeout = const Duration(seconds: 30);
    
    _audioPlayer.onPlayerComplete.listen((_) {
      _isSpeaking = false;
      _currentMessageId = null;
      _onStateChanged?.call();
      
      if (kDebugMode) {
        AppLogger.d('Playback completed', tag: 'Sarvam TTS');
      }
    });
    
    if (kDebugMode) {
      _setupDebugLogging();
      AppLogger.success('Initialized successfully', tag: 'Sarvam TTS');
    }
  }
  
  void _setupDebugLogging() {
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          AppLogger.d('→ ${options.method} ${options.baseUrl}${options.path}', tag: 'Sarvam TTS');
          AppLogger.d('Headers: ${options.headers}', tag: 'Sarvam TTS');
          AppLogger.d('Payload: ${options.data}', tag: 'Sarvam TTS');
          return handler.next(options);
        },
        onResponse: (response, handler) {
          AppLogger.success('← ${response.statusCode} ${response.requestOptions.path}', tag: 'Sarvam TTS');
          return handler.next(response);
        },
        onError: (error, handler) {
          AppLogger.e('API Error [${error.response?.statusCode}]', error: error.response?.data, tag: 'Sarvam TTS');
          return handler.next(error);
        },
      ),
    );
  }
  
  @override
  Future<void> speak(String text, {String? messageId}) async {
    if (text.isEmpty) {
      if (kDebugMode) {
        AppLogger.w('Empty text, skipping', tag: 'Sarvam TTS');
      }
      return;
    }
    
    if (kDebugMode) {
      AppLogger.d(
        'Speaking: "${text.substring(0, text.length > 50 ? 50 : text.length)}${text.length > 50 ? '...' : ''}" (messageId: $messageId)',
        tag: 'Sarvam TTS',
      );
    }
    
    try {
      await stop();
      
      _currentMessageId = messageId;
      _isSpeaking = true;
      _onStateChanged?.call();
      
      if (kDebugMode) {
        AppLogger.d('Making API request...', tag: 'Sarvam TTS');
      }
      
      final response = await _dio.post(
        '/text-to-speech',
        data: {
          'text': text,
          'target_language_code': 'hi-IN',
          'model': 'bulbul:v3',
          'speaker': 'priya',  // MUST be lowercase
          'pace': 1.0,
        },
        options: Options(
          headers: {
            'api-subscription-key': apiKey,
            'Content-Type': 'application/json',
          },
        ),
      );
      
      final responseData = response.data as Map<String, dynamic>;
      final audios = responseData['audios'] as List<dynamic>?;
      
      if (audios == null || audios.isEmpty) {
        throw Exception('No audio data received');
      }
      
      final base64Audio = audios[0] as String;
      final audioBytes = base64Decode(base64Audio);
      
      if (kDebugMode) {
        AppLogger.d('Playing audio (${audioBytes.length} bytes)', tag: 'Sarvam TTS');
      }
      
      await _audioPlayer.play(BytesSource(audioBytes));
      
      if (kDebugMode) {
        AppLogger.success('Playback started', tag: 'Sarvam TTS');
      }
    } catch (e) {
      _isSpeaking = false;
      _currentMessageId = null;
      _onStateChanged?.call();
      
      if (kDebugMode) {
        AppLogger.e('Failed to speak', error: e, tag: 'Sarvam TTS');
      }
      rethrow;
    }
  }
  
  @override
  Future<void> stop() async {
    if (_isSpeaking) {
      await _audioPlayer.stop();
      _isSpeaking = false;
      _currentMessageId = null;
      _onStateChanged?.call();
    }
  }
  
  @override
  bool get isSpeaking => _isSpeaking;
  
  @override
  String? get currentMessageId => _currentMessageId;
  
  @override
  set onStateChanged(Function()? callback) => _onStateChanged = callback;
  
  @override
  void dispose() {
    _audioPlayer.dispose();
    _dio.close();
  }
}
```

**Key Features:**
- WebSocket streaming for STT
- REST API for TTS
- Comprehensive logging (debug only)
- Error handling at every step
- Stream-based state management
- Proper resource cleanup

---

## Layer 4: Hybrid Providers

**File:** `lib/core/services/speech/providers/hybrid_speech_provider.dart`

### Smart Fallback Logic

```dart
class HybridSpeechToTextProvider implements SpeechToTextProvider {
  final SpeechToTextProvider primaryProvider;   // Sarvam
  final SpeechToTextProvider fallbackProvider;  // Native
  
  SpeechToTextProvider? _activeProvider;
  bool _primaryFailed = false;
  StreamSubscription<String?>? _primaryErrorSub;
  
  // Streams for unified interface
  final _transcriptionController = StreamController<String>.broadcast();
  final _isListeningController = StreamController<bool>.broadcast();
  final _errorController = StreamController<String?>.broadcast();
  
  @override
  Future<bool> startListening() async {
    if (!_primaryFailed) {
      try {
        if (kDebugMode) {
          AppLogger.d('Attempting primary (Sarvam)', tag: 'Hybrid STT');
        }
        
        final result = await primaryProvider.startListening();
        
        if (result) {
          _setActiveProvider(primaryProvider);
          
          // Monitor primary for post-connection failures
          _primaryErrorSub?.cancel();
          _primaryErrorSub = primaryProvider.errorStream.listen((error) {
            if (error != null && error.isNotEmpty) {
              if (kDebugMode) {
                AppLogger.w('Primary error detected: $error', tag: 'Hybrid STT');
              }
              
              if (_activeProvider == primaryProvider && !primaryProvider.isListening) {
                _primaryFailed = true;
                _errorController.add(error);
              }
            }
          });
          
          if (kDebugMode) {
            AppLogger.success('Primary provider started', tag: 'Hybrid STT');
          }
          
          // Verify connection after 500ms
          await Future.delayed(const Duration(milliseconds: 500));
          
          if (!primaryProvider.isListening) {
            if (kDebugMode) {
              AppLogger.w('Primary stopped immediately, falling back', tag: 'Hybrid STT');
            }
            
            _primaryFailed = true;
            await primaryProvider.cancelListening();
            
            // Fall back to native
            if (kDebugMode) {
              AppLogger.d('Using fallback (Native) after immediate failure', tag: 'Hybrid STT');
            }
            
            final fallbackResult = await fallbackProvider.startListening();
            if (fallbackResult) {
              _setActiveProvider(fallbackProvider);
            }
            return fallbackResult;
          }
          
          return true;
        }
      } catch (e) {
        if (kDebugMode) {
          AppLogger.w('Primary failed, using fallback: $e', tag: 'Hybrid STT');
        }
        _primaryFailed = true;
      }
    }
    
    // Use fallback
    if (kDebugMode) {
      AppLogger.d('Using fallback (Native)', tag: 'Hybrid STT');
    }
    
    final result = await fallbackProvider.startListening();
    if (result) {
      _setActiveProvider(fallbackProvider);
    }
    return result;
  }
  
  void _setActiveProvider(SpeechToTextProvider provider) {
    _activeProvider = provider;
    
    // Forward streams from active provider
    _transcriptionSub?.cancel();
    _listeningSub?.cancel();
    _errorSub?.cancel();
    
    _transcriptionSub = provider.transcriptionStream.listen(_transcriptionController.add);
    _listeningSub = provider.isListeningStream.listen(_isListeningController.add);
    _errorSub = provider.errorStream.listen(_errorController.add);
  }
  
  @override
  Future<String> stopListening() async {
    if (_activeProvider == null) return '';
    return await _activeProvider!.stopListening();
  }
}

class HybridTextToSpeechProvider implements TextToSpeechProvider {
  final TextToSpeechProvider primaryProvider;   // Sarvam
  final TextToSpeechProvider fallbackProvider;  // Native
  
  Function()? _onStateChanged;
  
  @override
  Future<void> speak(String text, {String? messageId}) async {
    if (kDebugMode) {
      AppLogger.d(
        'speak() called with text: "${text.substring(0, text.length > 30 ? 30 : text.length)}${text.length > 30 ? '...' : ''}", messageId: $messageId',
        tag: 'Hybrid TTS',
      );
    }
    
    try {
      if (kDebugMode) {
        AppLogger.d('Attempting primary (Sarvam)', tag: 'Hybrid TTS');
      }
      
      await primaryProvider.speak(text, messageId: messageId);
      
      if (kDebugMode) {
        AppLogger.success('Primary provider speaking', tag: 'Hybrid TTS');
      }
    } catch (e) {
      if (kDebugMode) {
        AppLogger.w('Primary failed, using fallback: $e', tag: 'Hybrid TTS');
      }
      
      await fallbackProvider.speak(text, messageId: messageId);
      
      if (kDebugMode) {
        AppLogger.success('Fallback provider speaking', tag: 'Hybrid TTS');
      }
    }
  }
  
  @override
  bool get isSpeaking =>
      primaryProvider.isSpeaking || fallbackProvider.isSpeaking;
  
  @override
  String? get currentMessageId =>
      primaryProvider.currentMessageId ?? fallbackProvider.currentMessageId;
}
```

**Smart Features:**
- **500ms verification:** Detects immediate failures
- **Error monitoring:** Watches for post-connection issues
- **Automatic fallback:** No user intervention
- **Stream forwarding:** Active provider's streams exposed
- **State tracking:** Knows which provider is active

---

## Layer 5: Unified Service

**File:** `lib/core/services/speech/speech_service.dart`

### Single API for Consumers

```dart
class SpeechService {
  final SpeechToTextProvider sttProvider;
  final TextToSpeechProvider ttsProvider;
  
  SpeechService({
    required this.sttProvider,
    required this.ttsProvider,
  });
  
  Future<void> initialize() async {
    if (kDebugMode) {
      AppLogger.d('Initializing speech service...', tag: 'SpeechService');
    }
    
    await sttProvider.initialize();
    await ttsProvider.initialize();
    
    if (kDebugMode) {
      AppLogger.success('Speech service initialized', tag: 'SpeechService');
    }
  }
  
  // STT methods
  Future<bool> hasPermission() => sttProvider.hasPermission();
  Future<bool> requestPermission() => sttProvider.requestPermission();
  Future<bool> startListening() => sttProvider.startListening();
  Future<String> stopListening() => sttProvider.stopListening();
  Future<void> cancelListening() => sttProvider.cancelListening();
  
  Stream<String> get transcriptionStream => sttProvider.transcriptionStream;
  Stream<bool> get isListeningStream => sttProvider.isListeningStream;
  Stream<String?> get errorStream => sttProvider.errorStream;
  bool get isListening => sttProvider.isListening;
  
  // TTS methods
  Future<void> speak(String text, {String? messageId}) async {
    if (kDebugMode) {
      AppLogger.d(
        'SpeechService.speak() called with: "${text.substring(0, text.length > 30 ? 30 : text.length)}${text.length > 30 ? '...' : ''}", messageId: $messageId',
        tag: 'SpeechService',
      );
    }
    return ttsProvider.speak(text, messageId: messageId);
  }
  
  Future<void> stop() async {
    if (kDebugMode) {
      AppLogger.d('SpeechService.stop() called', tag: 'SpeechService');
    }
    return ttsProvider.stop();
  }
  
  bool get isSpeaking => ttsProvider.isSpeaking;
  String? get currentMessageId => ttsProvider.currentMessageId;
  set onStateChanged(Function()? callback) => ttsProvider.onStateChanged = callback;
  
  void dispose() {
    sttProvider.dispose();
    ttsProvider.dispose();
  }
}
```

**Purpose:**
- **Unified API:** Single service for all consumers
- **Backward Compatible:** Same API as legacy services
- **Logging:** Centralized logging point
- **Simplicity:** Consumers don't know about providers

---

## Dependency Injection

**File:** `lib/config/injection_container.dart`

### Registration Setup

```dart
Future<void> setupDependencies() async {
  // Load environment variables
  await dotenv.load(fileName: 'env.dev');
  
  // Legacy services (kept for backward compatibility)
  sl.registerLazySingleton<SpeechToTextService>(() => SpeechToTextService());
  sl.registerLazySingleton<TextToSpeechService>(() => TextToSpeechService());
  
  // Native providers (wrap legacy services)
  sl.registerLazySingleton<NativeSpeechToTextProvider>(
    () => NativeSpeechToTextProvider(sl<SpeechToTextService>()),
  );
  sl.registerLazySingleton<NativeTextToSpeechProvider>(
    () => NativeTextToSpeechProvider(sl<TextToSpeechService>()),
  );
  
  // Sarvam providers (from environment)
  sl.registerLazySingleton<SarvamSpeechToTextProvider>(
    () => SarvamSpeechToTextProvider(
      apiKey: dotenv.env['SARVAM_API_KEY'] ?? '',
      wsUrl: dotenv.env['SARVAM_STT_WS_URL'] ?? 'wss://api.sarvam.ai/speech-to-text/ws',
    ),
  );
  sl.registerLazySingleton<SarvamTextToSpeechProvider>(
    () => SarvamTextToSpeechProvider(
      apiKey: dotenv.env['SARVAM_API_KEY'] ?? '',
      baseUrl: dotenv.env['SARVAM_TTS_URL'] ?? 'https://api.sarvam.ai',
    ),
  );
  
  // Hybrid providers (primary: Sarvam, fallback: Native)
  sl.registerLazySingleton<HybridSpeechToTextProvider>(
    () => HybridSpeechToTextProvider(
      primaryProvider: sl<SarvamSpeechToTextProvider>(),
      fallbackProvider: sl<NativeSpeechToTextProvider>(),
    ),
  );
  sl.registerLazySingleton<HybridTextToSpeechProvider>(
    () => HybridTextToSpeechProvider(
      primaryProvider: sl<SarvamTextToSpeechProvider>(),
      fallbackProvider: sl<NativeTextToSpeechProvider>(),
    ),
  );
  
  // Unified Speech Service (uses hybrid providers)
  sl.registerLazySingleton<SpeechService>(
    () => SpeechService(
      sttProvider: sl<HybridSpeechToTextProvider>(),
      ttsProvider: sl<HybridTextToSpeechProvider>(),
    ),
  );
}
```

**Dependency Graph:**
```
SpeechService
    ↓
HybridProviders (STT/TTS)
    ↓
[Sarvam Providers]  [Native Providers]
         ↓               ↓
   [Sarvam API]    [Legacy Services]
```

---

## Consumer Usage

### Example: ChatScreen (TTS)

```dart
class _ChatScreenState extends State<ChatScreen> {
  late final SpeechService _ttsService;
  
  @override
  void initState() {
    super.initState();
    
    // Get service from DI
    _ttsService = sl<SpeechService>();
    _ttsService.initialize();
    
    // Listen for state changes
    _ttsService.onStateChanged = () {
      if (mounted) setState(() {});
    };
  }
  
  // In UI callback
  onAudio: () async {
    if (_ttsService.isSpeaking &&
        _ttsService.currentMessageId == messageIdForTTS) {
      await _ttsService.stop();
    } else if (textForActions.isNotEmpty) {
      await _ttsService.speak(
        textForActions,
        messageId: messageIdForTTS,
      );
    }
    setState(() {});
  }
}
```

### Example: HoldToSpeakOverlay (STT)

```dart
class _HoldToSpeakOverlayState extends State<HoldToSpeakOverlay> {
  late SpeechService _speechService;
  
  @override
  void initState() {
    super.initState();
    
    _speechService = sl<SpeechService>();
    
    // Listen to streams
    _speechService.transcriptionStream.listen((transcript) {
      setState(() => _displayedText = transcript);
    });
    
    _speechService.isListeningStream.listen((isListening) {
      setState(() => _isListening = isListening);
    });
    
    _speechService.errorStream.listen((error) {
      if (error != null) {
        // Handle error
      }
    });
  }
  
  Future<void> _startListening() async {
    final success = await _speechService.startListening();
    if (!success) {
      // Handle failure
    }
  }
  
  Future<void> _stopListening() async {
    final finalText = await _speechService.stopListening();
    widget.onComplete?.call(finalText);
  }
}
```

---

## Key Design Patterns

1. **Strategy Pattern:** Interchangeable providers
2. **Adapter Pattern:** Native service wrappers
3. **Facade Pattern:** SpeechService unified API
4. **Dependency Injection:** GetIt container
5. **Observer Pattern:** Stream-based state
6. **Template Method:** Provider interface contracts

---

## Production Benefits

1. **Smart Fallback:** Never breaks user experience
2. **Zero Breaking Changes:** Same API as legacy
3. **Scalable:** Easy to add new providers
4. **Testable:** Mock any layer
5. **Maintainable:** Clear separation of concerns
6. **Observable:** Comprehensive logging
7. **Resilient:** Error handling at every level

---

**Production Status:** ✅ Live and Working  
**Fallback Tested:** ✅ Verified  
**Performance:** ✅ Optimized with kDebugMode  
**Next:** Monitor usage and optimize based on metrics
