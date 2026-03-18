#!/bin/bash
# чатор iOS - Quick Setup Script
# Run this in your element-ios fork directory

set -e

echo "🥞 Setting up чатор iOS..."

# Check if we're in the right directory
if [ ! -f "Riot.xcodeproj/project.pbxproj" ]; then
    echo "❌ Error: Not in element-ios directory!"
    echo "   Clone your fork first: git clone https://github.com/YOUR_USER/element-ios.git"
    exit 1
fi

# Backup original project file
echo "📦 Backing up original project..."
cp Riot.xcodeproj/project.pbxproj Riot.xcodeproj/project.pbxproj.backup

# Replace app name in project
echo "🎨 Applying чатор branding..."
sed -i '' 's/PRODUCT_NAME = Element/PRODUCT_NAME = чатор/g' Riot.xcodeproj/project.pbxproj
sed -i '' 's/ELEMENT_DEFAULT_SERVER/chator.k.vu/g' Riot.xcodeproj/project.pbxproj

# Copy logo if available
if [ -f "../element-web/chator-logo.png" ]; then
    echo "📸 Copying logo..."
    cp ../element-web/chator-logo.png Tools/IconGenerator/chator-logo.png
    echo "   Logo copied to Tools/IconGenerator/"
    echo "   Use Image Asset Generator to create app icons"
fi

# Generate Xcode project
echo "🔨 Generating Xcode project..."
if command -v xcodegen &> /dev/null; then
    xcodegen
else
    echo "⚠️  xcodegen not found. Install with: brew install xcodegen"
    echo "   Then run: xcodegen"
fi

# Install CocoaPods
echo "📦 Installing CocoaPods dependencies..."
if command -v pod &> /dev/null; then
    pod install
else
    echo "⚠️  CocoaPods not found. Install with: sudo gem install cocoapods"
    echo "   Then run: pod install"
fi

echo ""
echo "✅ чатор iOS setup complete!"
echo ""
echo "Next steps:"
echo "1. Open Riot.xcworkspace in Xcode"
echo "2. Select your Development Team (Xcode → Preferences → Accounts)"
echo "3. Build: Product → Build (⌘B)"
echo "4. Run on device or simulator"
echo ""
echo "For detailed instructions, see: chator/ios/README.md"
