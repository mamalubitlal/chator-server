# чатор Mobile Apps

Custom branded Element mobile apps for iOS and Android.

---

## 📱 Quick Start

**Option A: Official Element (Recommended for Launch)**
- Users download Element from App Store / Google Play
- Enter `https://chator.k.vu` as server
- **Cost:** $0
- **Time:** Works today

**Option B: Custom чатор Apps (What You're Building)**
- Full чатор branding everywhere
- Pre-configured server
- Your own app listings
- **Cost:** $124 upfront ($99 Apple + $25 Google)
- **Time:** 10-20 hours setup

---

## 📂 Project Structure

```
chator/
├── ios/           # iOS build guide & configs
├── android/       # Android build guide & configs
├── element-web/   # Web client (already configured)
└── matrix/        # Matrix server (already configured)
```

---

## 🚀 Build Process Overview

### iOS (Requires Mac)

1. Fork https://github.com/element-hq/element-ios
2. Apply чатор branding (app name, icons, colors)
3. Set default server to `chator.k.vu`
4. Build in Xcode (20-40 min)
5. Distribute via TestFlight or App Store

**See:** [`ios/README.md`](ios/README.md)

**Requirements:**
- macOS 13+
- Xcode 15+
- Apple Developer Account ($99/year for App Store)

### Android (Any OS)

1. Fork https://github.com/element-hq/element-android
2. Apply чатор branding (app name, icons, strings)
3. Set default server to `chator.k.vu`
4. Build with Gradle (15-30 min)
5. Publish to Google Play

**See:** [`android/README.md`](android/README.md)

**Requirements:**
- Android Studio
- 16GB+ RAM
- Google Play Developer Account ($25 one-time)

---

## 🎨 Branding Assets

**Logo:** https://nopaste.net/chator

**Colors:**
- Primary Blue: `#4A90E2`
- Light Blue: `#5BA3F5`
- Dark Blue: `#2E5C8A`

**App Name:** чатор (Cyrillic)

**Files to update on both platforms:**
- App icon (all sizes)
- App name in strings
- Default homeserver URL
- Launch/splash screen
- About page

---

## 📦 Distribution

### iOS Options

| Method | Cost | Devices | Review |
|--------|------|---------|--------|
| **TestFlight** | $99/yr | 10,000 beta | Yes (light) |
| **App Store** | $99/yr | Unlimited | Yes (1-3 days) |
| **Ad-Hoc** | $99/yr | 100 devices | No |
| **Enterprise** | $299/yr | Unlimited employees | No |

### Android Options

| Method | Cost | Devices | Review |
|--------|------|---------|--------|
| **Internal Testing** | $25 | 100 testers | Yes (fast) |
| **Play Store** | $25 | Unlimited | Yes (1-7 days) |
| **Direct APK** | $0 | Unlimited | No |

---

## 💰 Costs Breakdown

| Item | Cost |
|------|------|
| Apple Developer Program | $99/year |
| Google Play Developer | $25 one-time |
| **Total Year 1** | **$124** |
| **Total Year 2+** | **$99/year** |

---

## ⚠️ Important Notes

### Legal
- Element is AGPL-3.0 licensed (open source)
- You can fork and distribute freely
- **Must** keep source code open if you distribute
- **Must** include license and copyright notices

### App Store Guidelines
- **iOS:** Must provide demo account for App Review
- **Android:** Must have privacy policy
- Both: Must declare data collection practices

### Maintenance
- Element releases updates every 2-4 weeks
- You'll need to merge upstream changes regularly
- Security updates are critical - don't fall behind

### Alternative: Build Once, Distribute Forever
If you don't want ongoing maintenance:
1. Fork Element once
2. Build and publish
3. When Element updates, decide whether to merge
4. Users can still use old versions (Matrix is backwards compatible)

---

## 🔧 Helper Scripts

### iOS: Quick Setup

```bash
#!/bin/bash
# Run from element-ios fork directory

echo "Setting up чатор iOS..."

# Backup original
cp Riot.xcodeproj/project.pbxproj Riot.xcodeproj/project.pbxproj.backup

# Replace app name
sed -i '' 's/PRODUCT_NAME = Element/PRODUCT_NAME = чатор/g' Riot.xcodeproj/project.pbxproj

# Generate project
xcodegen

# Install pods
pod install

echo "Done! Open Riot.xcworkspace in Xcode"
```

### Android: Quick Setup

```bash
#!/bin/bash
# Run from element-android fork directory

echo "Setting up чатор Android..."

# Replace app name
sed -i 's/app_name">Element/app_name">чатор/g' vectorapp/src/main/res/values/strings.xml

# Add Russian translation
cat > vectorapp/src/main/res/values-ru/strings.xml << 'EOF'
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <string name="app_name">чатор</string>
</resources>
EOF

echo "Done! Open in Android Studio"
```

---

## 📋 Checklist

Before publishing:

- [ ] App icon updated (all sizes)
- [ ] App name shows "чатор"
- [ ] Default server is `chator.k.vu`
- [ ] Splash screen branded
- [ ] Tested login/register flow
- [ ] Tested messaging
- [ ] Tested voice/video calls
- [ ] Tested push notifications
- [ ] Privacy policy URL added
- [ ] Support contact added
- [ ] Screenshots taken (all required sizes)
- [ ] App description written (English + Russian)
- [ ] Keywords optimized (чат, messenger, russia)

---

## 🎯 Recommended Launch Strategy

**Phase 1: Beta (Week 1-2)**
- Build both apps
- Distribute via TestFlight (iOS) + Internal Testing (Android)
- 10-20 beta testers
- Fix critical bugs

**Phase 2: Soft Launch (Week 3-4)**
- Publish to App Store (select countries)
- Publish to Play Store (select countries)
- Gather feedback
- Iterate on UX

**Phase 3: Full Launch (Week 5+)**
- Publish worldwide
- Marketing push
- Monitor crash reports
- Regular updates

---

## 📞 Support

**Element iOS:** https://github.com/element-hq/element-ios/issues
**Element Android:** https://github.com/element-hq/element-android/issues
**Matrix Spec:** https://matrix.org/docs/

**чатор issues:** (your GitHub repo here)

---

Ready to build? Pick your platform and follow the guides! 🥞

**iOS:** [`ios/README.md`](ios/README.md)
**Android:** [`android/README.md`](android/README.md)
