#!/bin/bash
# чатор DPI Bypass - Auto Integration Script
# Run this from the element-x-android root directory

set -e

echo "🚀 Integrating DPI Bypass into Element X..."

# Check if we're in the right directory
if [ ! -f "app/build.gradle.kts" ]; then
    echo "❌ Error: Not in element-x-android root directory"
    exit 1
fi

# Create directories
echo "📁 Creating directories..."
mkdir -p app/src/main/kotlin/io/element/android/features/dpi/bypass
mkdir -p app/src/main/kotlin/io/element/android/features/network
mkdir -p app/src/main/assets

# Copy Kotlin files
echo "📁 Copying Kotlin files..."
cp ../chator-dpi-tester/app/src/main/java/io/github/romanvht/byedpi/activities/MatrixTestActivity.kt \
   app/src/main/kotlin/io/element/android/features/dpi/bypass/

cp ../chator-dpi-tester/app/src/main/java/io/github/romanvht/byedpi/manager/DpiStrategyManager.kt \
   app/src/main/kotlin/io/element/android/features/dpi/bypass/

cp ../chator-dpi-tester/app/src/main/java/io/github/romanvht/byedpi/work/DpiAutoTestWorker.kt \
   app/src/main/kotlin/io/element/android/features/dpi/bypass/

cp ../chator-dpi-tester/app/src/main/java/io/github/romanvht/byedpi/utility/SiteCheckUtils.kt \
   app/src/main/kotlin/io/element/android/features/dpi/bypass/

cp ../chator-dpi-tester/app/src/main/java/io/github/romanvht/byedpi/network/NetworkChangeObserver.kt \
   app/src/main/kotlin/io/element/android/features/network/

# Copy assets
echo "📁 Copying assets..."
cp ../chator-dpi-tester/app/src/main/assets/proxytest_strategies.list \
   app/src/main/assets/

cp ../chator-dpi-tester/app/src/main/assets/proxytest_matrix.sites \
   app/src/main/assets/

echo ""
echo "✅ Files copied successfully!"
echo ""
echo "📖 Next steps (see ELEMENT_X_INTEGRATION.md):"
echo "  1. Add dependencies to app/build.gradle.kts"
echo "  2. Update ElementXApplication.kt"
echo "  3. Add permissions to AndroidManifest.xml"
echo "  4. Add strings to values/strings.xml"
echo "  5. Add Settings UI button"
echo "  6. Build & test!"
echo ""
echo "📄 Full guide: ../ELEMENT_X_INTEGRATION.md"
