# Deep Link Setup with SuprSend

Complete guide for implementing deep linking in Flutter with SuprSend notifications.

---

## Table of Contents

1. [Current Recommended Approach](#current-recommended-approach-january-2026)
2. [Overview](#overview)
3. [Android Setup](#android-setup)
4. [Flutter Setup](#flutter-setup)
5. [Architecture](#architecture)
6. [Supported Deep Links](#supported-deep-links)
7. [Common Issues & Solutions](#common-issues--solutions)
8. [Testing](#testing)
9. [Historical: Previous Complex Approach](#historical-previous-complex-approach)

---

## Current Recommended Approach (January 2026)

After extensive testing and research, we found that the **official simple approach** works perfectly. The complexity we added earlier was unnecessary.

### The Key Discovery

The crashes and issues we faced were caused by **Flutter's built-in deep link handler conflicting with the `app_links` package**. The fix is a single meta-data tag:

```xml
<meta-data android:name="flutter_deeplinking_enabled" android:value="false" />
```

### Minimal Working Implementation

**Total: ~50 lines of code across 2 files**

#### 1. MainActivity.kt (5 lines)

```kotlin
package com.example.myapp

import io.flutter.embedding.android.FlutterFragmentActivity

class MainActivity : FlutterFragmentActivity()
```

That's it. No native delay, no intent interception, no complex logic.

#### 2. AndroidManifest.xml (critical additions)

```xml
<activity
    android:name=".MainActivity"
    android:exported="true"
    android:launchMode="singleTask"
    ...>
    
    <!-- CRITICAL: Disable Flutter's built-in deep link handler -->
    <meta-data
        android:name="flutter_deeplinking_enabled"
        android:value="false"
        />
    
    <!-- Deep link intent filter -->
    <intent-filter android:autoVerify="true">
        <action android:name="android.intent.action.VIEW" />
        <category android:name="android.intent.category.DEFAULT" />
        <category android:name="android.intent.category.BROWSABLE" />
        <data android:scheme="<app>" android:host="*" />
    </intent-filter>
</activity>
```

#### 3. DeepLinkService.dart (40 lines)

```dart
import 'dart:async';
import 'package:app_links/app_links.dart';

class DeepLinkService {
  static const String _tag = 'DeepLinkService';

  final AppLinks _appLinks = AppLinks();
  StreamSubscription<Uri>? _sub;
  Uri? _pending;
  bool _ready = false;

  void initialize() {
    _sub = _appLinks.uriLinkStream.listen((uri) {
      AppLogger.d('Deep link received: $uri', tag: _tag);
      if (_ready) {
        DeepLinkHandler.handleDeepLink(uri);
      } else {
        _pending = uri;
      }
    });
    AppLogger.d('DeepLinkService initialized', tag: _tag);
  }

  void setReady() {
    _ready = true;
    AppLogger.d('App ready for deep links', tag: _tag);
    if (_pending != null) {
      DeepLinkHandler.handleDeepLink(_pending!);
      _pending = null;
    }
  }

  void dispose() {
    _sub?.cancel();
    _sub = null;
  }
}
```

#### 4. Usage in HomeScreen/LoginScreen

```dart
void _processDeepLinkWhenStable() {
  Future.delayed(const Duration(milliseconds: 500), () {
    if (!mounted) return;
    final deepLinkService = sl<DeepLinkService>();
    deepLinkService.initialize();
    deepLinkService.setReady();
  });
}
```

### Why This Works

| Component | Purpose |
|-----------|---------|
| `flutter_deeplinking_enabled=false` | Prevents Flutter's built-in handler from conflicting with `app_links` |
| `singleTask` launch mode | Prevents duplicate app instances |
| `uriLinkStream.listen()` | Receives deep links in all app states (foreground, background, killed) |
| `_ready` flag | Ensures navigation only happens after splash screen completes |

### What We Learned

1. **The native delay was NOT needed** - The `app_links` package handles killed-mode correctly when Flutter's built-in handler is disabled
2. **The complex queuing was NOT needed** - A simple `_ready` flag is sufficient
3. **The meta-data tag was the ONLY missing piece** - This is documented in `app_links` but easy to miss

---

## Overview

Deep links allow users to tap on a notification and navigate directly to a specific screen in the app. This implementation uses:

- **SuprSend** for push notifications with deep link payloads
- **app_links** Flutter package for handling deep links
- **Custom URI scheme**: `<myapp>://`

### Flow Diagram

```
┌─────────────────┐     ┌──────────────────┐     ┌─────────────────┐
│  SuprSend Push  │────>│  Android Native  │────>│  Flutter        │
│  Notification   │     │  Intent Handler  │     │  app_links      │
└─────────────────┘     └──────────────────┘     └─────────────────┘
                                                          │
                                                          v
                                                 ┌─────────────────┐
                                                 │ DeepLinkService │
                                                 │ (processes URI) │
                                                 └─────────────────┘
                                                          │
                                                          v
                                                 ┌─────────────────┐
                                                 │ DeepLinkHandler │
                                                 │ (routes to UI)  │
                                                 └─────────────────┘
```

---

## Android Setup

### 1. AndroidManifest.xml

Add intent filters to `MainActivity` for handling deep links:

```xml
<!-- android/app/src/main/AndroidManifest.xml -->
<activity
    android:name=".MainActivity"
    android:exported="true"
    android:launchMode="singleTask"
    android:theme="@style/LaunchTheme"
    android:configChanges="orientation|keyboardHidden|keyboard|screenSize|smallestScreenSize|locale|layoutDirection|fontScale|screenLayout|density|uiMode"
    android:hardwareAccelerated="true"
    android:windowSoftInputMode="adjustResize">
    
    <!-- Normal launcher intent -->
    <intent-filter>
        <action android:name="android.intent.action.MAIN"/>
        <category android:name="android.intent.category.LAUNCHER"/>
    </intent-filter>
    
    <!-- Deep link intent filter for <myapp>:// scheme -->
    <intent-filter android:autoVerify="true">
        <action android:name="android.intent.action.VIEW" />
        <category android:name="android.intent.category.DEFAULT" />
        <category android:name="android.intent.category.BROWSABLE" />
        <data android:scheme="<app>" />
    </intent-filter>
</activity>

<!-- SuprSend notification redirection activity -->
<activity
    android:name="app.suprsend.inbox.NotificationRedirectionActivity"
    android:exported="true"
    android:launchMode="singleTask">
    <intent-filter>
        <action android:name="android.intent.action.VIEW" />
        <category android:name="android.intent.category.DEFAULT" />
        <category android:name="android.intent.category.BROWSABLE" />
        <data android:scheme="<app>" />
    </intent-filter>
</activity>
```

**Key Points:**
- `android:launchMode="singleTask"` - Prevents duplicate app instances
- `android:exported="true"` - Required for deep link handling
- Don't use `android:taskAffinity=""` - Can cause duplicate instances

### 2. MainActivity.kt

Handle deep links natively with a delay for killed app state:

```kotlin
// android/app/src/main/kotlin/ai/example/<app>/MainActivity.kt
package com.example.myapp

import android.content.Intent
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    companion object {
        private const val TAG = "MainActivity"
        private const val DEEP_LINK_DELAY_MS = 4000L // 4 seconds for splash + init
    }

    private var pendingDeepLinkIntent: Intent? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Handle deep link when app is launched from killed state
        intent?.let { incomingIntent ->
            if (incomingIntent.action == Intent.ACTION_VIEW && incomingIntent.data != null) {
                Log.d(TAG, "onCreate: Deep link received: ${incomingIntent.data}")

                // Store the deep link intent for delayed processing
                pendingDeepLinkIntent = Intent(incomingIntent)

                // Clear the current intent to prevent app_links from processing it too early
                intent = Intent(incomingIntent).apply {
                    action = Intent.ACTION_MAIN
                    data = null
                }

                // Re-inject the deep link after Flutter is fully initialized
                Handler(Looper.getMainLooper()).postDelayed({
                    pendingDeepLinkIntent?.let { delayedIntent ->
                        Log.d(TAG, "onCreate: Re-injecting deep link after delay")
                        onNewIntent(delayedIntent)
                        pendingDeepLinkIntent = null
                    }
                }, DEEP_LINK_DELAY_MS)
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        // This handles deep links when app is in foreground or background
        Log.d(TAG, "onNewIntent: ${intent.action} - ${intent.data}")
    }
}
```

**Why the delay?**
- When the app is killed and launched via deep link, Flutter's engine isn't ready
- The `app_links` package tries to communicate via MethodChannel too early
- This causes a framework assertion crash: `'_elements.contains(element)': is not true`
- The 4-second delay ensures Flutter is fully initialized before processing

---

## Flutter Setup

### 1. Dependencies

```yaml
# pubspec.yaml
dependencies:
  app_links: ^6.3.3
```

### 2. DeepLinkService

Manages the `app_links` package and processes incoming deep links:

```dart
// lib/core/services/deep_link_service.dart
import 'dart:async';
import 'package:app_links/app_links.dart';

class DeepLinkService {
  static const String _tag = 'DeepLinkService';

  final AppLinks _appLinks = AppLinks();
  StreamSubscription<Uri>? _linkSubscription;
  Uri? _pendingInitialLink;
  bool _isAppFullyInitialized = false;

  Future<void> initialize() async {
    // Start listening for deep links immediately
    _startListening();
    AppLogger.d('DeepLinkService initialized with stream listener', tag: _tag);
  }

  void _startListening() {
    _linkSubscription = _appLinks.uriLinkStream.listen(
      (Uri uri) {
        AppLogger.d('Deep link received via stream: $uri', tag: _tag);
        _processDeepLink(uri);
      },
      onError: (error) {
        AppLogger.e('Deep link stream error', error: error, tag: _tag);
      },
    );
    AppLogger.d('Stream listener started successfully', tag: _tag);
  }

  /// Called after splash screen completes and app is fully ready
  void setAppFullyInitialized() {
    _isAppFullyInitialized = true;
    AppLogger.d('App marked as fully initialized', tag: _tag);

    // Process any pending initial deep link
    if (_pendingInitialLink != null) {
      AppLogger.d('Processing pending initial link: $_pendingInitialLink', tag: _tag);
      _processDeepLink(_pendingInitialLink!);
      _pendingInitialLink = null;
    } else {
      AppLogger.d('No pending deep link', tag: _tag);
    }
  }

  void _processDeepLink(Uri uri) {
    AppLogger.d('_processDeepLink called with: $uri', tag: _tag);

    if (!_isAppFullyInitialized) {
      AppLogger.d('App not ready, queueing deep link', tag: _tag);
      _pendingInitialLink = uri;
      return;
    }

    AppLogger.d('Calling DeepLinkHandler.handleDeepLink', tag: _tag);
    DeepLinkHandler.handleDeepLink(uri);
    AppLogger.d('DeepLinkHandler.handleDeepLink completed', tag: _tag);
  }

  void dispose() {
    _linkSubscription?.cancel();
    _linkSubscription = null;
  }
}
```

### 3. DeepLinkHandler

Routes deep links to the appropriate screens:

```dart
// lib/core/navigation/deep_link_handler.dart
import 'package:<AppName>_AI/config/injection_container.dart';
import 'package:<AppName>_AI/config/routes/app_routes.dart';
import 'package:<AppName>_AI/core/cubit/navigation_cubit.dart';
import 'package:<AppName>_AI/core/navigation/app_navigation.dart';
import 'package:<AppName>_AI/core/utils/logger.dart';

class DeepLinkHandler {
  static const String _scheme = '<app>';
  static const String _tag = 'DeepLinkHandler';

  static bool isValidScheme(Uri uri) {
    return uri.scheme == _scheme;
  }

  static void handleDeepLink(Uri uri) {
    try {
      AppLogger.d('Deep link received: $uri', tag: _tag);

      if (!isValidScheme(uri)) {
        AppLogger.w('Invalid scheme: ${uri.scheme}', tag: _tag);
        _navigateToTab(NavigationPage.home);
        return;
      }

      final route = _parseRoute(uri);
      final queryParams = uri.queryParameters;

      AppLogger.d('Parsed route: $route', tag: _tag);

      switch (route) {
        // PageView tabs
        case '/home':
        case '':
          _navigateToTab(NavigationPage.home);
          break;
        case '/chat':
          _navigateToTab(NavigationPage.chat);
          break;
        case '/health/stats':
          _navigateToTab(NavigationPage.healthScore);
          break;
        case '/profile':
          _navigateToTab(NavigationPage.profile);
          break;

        // Standalone screens
        case '/reminders':
          _navigateToScreen(AppRoutes.remindersRoute);
          break;

        // Not implemented yet
        case '/report/view':
          final reportId = queryParams['id'];
          AppLogger.d('Report deep link - id: $reportId (not implemented)', tag: _tag);
          _navigateToTab(NavigationPage.home);
          break;

        default:
          AppLogger.w('Unknown route: $route', tag: _tag);
          _navigateToTab(NavigationPage.home);
      }
    } catch (e, stackTrace) {
      AppLogger.e('handleDeepLink error', error: e, stackTrace: stackTrace, tag: _tag);
      _navigateToTab(NavigationPage.home);
    }
  }

  static String _parseRoute(Uri uri) {
    String route;
    if (uri.host.isNotEmpty) {
      route = uri.path.isNotEmpty ? '${uri.host}${uri.path}' : uri.host;
    } else {
      route = uri.path;
    }
    if (route.isNotEmpty && !route.startsWith('/')) {
      route = '/$route';
    }
    return route;
  }

  /// Navigate to a PageView tab (uses NavigationCubit)
  static void _navigateToTab(NavigationPage page) {
    AppLogger.d('Navigating to ${page.name} (index: ${page.pageIndex})', tag: _tag);

    final currentRoute = AppNavigation.currentRoute;

    // If on a detail screen, pop back to main navigation first
    if (currentRoute != null && currentRoute != AppRoutes.homeRoute) {
      AppNavigation.backUntil(AppRoutes.homeRoute);
    }

    // Use the cubit to switch tabs (same as drawer navigation)
    // fromDrawer: true uses jumpToPage for instant, reliable navigation
    sl<NavigationCubit>().navigateTo(page, fromDrawer: true);
  }

  /// Navigate to a standalone screen (not part of the PageView)
  static void _navigateToScreen(String route) {
    AppLogger.d('Navigating to standalone screen: $route', tag: _tag);
    AppNavigation.intent(route);
  }
}
```

### 4. Dependency Injection

Register `DeepLinkService` as a lazy singleton:

```dart
// lib/config/injection_container.dart
sl.registerLazySingleton<DeepLinkService>(() => DeepLinkService());
```

### 5. Initialize in main.dart

```dart
// In your app initialization
await sl<DeepLinkService>().initialize();
```

### 6. Mark App as Ready

After splash screen completes and user is on the main screen:

```dart
// In HomeScreen or after login completes
sl<DeepLinkService>().setAppFullyInitialized();
```

---

## Architecture

### Navigation Types

1. **PageView Tabs** - Screens in the main `PageView` (Home, Chat, Health Board, Profile)
   - Use `NavigationCubit.navigateTo()` to switch tabs
   - No need to recreate the screen, just change the page index

2. **Standalone Screens** - Screens pushed on top of `MainNavigationScreen` (Reminders, etc.)
   - Use `AppNavigation.intent()` to push the screen

### Why This Approach?

**Previous (broken) approach:**
```dart
// DON'T DO THIS - Causes race conditions
sl<NavigationCubit>().navigateTo(page, fromDrawer: false);
AppNavigation.intentWithClearAllRoutesWithData(AppRoutes.homeRoute, page.pageIndex);
```

This recreates the entire `MainNavigationScreen`, causing race conditions between the cubit state and `PageController`.

**Current (working) approach:**
```dart
// DO THIS - Same as drawer navigation
sl<NavigationCubit>().navigateTo(page, fromDrawer: true);
```

This reuses the existing `MainNavigationScreen` and lets the `BlocListener` handle the page change.

---

## Supported Deep Links

| Deep Link | Screen | Type |
|-----------|--------|------|
| `<myapp>://home` | Home tab | PageView |
| `<myapp>://chat` | Chat tab | PageView |
| `<myapp>://health/stats` | Health Board tab | PageView |
| `<myapp>://profile` | Profile tab | PageView |
| `<myapp>://reminders` | Reminders screen | Standalone |

### SuprSend Configuration

In SuprSend notification template, set the deep link URL:

```
<myapp>://profile
<myapp>://reminders
<myapp>://chat
```

---

## Common Issues & Solutions

### 1. App Crashes in Killed Mode

**Symptom:** `'_elements.contains(element)': is not true` assertion error

**Cause:** `app_links` tries to communicate via MethodChannel before Flutter engine is ready

**Solution:** Native-side delay in `MainActivity.kt`:
- Intercept deep link in `onCreate`
- Clear the intent temporarily
- Re-inject via `onNewIntent` after 4 seconds

### 2. Duplicate App Instances

**Symptom:** Two app instances in the app switcher

**Cause:** Wrong `launchMode` or `taskAffinity` in AndroidManifest.xml

**Solution:**
```xml
android:launchMode="singleTask"
<!-- Remove: android:taskAffinity="" -->
```

### 3. Unpredictable Tab Navigation

**Symptom:** Deep link to `/profile` sometimes lands on wrong tab

**Cause:** Race condition between `NavigationCubit` state and `PageController`

**Solution:** Use the same pattern as drawer navigation:
```dart
sl<NavigationCubit>().navigateTo(page, fromDrawer: true);
```

Don't recreate `MainNavigationScreen` for tab navigation.

### 4. URI Parsing Issues

**Symptom:** `<myapp>://profile` doesn't parse correctly

**Cause:** `uri.host` vs `uri.path` confusion

**Solution:** The `_parseRoute` method handles this:
```dart
static String _parseRoute(Uri uri) {
  String route;
  if (uri.host.isNotEmpty) {
    // <myapp>://profile -> host="profile", path=""
    route = uri.path.isNotEmpty ? '${uri.host}${uri.path}' : uri.host;
  } else {
    route = uri.path;
  }
  if (route.isNotEmpty && !route.startsWith('/')) {
    route = '/$route';
  }
  return route; // Returns "/profile"
}
```

### 5. Deep Link Not Received

**Symptom:** Tapping notification doesn't trigger deep link

**Checklist:**
- [ ] Intent filters in AndroidManifest.xml are correct
- [ ] `android:exported="true"` is set
- [ ] SuprSend notification template has correct deep link URL
- [ ] `DeepLinkService.initialize()` is called
- [ ] Stream listener is active

---

## Testing

### ADB Commands

Test deep links without sending actual notifications:

```bash
# Test profile deep link
adb shell am start -a android.intent.action.VIEW -d "<myapp>://profile" com.example.myapp

# Test chat deep link
adb shell am start -a android.intent.action.VIEW -d "<myapp>://chat" com.example.myapp

# Test reminders deep link
adb shell am start -a android.intent.action.VIEW -d "<myapp>://reminders" com.example.myapp

# Test health stats deep link
adb shell am start -a android.intent.action.VIEW -d "<myapp>://health/stats" com.example.myapp
```

### Test Scenarios

1. **Foreground:** App is open and visible
2. **Background:** App is in recent apps
3. **Killed:** App is not in recent apps (force stopped)

All three scenarios should work correctly.

### Debug Logging

Look for these log tags:
- `[DeepLinkService]` - Deep link reception and processing
- `[DeepLinkHandler]` - Route parsing and navigation
- `[navigation]` - AppNavigation operations
- `MainActivity` - Native Android logs (use `adb logcat | grep MainActivity`)

---

## File Locations

| File | Purpose |
|------|---------|
| `android/app/src/main/AndroidManifest.xml` | Intent filters |
| `android/app/src/main/kotlin/.../MainActivity.kt` | Native intent handling |
| `lib/core/services/deep_link_service.dart` | Flutter deep link processing |
| `lib/core/navigation/deep_link_handler.dart` | Route parsing and navigation |
| `lib/core/navigation/app_navigation.dart` | Navigation helper methods |
| `lib/core/cubit/navigation_cubit.dart` | PageView tab state management |

---

## Adding New Deep Links

### For PageView Tabs

1. Add case in `DeepLinkHandler.handleDeepLink()`:
   ```dart
   case '/new-tab':
     _navigateToTab(NavigationPage.newTab);
     break;
   ```

2. Ensure `NavigationPage` enum has the page

### For Standalone Screens

1. Add route in `AppRoutes`:
   ```dart
   static const String newScreenRoute = "/new_screen";
   ```

2. Register route in `routes.dart`

3. Add case in `DeepLinkHandler.handleDeepLink()`:
   ```dart
   case '/new-screen':
     _navigateToScreen(AppRoutes.newScreenRoute);
     break;
   ```

---

## Historical: Previous Complex Approach

This section documents the complex approach we initially implemented. It is kept for historical reference to help future developers understand what was tried and why it was unnecessary.

### What We Built (Unnecessary Complexity)

#### Complex MainActivity.kt (78 lines)

We implemented native intent interception with a 4-second delay:

```kotlin
// THIS WAS UNNECESSARY - Kept for historical reference
class MainActivity : FlutterFragmentActivity() {
    companion object {
        private const val DEEP_LINK_DELAY_MS = 4000L
    }
    
    private var pendingDeepLinkIntent: Intent? = null
    private var isFlutterReady = false
    private val handler = Handler(Looper.getMainLooper())
    
    override fun onCreate(savedInstanceState: Bundle?) {
        if (isDeepLinkIntent(intent)) {
            pendingDeepLinkIntent = Intent(intent)
            intent.data = null
            intent.action = Intent.ACTION_MAIN
        }
        
        super.onCreate(savedInstanceState)
        
        if (pendingDeepLinkIntent != null) {
            handler.postDelayed({
                isFlutterReady = true
                processPendingDeepLink()
            }, DEEP_LINK_DELAY_MS)
        }
    }
    // ... more complex logic
}
```

#### Complex DeepLinkService.dart (212 lines)

We implemented multiple flags and queuing mechanisms:

```dart
// THIS WAS UNNECESSARY - Kept for historical reference
class DeepLinkService {
  bool _isInitialized = false;
  Uri? _pendingInitialLink;
  bool _isProcessingDeepLink = false;
  bool _isAppFullyInitialized = false;
  String? lastError;

  Future<void> initialize() async {
    if (_isInitialized) return;
    try {
      await _handleInitialLink();
      _startListening();
      _isInitialized = true;
    } catch (e) {
      lastError = 'init: $e';
      _showErrorOnUI('DeepLink init failed: $e');
    }
  }

  void setAppFullyInitialized() {
    if (_isAppFullyInitialized) return;
    _isAppFullyInitialized = true;
    if (_pendingInitialLink != null) {
      processPendingLink();
    }
  }

  void processPendingLink() {
    if (_pendingInitialLink == null) return;
    if (!AppNavigation.isNavigatorReady) return;
    if (_isProcessingDeepLink) return;
    
    _isProcessingDeepLink = true;
    // ... complex processing
    _isProcessingDeepLink = false;
  }
  // ... 150+ more lines
}
```

### Why This Complexity Was Added

1. **Killed-mode crashes** - We saw `'_elements.contains(element)': is not true` errors
2. **We didn't know about `flutter_deeplinking_enabled`** - This meta-data flag was the actual fix
3. **We assumed the problem was timing** - So we added delays and queuing
4. **It worked, so we kept it** - But it was solving the wrong problem

### The Real Root Cause

Flutter has a **built-in deep link handler** that was conflicting with the `app_links` package. Both were trying to process the same intent, causing race conditions and crashes.

The fix was not complex native code or Dart queuing - it was simply telling Flutter to disable its built-in handler:

```xml
<meta-data android:name="flutter_deeplinking_enabled" android:value="false" />
```

### Lessons Learned

| What We Thought | Reality |
|-----------------|---------|
| Native delay (4s) is required for killed mode | NOT required - `app_links` handles it |
| Complex queuing prevents race conditions | NOT needed - simple `_ready` flag works |
| Multiple initialization flags add safety | Unnecessary complexity |
| The crash was a timing issue | The crash was a **conflict** between two handlers |

### How to Avoid This in the Future

1. **Read the package documentation carefully** - `app_links` mentions `flutter_deeplinking_enabled`
2. **Check official examples first** - They show the simple approach
3. **Don't add complexity to fix symptoms** - Find the root cause
4. **Test the simplest solution first** - Then add complexity only if needed

---

*Last Updated: January 2026*
*Simplified from complex approach after POC testing confirmed official method works*
