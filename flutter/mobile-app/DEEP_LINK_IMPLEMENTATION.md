# Deep Link Implementation Guide

Complete guide for deep linking with SuprSend notifications in the <AppName> app.

---

## Overview

Deep links allow users to tap on a notification and navigate directly to a specific screen in the app.

| Component | Technology |
|-----------|------------|
| Push Notifications | SuprSend |
| Deep Link Handling | app_links (Flutter) |
| URL Scheme | `<myapp>://` |
| Platforms | Android & iOS |

---

## Architecture

```
┌─────────────────────┐
│  SuprSend Backend   │
│  (sends push with   │
│   deep link URL)    │
└──────────┬──────────┘
           │
           ▼
┌─────────────────────┐     ┌─────────────────────┐
│      Android        │     │        iOS          │
│  Intent Filter      │     │  SuprSendDeepLink   │
│  (<myapp>://)        │     │     Delegate        │
└──────────┬──────────┘     └──────────┬──────────┘
           │                           │
           ▼                           ▼
┌─────────────────────────────────────────────────┐
│              app_links (Flutter)                │
│            uriLinkStream.listen()               │
└──────────────────────┬──────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────┐
│              DeepLinkService                    │
│         (queues until app ready)                │
└──────────────────────┬──────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────┐
│              DeepLinkHandler                    │
│       (routes to screens/tabs)                  │
└─────────────────────────────────────────────────┘
```

---

## Supported Deep Links

| Deep Link | Screen | Type |
|-----------|--------|------|
| `<myapp>://home` | Home tab | PageView tab |
| `<myapp>://chat` | Chat tab | PageView tab |
| `<myapp>://health/stats` | Health Board tab | PageView tab |
| `<myapp>://profile` | Profile tab | PageView tab |
| `<myapp>://reminders` | Reminders screen | Standalone |

---

## Android Setup

### 1. AndroidManifest.xml

**Critical: Disable Flutter's built-in deep link handler** to avoid conflict with `app_links`:

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
    
    <!-- Deep link intent filter for <myapp>:// scheme -->
    <intent-filter android:autoVerify="true">
        <action android:name="android.intent.action.VIEW" />
        <category android:name="android.intent.category.DEFAULT" />
        <category android:name="android.intent.category.BROWSABLE" />
        <data android:scheme="<app>" android:host="*" />
    </intent-filter>
</activity>
```

**Key points:**
- `flutter_deeplinking_enabled=false` prevents crashes from Flutter/app_links conflict
- `singleTask` prevents duplicate app instances
- `android:exported="true"` required for deep link handling

### 2. MainActivity.kt

Minimal implementation - no native handling needed:

```kotlin
package com.example.myapp

import io.flutter.embedding.android.FlutterFragmentActivity

class MainActivity : FlutterFragmentActivity()
```

### 3. How Android Works

1. User taps SuprSend notification with `<myapp>://chat`
2. Android system launches app with `Intent.ACTION_VIEW` + data URI
3. Intent filter on MainActivity catches it
4. `app_links` plugin receives the URI
5. Flutter's `DeepLinkService` processes it

---

## iOS Setup

### 1. Info.plist

**Add custom URL scheme and disable Flutter deep linking:**

```xml
<!-- Custom URL scheme -->
<key>CFBundleURLTypes</key>
<array>
    <dict>
        <key>CFBundleTypeRole</key>
        <string>Editor</string>
        <key>CFBundleURLSchemes</key>
        <array>
            <string><app></string>
        </array>
    </dict>
</array>

<!-- CRITICAL: Disable Flutter's built-in deep link handler -->
<key>FlutterDeepLinkingEnabled</key>
<false/>
```

### 2. AppDelegate.swift

**Implement SuprSendDeepLinkDelegate:**

```swift
import Flutter
import UIKit
import SuprSendSdk

@main
@objc class AppDelegate: FlutterAppDelegate, SuprSendDeepLinkDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    
    // Initialize SuprSend SDK
    let suprSendConfiguration = SuprSendSDKConfiguration(
      withKey: "YOUR_KEY",
      secret: "YOUR_SECRET",
      baseUrl: nil
    )
    SuprSend.shared.configureWith(configuration: suprSendConfiguration, launchOptions: launchOptions)
    SuprSend.shared.setDeepLinkDelegate(self)  // <-- Register delegate
    
    registerForPushNotifications()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // MARK: - SuprSendDeepLinkDelegate

  func shouldHandleSuprSendDeepLink(_ url: URL) -> Bool {
    print("[DeepLink] SuprSend received URL: \(url)")
    // Open the URL - iOS routes it back via application(_:open:options:)
    // which app_links plugin listens to
    UIApplication.shared.open(url, options: [:], completionHandler: nil)
    return false  // We handled it ourselves
  }
  
  // ... rest of AppDelegate
}
```

### 3. Why SuprSendDeepLinkDelegate is Required

By default, SuprSend SDK only handles **HTTP** deep links. For custom schemes like `<myapp>://`:

1. Implement `SuprSendDeepLinkDelegate`
2. Call `SuprSend.shared.setDeepLinkDelegate(self)`
3. In `shouldHandleSuprSendDeepLink`:
   - Return `false` so SuprSend doesn't consume it
   - Call `UIApplication.shared.open(url)` to trigger iOS URL handling
   - `app_links` plugin receives it via `application(_:open:options:)`

### 4. How iOS Works

1. User taps SuprSend notification with `<myapp>://chat`
2. SuprSend SDK calls `shouldHandleSuprSendDeepLink`
3. We call `UIApplication.shared.open(url)` and return `false`
4. iOS triggers `application(_:open:options:)` on app delegate
5. `app_links` plugin receives the URL
6. Flutter's `DeepLinkService` processes it

---

## Flutter Setup

### 1. DeepLinkService

**Location:** `lib/core/services/deep_link_service.dart`

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

### 2. DeepLinkHandler

**Location:** `lib/core/navigation/deep_link_handler.dart`

```dart
class DeepLinkHandler {
  static const String _scheme = '<app>';
  static const String _tag = 'DeepLinkHandler';

  static void handleDeepLink(Uri uri) {
    try {
      if (uri.scheme != _scheme) {
        _navigateToTab(NavigationPage.home);
        return;
      }

      final route = _parseRoute(uri);

      switch (route) {
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
        case '/reminders':
          _navigateToScreen(AppRoutes.remindersRoute);
          break;
        default:
          _navigateToTab(NavigationPage.home);
      }
    } catch (e) {
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

  static void _navigateToTab(NavigationPage page) {
    final currentRoute = AppNavigation.currentRoute;
    if (currentRoute != null && currentRoute != AppRoutes.homeRoute) {
      AppNavigation.backUntil(AppRoutes.homeRoute);
    }
    sl<NavigationCubit>().navigateTo(page, fromDrawer: true);
  }

  static void _navigateToScreen(String route) {
    if (AppNavigation.currentRoute == route) return;
    AppNavigation.intent(route);
  }
}
```

### 3. Initialization in Screens

**LoginScreen and HomeScreen:**

```dart
@override
void initState() {
  super.initState();
  _processDeepLinkWhenStable();
}

void _processDeepLinkWhenStable() {
  Future.delayed(const Duration(milliseconds: 500), () {
    if (!mounted) return;
    final deepLinkService = sl<DeepLinkService>();
    deepLinkService.initialize();
    deepLinkService.setReady();
  });
}
```

---

## SuprSend Configuration

In SuprSend notification template, set the deep link URL in the **Launch URL** field:

```
<myapp>://chat
<myapp>://profile
<myapp>://reminders
<myapp>://health/stats
```

---

## Testing

### Android

```bash
adb shell am start -a android.intent.action.VIEW -d "<myapp>://chat" com.example.myapp
adb shell am start -a android.intent.action.VIEW -d "<myapp>://profile" com.example.myapp
adb shell am start -a android.intent.action.VIEW -d "<myapp>://reminders" com.example.myapp
```

### iOS

```bash
xcrun simctl openurl booted "<myapp>://chat"
xcrun simctl openurl booted "<myapp>://profile"
xcrun simctl openurl booted "<myapp>://reminders"
```

---

## Debugging

### Check Xcode Logs (iOS)

Look for:
```
[DeepLink] SuprSend received URL: <myapp>://chat
```

### Check Flutter Logs

Look for:
```
[DeepLinkService] Deep link received: <myapp>://chat
[DeepLinkHandler] Deep link received: <myapp>://chat
[DeepLinkHandler] Parsed route: /chat
[DeepLinkHandler] Navigating to chat (index: 1)
```

---

## Common Issues

### 1. App Crashes on Android (Killed State)

**Cause:** Flutter's built-in deep link handler conflicts with `app_links`

**Solution:** Add to AndroidManifest.xml:
```xml
<meta-data
    android:name="flutter_deeplinking_enabled"
    android:value="false"
    />
```

### 2. Deep Link Not Working on iOS

**Cause:** SuprSend SDK only handles HTTP links by default

**Solution:** Implement `SuprSendDeepLinkDelegate` and call `UIApplication.shared.open(url)`

### 3. Duplicate App Instances

**Cause:** Wrong `launchMode` in AndroidManifest

**Solution:** Use `android:launchMode="singleTask"`

### 4. Navigation to Wrong Tab

**Cause:** Race condition between cubit and PageController

**Solution:** Use `sl<NavigationCubit>().navigateTo(page, fromDrawer: true)` for instant navigation

---

## File Locations

| File | Purpose |
|------|---------|
| `android/app/src/main/AndroidManifest.xml` | Android intent filters |
| `android/app/src/main/kotlin/.../MainActivity.kt` | Android entry point |
| `ios/Runner/Info.plist` | iOS URL scheme + FlutterDeepLinkingEnabled |
| `ios/Runner/AppDelegate.swift` | iOS SuprSendDeepLinkDelegate |
| `lib/core/services/deep_link_service.dart` | Flutter deep link listener |
| `lib/core/navigation/deep_link_handler.dart` | Flutter route parsing |

---

## Adding New Deep Links

1. **Add route in DeepLinkHandler:**

```dart
case '/new-screen':
  _navigateToScreen(AppRoutes.newScreenRoute);
  break;
```

2. **Configure in SuprSend:**
   - Set Launch URL: `<myapp>://new-screen`

3. **Test:**
```bash
# Android
adb shell am start -a android.intent.action.VIEW -d "<myapp>://new-screen" com.example.myapp

# iOS
xcrun simctl openurl booted "<myapp>://new-screen"
```

---

## References

- [SuprSend iOS APNS Push Integration](https://docs.suprsend.com/docs/ios-apns-push)
- [app_links Flutter Package](https://pub.dev/packages/app_links)
- [Apple: Defining a Custom URL Scheme](https://developer.apple.com/documentation/xcode/defining-a-custom-url-scheme-for-your-app)
- [Flutter Deep Linking](https://docs.flutter.dev/ui/navigation/deep-linking)
