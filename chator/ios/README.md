# чатор iOS App - Build Guide

Custom Element iOS app for чатор.

---

## ⚠️ Requirements

**You need:**
- Mac computer (macOS 13+)
- Xcode 15+ (14GB+)
- CocoaPods (`sudo gem install cocoapods`)
- XcodeGen (`brew install xcodegen`)
- Apple Developer Account ($99/year for App Store, FREE for personal use)

**Time:** 1-2 hours for first build

---

## Step 1: Fork Element iOS

1. Go to https://github.com/element-hq/element-ios
2. Click **Fork** → Create fork under your GitHub account
3. Clone YOUR fork:

```bash
git clone https://github.com/YOUR_USERNAME/element-ios.git chator-ios
cd chator-ios
```

---

## Step 2: Apply чатор Branding

### 2.1 Replace App Name

Find and replace in Xcode project:

**File:** `Riot.xcodeproj/project.pbxproj`

Search for `"Element"` and replace with `"чатор"` where it appears as:
- `PRODUCT_NAME`
- App display name

**OR** use sed:

```bash
# Backup first!
cp Riot.xcodeproj/project.pbxproj Riot.xcodeproj/project.pbxproj.bak

# Replace product name (be careful!)
sed -i '' 's/PRODUCT_NAME=Element/PRODUCT_NAME=чатор/g' Riot.xcodeproj/project.pbxproj
```

### 2.2 Update Assets

**App Icon:**
1. Download чатор logo: https://nopaste.net/chator
2. Open `Tools/IconGenerator` in the repo
3. Generate all icon sizes from your logo
4. Replace icons in `Resources/Assets.xcassets/AppIcon.appiconset/`

**Launch Screen:**
- Open `Resources/Assets.xcassets/LaunchImage.launchimage/`
- Replace with чатор branded images

### 2.3 Update Configuration

**File:** `Riot/Config/Info.plist`

Change:
```xml
<key>CFBundleName</key>
<string>Element</string>
```
To:
```xml
<key>CFBundleName</key>
<string>чатор</string>
```

**File:** `Riot/AppDelegate.swift`

Find the default homeserver config and change:

```swift
let defaultHomeserverURL = "https://chator.k.vu"
```

---

## Step 3: Build Configuration

**File:** `Riot/Config/BuildConfiguration.swift` (or similar)

Set:
```swift
static let defaultServerName = "chator.k.vu"
static let allowCustomServer = true
static let bugReportURL = "https://github.com/YOUR_USERNAME/chator/issues"
```

---

## Step 4: Generate Project & Install Dependencies

```bash
# Generate Xcode project
xcodegen

# Install CocoaPods dependencies (takes 10-20 min)
pod install

# Open workspace
open Riot.xcworkspace
```

---

## Step 5: Build in Xcode

1. Select your **Development Team** (Apple ID is fine for testing)
2. Select your iPhone or "Any iOS Device"
3. **Product → Build** (or ⌘B)
4. Wait 20-40 minutes for first build

**To run on your iPhone:**
1. Connect iPhone via USB
2. Select your device in Xcode
3. Click **Run** (▶️)
4. Trust the developer profile on your iPhone (Settings → General → Device Management)

---

## Step 6: Export IPA (for TestFlight or Distribution)

### For TestFlight (requires $99/year Apple Developer Program):

1. **Product → Archive**
2. Wait for archive to complete
3. Click **Distribute App**
4. Select **App Store Connect** → **Upload**
5. Follow prompts to upload to App Store Connect
6. Go to https://appstoreconnect.apple.com
7. Send to TestFlight beta testers

### For Ad-Hoc Distribution (100 devices max):

1. **Product → Archive**
2. **Distribute App** → **Ad Hoc**
3. Select provisioning profile with device UDIDs
4. Export `.ipa` file
5. Share via TestFlight, Diawi, or direct install

---

## Step 7: Publish to App Store

1. App Store Connect → Create new app
2. Bundle ID: `im.chator.ios` (or your choice)
3. Upload build from Xcode
4. Fill in:
   - App name: чатор
   - Description: "Messenger for Russian teens"
   - Keywords: чат, messenger, matrix, russia, teens
   - Screenshots (12.9" iPad, 6.7" iPhone, 6.5" iPhone)
   - Privacy policy URL
   - Support URL
5. Submit for review (1-3 days)

---

## Quick Reference

**Build time:** 20-40 min
**App size:** ~150-200 MB
**Minimum iOS:** 15.0+

**Key files to modify:**
| File | Purpose |
|------|---------|
| `Riot.xcodeproj/project.pbxproj` | App name, bundle ID |
| `Riot/Config/Info.plist` | Bundle name, version |
| `Resources/Assets.xcassets/` | Icons, launch images |
| `Riot/AppDelegate.swift` | Default server |
| `Riot/Config/BuildConfiguration.swift` | Build settings |

---

## Troubleshooting

**Build fails with "No such module":**
```bash
pod deintegrate
pod install
```

**Code signing errors:**
- Check Xcode → Preferences → Accounts
- Make sure you're signed in with Apple ID
- Select automatic signing

**App crashes on launch:**
- Check console logs in Xcode
- Verify default homeserver is accessible

**Icons don't update:**
- Clean build folder: ⌘⇧K
- Delete app from device
- Rebuild

---

## Next Steps

After iOS build works:
1. Set up CI/CD (GitHub Actions, Bitrise)
2. Automate builds for releases
3. Build Android version (see `chator/android/README.md`)
4. Set up TestFlight for beta testers

---

**Questions?** Check Element iOS docs: https://github.com/element-hq/element-ios#development

Удачи! 🥞
