# чатор Android App - Build Guide

Custom Element Android app for чатор.

---

## ⚠️ Requirements

**You need:**
- Computer (Linux/Windows/Mac)
- 16GB+ RAM recommended
- 50GB+ free disk space
- Android Studio Hedgehog (2023.1.1) or newer
- JDK 17+
- Android SDK (API 34+)
- Google Play Developer Account ($25 one-time for Play Store)

**Time:** 1-2 hours for first build

---

## Step 1: Fork Element Android

1. Go to https://github.com/element-hq/element-android
2. Click **Fork** → Create fork under your GitHub account
3. Clone YOUR fork:

```bash
git clone https://github.com/YOUR_USERNAME/element-android.git chator-android
cd chator-android
```

---

## Step 2: Apply чатор Branding

### 2.1 Update App Name

**File:** `vectorapp/src/main/res/values/strings.xml`

Change:
```xml
<string name="app_name">Element</string>
```
To:
```xml
<string name="app_name">чатор</string>
```

**For Russian localization:**
Create/edit `vectorapp/src/main/res/values-ru/strings.xml`:
```xml
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <string name="app_name">чатор</string>
</resources>
```

### 2.2 Replace App Icon

1. Download чатор logo: https://nopaste.net/chator
2. Open Android Studio → **File → Image Asset**
3. Select your logo PNG
4. Generate all icon variants
5. This will replace icons in:
   - `vectorapp/src/main/res/mipmap-*/ic_launcher.png`
   - `vectorapp/src/main/res/mipmap-*/ic_launcher_round.png`
   - `vectorapp/src/main/res/mipmap-*/ic_launcher_foreground.png`

**OR manually:**
```bash
# Copy logo to project
cp /path/to/chator-logo.png chator-android/app/src/main/res/drawable/chator_logo.png

# Use Image Asset Studio in Android Studio to generate all sizes
```

### 2.3 Update Package Name (Optional but Recommended)

If you want a unique package name (for Play Store):

**File:** `vectorapp/build.gradle`

Change:
```gradle
android {
    defaultConfig {
        applicationId "im.vector.app"
    }
}
```
To:
```gradle
android {
    defaultConfig {
        applicationId "im.chator.android"
    }
}
```

**Then refactor the package:**
1. Open Android Studio
2. Right-click `im.vector` package → **Refactor → Rename**
3. Change to `im.chator`
4. Let Android Studio update all references

### 2.4 Set Default Homeserver

**File:** `vectorapp/src/main/java/im/vector/app/features/home/AutoJoin.kt` (or search for default server)

Find and change:
```kotlin
const val DEFAULT_HOME_SERVER = "https://chator.k.vu"
```

**OR** in `vectorapp/src/main/res/values/strings.xml`:
```xml
<string name="default_homeserver_url">https://chator.k.vu</string>
```

### 2.5 Update Build Configuration

**File:** `vectorapp/build.gradle`

Update version info:
```gradle
android {
    defaultConfig {
        versionCode 1
        versionName "1.0.0"
        applicationId "im.chator.android"
    }
}
```

---

## Step 3: Build with Gradle

### First Time Setup

```bash
# Install dependencies (takes 10-20 min)
./gradlew dependencies

# Sync Gradle
./gradlew sync
```

### Build Debug APK (for testing)

```bash
./gradlew assembleDebug
```

Output: `vectorapp/build/outputs/apk/debug/vector-app-debug.apk`

### Build Release APK (for distribution)

**You need a signing key:**

```bash
# Generate keystore (keep this safe!)
keytool -genkey -v -keystore chator-release.keystore \
  -alias chator -keyalg RSA -keysize 2048 -validity 10000

# Build signed release
./gradlew assembleRelease \
  -Pandroid.injected.signing.store.file=chator-release.keystore \
  -Pandroid.injected.signing.store.password=YOUR_PASSWORD \
  -Pandroid.injected.signing.key.alias=chator \
  -Pandroid.injected.signing.key.password=YOUR_PASSWORD
```

Output: `vectorapp/build/outputs/apk/release/vector-app-release.apk`

### Build Android App Bundle (for Play Store)

```bash
./gradlew bundleRelease \
  -Pandroid.injected.signing.store.file=chator-release.keystore \
  -Pandroid.injected.signing.store.password=YOUR_PASSWORD \
  -Pandroid.injected.signing.key.alias=chator \
  -Pandroid.injected.signing.key.password=YOUR_PASSWORD
```

Output: `vectorapp/build/outputs/bundle/release/vector-app-release.aab`

---

## Step 4: Build in Android Studio

1. Open Android Studio
2. **File → Open** → Select `chator-android` folder
3. Wait for Gradle sync (10-20 min first time)
4. Select **Build → Make Project** (or ⌘/Ctrl+F9)
5. Wait for build to complete

**To run on emulator/phone:**
1. Connect Android device via USB (enable USB debugging)
2. Or create emulator: **Tools → Device Manager**
3. Click **Run** (▶️) or ⌘/Ctrl+R
4. Select your device

---

## Step 5: Test the App

1. Install APK on your device
2. Open чатор app
3. Should show:
   - чатор logo on splash screen
   - чатор app name
   - Pre-configured server: `chator.k.vu`
4. Login/register with your Matrix account

---

## Step 6: Publish to Google Play

### Prerequisites:
- Google Play Developer Account ($25 one-time)
- Signed release APK or AAB
- App screenshots (phone, tablet, 7-inch tablet)
- Feature graphic (1024x500)
- Privacy policy URL

### Upload Process:

1. Go to https://play.google.com/console
2. **Create app**
3. Fill in:
   - **App name:** чатор
   - **Short description:** "Messenger for Russian teens"
   - **Full description:** (write compelling copy)
   - **Category:** Communication
   - **Content rating:** Complete questionnaire
   - **Target audience:** Teens (13-17)
4. **Store listing:**
   - Upload screenshots (min 2 for phone)
   - Upload feature graphic
   - Upload app icon (512x512)
5. **App content:**
   - Privacy policy
   - App access (declare permissions)
   - Ads declaration (none)
   - Content rating
6. **Pricing & distribution:**
   - Select FREE
   - Choose countries (Russia + others)
7. **Upload release:**
   - Upload signed AAB
   - Fill release notes
8. **Submit for review** (1-7 days typically)

---

## Quick Reference

**Build time:** 15-30 min
**App size:** ~80-120 MB
**Minimum Android:** 8.0 (API 26)
**Target SDK:** 34 (Android 14)

**Key files to modify:**
| File | Purpose |
|------|---------|
| `vectorapp/src/main/res/values/strings.xml` | App name, strings |
| `vectorapp/src/main/res/values-ru/strings.xml` | Russian translations |
| `vectorapp/build.gradle` | Package name, version |
| `vectorapp/src/main/res/mipmap-*/` | App icons |
| `vectorapp/src/main/AndroidManifest.xml` | Permissions, metadata |

---

## Troubleshooting

**Gradle sync fails:**
```bash
./gradlew clean
./gradlew build --refresh-dependencies
```

**Build fails with "SDK not found":**
- Open Android Studio → **Tools → SDK Manager**
- Install Android SDK Platform 34
- Install Build-Tools 34.x

**Out of memory during build:**
Edit `gradle.properties`:
```properties
org.gradle.jvmargs=-Xmx4096m -XX:MaxMetaspaceSize=1024m
```

**App crashes on launch:**
- Check Logcat in Android Studio
- Verify default homeserver is accessible
- Check network permissions in manifest

**Icons don't update:**
- **Build → Clean Project**
- Uninstall app from device
- Rebuild

---

## CI/CD Setup (Optional)

For automated builds on every commit:

**GitHub Actions:**
Create `.github/workflows/build.yml`:
```yaml
name: Build чатор Android

on: [push, pull_request]

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-java@v4
        with:
          java-version: '17'
          distribution: 'temurin'
      - name: Build Debug APK
        run: ./gradlew assembleDebug
      - uses: actions/upload-artifact@v4
        with:
          name: app-debug
          path: vectorapp/build/outputs/apk/debug/*.apk
```

---

## Next Steps

After Android build works:
1. Set up automated builds (GitHub Actions, Bitrise, Codemagic)
2. Configure beta testing (Google Play Internal Testing)
3. Build iOS version (see `chator/ios/README.md`)
4. Set up crash reporting (Sentry, Firebase Crashlytics)

---

**Questions?** Check Element Android docs: https://github.com/element-hq/element-android/blob/develop/docs/development.md

Удачи! 🥞
