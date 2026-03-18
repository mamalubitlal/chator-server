#!/bin/bash
# чатор Android - Quick Setup Script
# Run this in your element-android fork directory

set -e

echo "🥞 Setting up чатор Android..."

# Check if we're in the right directory
if [ ! -f "vectorapp/build.gradle" ]; then
    echo "❌ Error: Not in element-android directory!"
    echo "   Clone your fork first: git clone https://github.com/YOUR_USER/element-android.git"
    exit 1
fi

# Replace app name in strings
echo "🎨 Applying чатор branding..."

# Backup original strings.xml
cp vectorapp/src/main/res/values/strings.xml vectorapp/src/main/res/values/strings.xml.backup

# Replace app name
sed -i 's/app_name">Element/app_name">чатор/g' vectorapp/src/main/res/values/strings.xml

# Create Russian translation
echo "🇷🇺 Adding Russian translation..."
mkdir -p vectorapp/src/main/res/values-ru
cat > vectorapp/src/main/res/values-ru/strings.xml << 'EOF'
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <string name="app_name">чатор</string>
    <!-- Add more Russian translations as needed -->
</resources>
EOF

# Copy logo if available
if [ -f "../element-web/chator-logo.png" ]; then
    echo "📸 Copying logo..."
    cp ../element-web/chator-logo.png vectorapp/src/main/res/drawable/chator_logo.png
    echo "   Logo copied to: vectorapp/src/main/res/drawable/"
    echo "   Use Android Studio → File → Image Asset to generate all icon sizes"
fi

# Make gradlew executable
chmod +x gradlew

echo ""
echo "✅ чатор Android setup complete!"
echo ""
echo "Next steps:"
echo "1. Open this folder in Android Studio"
echo "2. Wait for Gradle sync (10-20 min first time)"
echo "3. Build: Build → Make Project (⌘/Ctrl+F9)"
echo "4. Run on device or emulator"
echo ""
echo "Or build from command line:"
echo "  ./gradlew assembleDebug"
echo ""
echo "For detailed instructions, see: chator/android/README.md"
