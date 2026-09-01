# <AppName> AI -- Build, Run & Release Guide

> **Platform:** Android & iOS | **Package:** `com.example.myapp` | **Firebase:** `<firebase-project-dev>`

---

## Table of Contents

**Build & Release**

1. [Prerequisites](#1-prerequisites)
2. [Environment Switching](#2-environment-switching)
3. [Run](#3-run)
4. [Build](#4-build)
5. [Release -- Android (Play Store)](#5-release--android-play-store)
6. [Release -- iOS (App Store / TestFlight)](#6-release--ios-app-store--testflight)
7. [Version Management](#7-version-management)
8. [Firebase Crashlytics -- Symbol Upload](#8-firebase-crashlytics--symbol-upload)
9. [Post-Release Verification](#9-post-release-verification)

**Branching & Practices**

10. [Branching Strategy](#10-branching-strategy)
11. [Best Practices](#11-best-practices)

**Common**

12. [Android Signing](#12-android-signing)
13. [Output Paths](#13-output-paths)
14. [Troubleshooting](#14-troubleshooting)
15. [Quick Reference](#15-quick-reference)

---

# Build & Release

## 1. Prerequisites

| Requirement | Version / Details |
|-------------|-------------------|
| Flutter SDK | `^3.9.2` |
| Dart SDK | Bundled with Flutter |
| Android minSdk | 26 (Android 8.0) |
| iOS deployment target | 15.6 |
| Xcode | Latest stable |
| CocoaPods | `gem install cocoapods` |
| Apple Developer Team | `JPS5DGWE8T` |
| Firebase CLI | See below |

### First-time setup

```bash
# 1. Clone and install dependencies
git clone <repo-url>
cd <app>-mobile
flutter pub get

# 2. iOS pods
cd ios && pod install && cd ..

# 3. Android signing -- see Section 12

# 4. Firebase CLI (needed for Crashlytics symbol upload)
curl -sL https://firebase.tools | bash
firebase login
```

### Environment files

Two env files exist in the project root. They are **gitignored** and contain only base URLs (secrets are fetched from the backend at runtime).

| File | Purpose | API base URL |
|------|---------|-------------|
| `env.dev` | Development / staging | Dev server |
| `env.prod` | Production | Production server |

> New developer? Copy `env.dev.example` / `env.prod.example` to `env.dev` / `env.prod` and fill in the URLs.

Env is selected by **entry point** (no code change):

| Entry point | Env file | Use for |
|-------------|----------|---------|
| `lib/main.dart` (default) | `env.prod` | Release builds, prod testing |
| `lib/main_dev.dart` | `env.dev` | Dev with API logs |
| `lib/main_dev_api_log_off.dart` | `env.dev` | Dev with API logs off |

`flutter run` and `flutter build` use `main.dart` by default, so prod is the default.

---

## 2. Environment and entry points

- **Prod (default):** `lib/main.dart` loads `env.prod`. Use for release builds and prod testing.
- **Dev with API logs:** `flutter run -t lib/main_dev.dart` loads `env.dev` and enables Dio API logging in debug.
- **Dev without API logs:** `flutter run -t lib/main_dev_api_log_off.dart` loads `env.dev` with API logs disabled (e.g. performance testing, less console noise).

No manual edit in `main.dart` is needed; choose the entry point when running or building.

---

## 3. Run

### Prod (default)

```bash
flutter run
```

Uses `lib/main.dart` → `env.prod`.

### Dev with API logs

```bash
flutter run -t lib/main_dev.dart
```

### Dev without API logs

```bash
flutter run -t lib/main_dev_api_log_off.dart
```

### Pick a specific device

```bash
flutter devices
flutter run -d <device_id>
```

### Run on iOS simulator

```bash
open -a Simulator
flutter run
```

---

## 4. Build

### Android -- Normal (no obfuscation)

```bash
# APK
flutter build apk

# App Bundle (for Play Store)
flutter build appbundle
```

### Android -- Obfuscated (use for release)

```bash
# APK
flutter build apk --obfuscate --split-debug-info=build/symbols

# App Bundle (for Play Store)
flutter build appbundle --obfuscate --split-debug-info=build/symbols
```

### iOS -- Normal (no obfuscation)

```bash
flutter build ios
```

### iOS -- Obfuscated (use for release)

```bash
flutter build ios --obfuscate --split-debug-info=build/symbols
```

> After any obfuscated build, `build/symbols/` contains the debug symbols. Upload these to Crashlytics (Section 8) and archive them before the next build overwrites them.

---

## 5. Release -- Android (Play Store)

### Step-by-step

```bash
# 1. Bump version in pubspec.yaml (see Section 7)

# 2. Clean build
flutter clean && flutter pub get

# 3. Build obfuscated AAB (uses main.dart → env by default)
flutter build appbundle --obfuscate --split-debug-info=build/symbols

# 4. Archive symbols for this version
mkdir -p release_symbols/$(grep 'version:' pubspec.yaml | head -1 | awk '{print $2}')
cp -r build/symbols/ release_symbols/$(grep 'version:' pubspec.yaml | head -1 | awk '{print $2}')/

# 5. Upload symbols to Crashlytics
firebase crashlytics:symbols:upload \
  --app=<FIREBASE_ANDROID_APP_ID> \
  build/symbols

# 6. Upload AAB to Google Play Console
#    File: build/app/outputs/bundle/release/app-release.aab
```

---

## 6. Release -- iOS (App Store / TestFlight)

### Step-by-step

```bash
# 1. Bump version in pubspec.yaml (see Section 7)

# 2. Clean build
flutter clean && flutter pub get
cd ios && pod install && cd ..

# 3. Build obfuscated iOS (uses main.dart → env by default)
flutter build ios --obfuscate --split-debug-info=build/symbols

# 4. Archive symbols for this version
mkdir -p release_symbols/$(grep 'version:' pubspec.yaml | head -1 | awk '{print $2}')
cp -r build/symbols/ release_symbols/$(grep 'version:' pubspec.yaml | head -1 | awk '{print $2}')/

# 5. Upload symbols to Crashlytics
firebase crashlytics:symbols:upload \
  --app=<FIREBASE_IOS_APP_ID> \
  build/symbols
```

### Distribute via Xcode

6. Open `ios/Runner.xcworkspace` in Xcode
7. Select **Runner** target, verify version/build number matches `pubspec.yaml`
8. Select **Any iOS Device (arm64)** as destination
9. **Product > Archive**
10. Wait for archive to complete
11. **Window > Organizer** > select the latest archive
12. Click **Distribute App**
13. Choose distribution method:
    - **App Store Connect** for TestFlight / production release
    - **Ad Hoc** for internal testing (requires provisioned UDIDs)
14. Follow the prompts, select your team and signing certificate
15. Click **Upload** (for App Store Connect) or **Export** (for Ad Hoc IPA)

> Xcode handles code signing, entitlements, and IPA creation during the archive/distribute flow. No need for manual `xcodebuild` commands unless automating CI.

---

## 7. Version Management

### Format

In `pubspec.yaml`:

```yaml
version: 1.0.7+25
#         ^^^^^  ^^
#         |      |
#         |      +-- buildNumber (versionCode on Android, CFBundleVersion on iOS)
#         +-- versionName (displayed to users)
```

### Rules

- **versionName** (`1.0.7`): Bump for user-visible changes. Follow semver.
- **buildNumber** (`+25`): Must increment for EVERY store upload. Play Store rejects duplicate versionCodes. App Store rejects duplicate build numbers for the same version.
- iOS reads both values from `pubspec.yaml` automatically.
- Android reads both values from `pubspec.yaml` via `flutter.versionCode` and `flutter.versionName` in `build.gradle.kts`.

### Before every release

```yaml
# Before:
version: 1.0.7+25

# After (patch bump + new build number):
version: 1.0.8+26
```

---

## 8. Firebase Crashlytics -- Symbol Upload

### Why this matters

When you build with `--obfuscate`, Dart symbols are stripped. Crashlytics shows raw memory addresses instead of file names and line numbers:

```
# Without symbols (useless):
_kDartIsolateSnapshotInstructions+0x792d13

# With symbols (actionable):
StringFunctions.capitalizeFirstLetter (string_extensions.dart:126)
```

### Firebase App IDs

| Platform | App ID |
|----------|--------|
| Android | `<FIREBASE_ANDROID_APP_ID>` |
| iOS | `<FIREBASE_IOS_APP_ID>` |

### Upload after every obfuscated build

```bash
# Android
firebase crashlytics:symbols:upload \
  --app=<FIREBASE_ANDROID_APP_ID> \
  build/symbols

# iOS
firebase crashlytics:symbols:upload \
  --app=<FIREBASE_IOS_APP_ID> \
  build/symbols
```

### Archive symbols per version

The `build/symbols/` folder is overwritten on every build. Archive before the next build:

```bash
cp -r build/symbols/ release_symbols/<version>/
```

### Enable Firebase Analytics debug mode (Android)

```bash
# Existing script in the project:
./scripts/enable_firebase_analytics_debug_android.sh

# Or manually:
adb shell setprop debug.firebase.analytics.app com.example.myapp
```

---

## 9. Post-Release Verification

After uploading to Play Store / App Store Connect:

### Crashlytics

1. Open Firebase Console > Crashlytics
2. Verify the new app version appears
3. If a crash occurs, check that the stack trace shows **readable file names and line numbers** (not memory addresses)
4. If traces are still obfuscated, you forgot to upload symbols -- re-upload from `release_symbols/<version>/`

### Environment

1. Install the release build on a test device
2. Verify it hits the **production API** (not dev)
3. Check login, health check-in, and core flows work against prod

### Common mistakes

| Mistake | Symptom | Fix |
|---------|---------|-----|
| Built release with `-t lib/main_dev.dart` | Release hits dev API | Build without `-t` (default is main.dart → prod) |
| Forgot to upload symbols | Crashlytics shows memory addresses | Upload from `release_symbols/` |
| Forgot to bump build number | Store rejects upload | Increment `+N` in pubspec and rebuild |
| Want dev but ran `flutter run` | Dev run hits prod API | Use `flutter run -t lib/main_dev.dart` |

---

# Branching & Practices

## 10. Branching Strategy

```
main (production -- only merged from dev via PR)
 └── dev (integration -- all feature PRs merge here)
      ├── dev-g (Gautam's working branch)
      ├── dev-sourav (Sourav's working branch)
      ├── feature/xxx (feature branches, from dev)
      ├── fix/xxx (bug fixes, from dev)
      └── hotfix/xxx (urgent prod fixes, from main, merge back to both)
```

### Naming convention

| Prefix | Use for | Branch from |
|--------|---------|-------------|
| `feature/<name>` | New features | `dev` |
| `fix/<name>` | Bug fixes | `dev` |
| `hotfix/<name>` | Urgent production fixes | `main` (merge back to `main` AND `dev`) |
| `dev-<person>` | Personal working branches | `dev` (merge to `dev` via PR) |

### Rules

- `main` is always release-ready. Only `dev -> main` PRs after testing.
- All PRs go to `dev` first. Never push directly to `main`.
- Delete branches after merge (keep the repo clean).
- Hotfixes branch from `main`, get merged to both `main` and `dev`.

### Release flow

```
1. Feature branches → PR to dev → merge
2. When dev is stable → PR from dev to main → merge
3. Build release from main (or dev if hotfix cycle is fast)
4. Tag the release: git tag -a v1.2.1 -m "Release 1.2.1"
```

---

## 11. Best Practices

### Build & release checklist

- Always `flutter clean && flutter pub get` before release builds
- Always build with `--obfuscate --split-debug-info=build/symbols`
- Always upload Crashlytics symbols after every obfuscated build (Section 8)
- Always bump version + build number in `pubspec.yaml` before release (Section 7)
- Always archive symbols before the next build: `cp -r build/symbols/ release_symbols/<version>/`
- Never build release with `-t lib/main_dev.dart` (that points to dev API)

### Security

- Never commit `env.dev` or `env.prod` (gitignored). They contain base URLs only; secrets come from the backend API at runtime.
- Never commit `key.properties` or `.jks` keystore files (gitignored).
- Never hardcode API keys, tokens, or secrets in Dart code.
- Use `AppLogger` instead of `print()` or `debugPrint()` -- AppLogger respects `kDebugMode`.
- Wrap debug-only code in `if (kDebugMode)` checks.

### Code hygiene

- Run `flutter analyze` before pushing -- zero warnings in CI.
- Use full package imports (`package:<AppName>_AI/...`), never relative imports (`../`).
- Keep widget files under ~100 lines, screen files under ~450 lines.
- Register Cubits as Factory, everything else as Singleton in GetIt.

### Git hygiene

- Write meaningful commit messages (what changed and why).
- Delete feature branches after merge.
- Keep PRs small and focused -- one feature or fix per PR.
- Review before merging to `dev`; test before merging `dev` to `main`.

---

# Common

## 12. Android Signing

Release builds require a keystore and `android/key.properties`.

### key.properties template

Create `android/key.properties` (gitignored):

```properties
storePassword=<password>
keyPassword=<password>
keyAlias=<alias>
storeFile=<path-to-keystore.jks>
```

- Get the keystore file and credentials from the team lead or secure storage.
- The `storeFile` path is relative to `android/app/`.
- If `key.properties` is missing, the Gradle build will fail with: `key.properties not found`.

---

## 13. Output Paths

| Build | Output path |
|-------|-------------|
| Android APK | `build/app/outputs/flutter-apk/app-release.apk` |
| Android AAB | `build/app/outputs/bundle/release/app-release.aab` |
| iOS app | `build/ios/iphoneos/Runner.app` |
| iOS archive | Created by Xcode in Organizer |
| Symbols (all obfuscated builds) | `build/symbols/` |
| Archived symbols | `release_symbols/<version>/` |

---

## 14. Troubleshooting

| Problem | Solution |
|---------|----------|
| Build fails after dependency change | `flutter clean && flutter pub get` |
| iOS build fails after plugin update | `cd ios && pod install && cd ..` |
| `key.properties not found` | Create from template (Section 12), get keystore from team |
| Crashlytics shows memory addresses | Upload symbols: `firebase crashlytics:symbols:upload --app=<APP_ID> build/symbols` |
| Wrong API environment in release | Do not pass `-t lib/main_dev.dart` when building release; default entry is prod |
| Play Store rejects AAB | Forgot to increment `+buildNumber` in pubspec.yaml |
| App Store rejects build | Duplicate build number -- increment and rebuild |
| iOS pods out of sync | `cd ios && pod deintegrate && pod install && cd ..` |
| Stale cache after branch switch | `flutter clean && flutter pub get && cd ios && pod install && cd ..` |
| Xcode "No signing certificate" | Xcode > Settings > Accounts > re-add Apple ID, download certificates |

---

## 15. Quick Reference

### Commands (no flavors)

| Action | Command |
|--------|---------|
| Run (prod, default) | `flutter run` |
| Run (dev, with API logs) | `flutter run -t lib/main_dev.dart` |
| Run (dev, no API logs) | `flutter run -t lib/main_dev_api_log_off.dart` |
| Build APK | `flutter build apk` |
| Build AAB | `flutter build appbundle` |
| Build APK (obfuscated) | `flutter build apk --obfuscate --split-debug-info=build/symbols` |
| Build AAB (obfuscated) | `flutter build appbundle --obfuscate --split-debug-info=build/symbols` |
| Build iOS | `flutter build ios` |
| Build iOS (obfuscated) | `flutter build ios --obfuscate --split-debug-info=build/symbols` |
| Upload symbols (Android) | `firebase crashlytics:symbols:upload --app=<FIREBASE_ANDROID_APP_ID> build/symbols` |
| Upload symbols (iOS) | `firebase crashlytics:symbols:upload --app=<FIREBASE_IOS_APP_ID> build/symbols` |
| Clean | `flutter clean && flutter pub get` |

### Firebase App IDs

| Platform | App ID |
|----------|--------|
| Android | `<FIREBASE_ANDROID_APP_ID>` |
| iOS | `<FIREBASE_IOS_APP_ID>` |
