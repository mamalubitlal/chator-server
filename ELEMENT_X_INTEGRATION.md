# чатор DPI Bypass - Integration for element-x-android

## 🎯 Quick Integration

Copy these files to your `element-x-android` fork:

### 1. Create Directories
```bash
cd element-x-android
mkdir -p app/src/main/kotlin/io/element/android/features/dpi/bypass
mkdir -p app/src/main/kotlin/io/element/android/features/network
mkdir -p app/src/main/assets
```

### 2. Copy Kotlin Files
```bash
# From chator-dpi-tester repo
cp chator-dpi-tester/app/src/main/java/io/github/romanvht/byedpi/activities/MatrixTestActivity.kt \
   app/src/main/kotlin/io/element/android/features/dpi/bypass/

cp chator-dpi-tester/app/src/main/java/io/github/romanvht/byedpi/manager/DpiStrategyManager.kt \
   app/src/main/kotlin/io/element/android/features/dpi/bypass/

cp chator-dpi-tester/app/src/main/java/io/github/romanvht/byedpi/work/DpiAutoTestWorker.kt \
   app/src/main/kotlin/io/element/android/features/dpi/bypass/

cp chator-dpi-tester/app/src/main/java/io/github/romanvht/byedpi/utility/SiteCheckUtils.kt \
   app/src/main/kotlin/io/element/android/features/dpi/bypass/

cp chator-dpi-tester/app/src/main/java/io/github/romanvht/byedpi/network/NetworkChangeObserver.kt \
   app/src/main/kotlin/io/element/android/features/network/
```

### 3. Copy Assets
```bash
cp chator-dpi-tester/app/src/main/assets/proxytest_strategies.list \
   app/src/main/assets/

cp chator-dpi-tester/app/src/main/assets/proxytest_matrix.sites \
   app/src/main/assets/
```

---

## 🔧 Manual Integration Steps

### Step 1: Add Dependencies

**File:** `app/build.gradle.kts`

```kotlin
dependencies {
    // WorkManager for background testing
    implementation("androidx.work:work-runtime-ktx:2.9.0")
    
    // Gson for JSON
    implementation("com.google.code.gson:gson:2.10.1")
}
```

### Step 2: Update Application.kt

**File:** `app/src/main/kotlin/io/element/android/ElementXApplication.kt`

Add imports:
```kotlin
import io.element.android.features.dpi.bypass.DpiStrategyManager
import io.element.android.features.dpi.bypass.DpiAutoTestWorker
import io.element.android.features.network.NetworkChangeObserver
import io.element.android.features.network.NetworkState
import io.element.android.features.network.NetworkType
```

Add to `onCreate()`:
```kotlin
override fun onCreate() {
    super.onCreate()
    
    // Check first boot
    val prefs = getSharedPreferences("elementx_prefs", MODE_PRIVATE)
    val isFirstBoot = prefs.getBoolean("first_boot", true)
    
    // Initialize DPI strategy manager
    val strategyManager = DpiStrategyManager(this)
    
    // Start network monitoring
    val networkObserver = NetworkChangeObserver(this)
    networkObserver.startMonitoring()
    
    // First boot: run full DPI test
    if (isFirstBoot) {
        Timber.i("🥞 First boot - scheduling full DPI test")
        DpiAutoTestWorker.scheduleFirstBootTest(this)
        prefs.edit().putBoolean("first_boot", false).apply()
    }
    
    // Observe network changes
    applicationScope.launch {
        networkObserver.networkState.collect { state ->
            when (state) {
                is NetworkState.Changed -> {
                    handleNetworkChange(state.type, strategyManager, networkObserver)
                }
                else -> {}
            }
        }
    }
}

private fun handleNetworkChange(
    networkType: NetworkType,
    strategyManager: DpiStrategyManager,
    networkObserver: NetworkChangeObserver
) {
    val networkId = when (networkType) {
        NetworkType.WiFi -> networkObserver.getCurrentWifiSsid()
        NetworkType.Mobile -> networkObserver.getCurrentCarrier()
        else -> "default"
    }
    
    val savedStrategy = strategyManager.getBestStrategyForCurrentNetwork(networkType, networkId)
    
    if (savedStrategy != null) {
        Timber.i("🥞 Applying saved strategy for $networkType/$networkId")
        strategyManager.applyStrategy(savedStrategy)
    } else if (strategyManager.isAutoTestEnabled()) {
        Timber.i("🥞 No strategy for $networkType/$networkId - scheduling test")
        DpiAutoTestWorker.scheduleNetworkChangeTest(this, networkType.toString())
    }
}
```

### Step 3: Add Permissions

**File:** `app/src/main/AndroidManifest.xml`

```xml
<manifest>
    <!-- Network permissions for DPI bypass -->
    <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
    <uses-permission android:name="android.permission.CHANGE_NETWORK_STATE" />
    <uses-permission android:name="android.permission.ACCESS_WIFI_STATE" />
    <uses-permission android:name="android.permission.INTERNET" />
</manifest>
```

### Step 4: Add Strings

**File:** `app/src/main/res/values/strings.xml`

```xml
<!-- DPI Bypass -->
<string name="dpi_bypass_category">DPI Bypass</string>
<string name="dpi_auto_test_enabled">Auto-test on network change</string>
<string name="dpi_auto_test_enabled_summary">Automatically test strategies when switching WiFi/Mobile</string>
<string name="dpi_test_now">Test strategies now</string>
<string name="dpi_test_now_summary">Manually test DPI bypass strategies</string>
<string name="dpi_test_running">Testing strategies…</string>
<string name="dpi_test_progress">Testing strategy %1$d/%2$d against %3$d domains…</string>
<string name="dpi_test_complete">Test complete! Best: %1$s (%2$d%%)</string>
<string name="dpi_first_boot_test">Optimizing connection for your network…</string>
<string name="dpi_retest_button">Re-test Now</string>
<string name="dpi_no_strategy">No strategy saved</string>
<string name="dpi_strategy_saved">Strategy saved</string>
```

**File:** `app/src/main/res/values-ru/strings.xml`

```xml
<!-- Обход DPI -->
<string name="dpi_bypass_category">Обход DPI</string>
<string name="dpi_auto_test_enabled">Авто-тест при смене сети</string>
<string name="dpi_auto_test_enabled_summary">Автоматически тестировать стратегии при переключении WiFi/Мобильная</string>
<string name="dpi_test_now">Тестировать стратегии</string>
<string name="dpi_test_now_summary">Протестировать стратегии обхода DPI</string>
<string name="dpi_test_running">Тестирование стратегий…</string>
<string name="dpi_test_progress">Тест стратегии %1$d/%2$d против %3$d доменов…</string>
<string name="dpi_test_complete">Тест завершён! Лучшая: %1$s (%2$d%%)</string>
<string name="dpi_first_boot_test">Оптимизация соединения для вашей сети…</string>
<string name="dpi_retest_button">Тестировать заново</string>
<string name="dpi_no_strategy">Нет сохранённой стратегии</string>
<string name="dpi_strategy_saved">Стратегия сохранена</string>
```

### Step 5: Add Settings UI

**File:** `app/src/main/kotlin/io/element/android/features/settings/advanced/AdvancedSettingsView.kt`

Add DPI bypass preference:
```kotlin
@Composable
internal fun AdvancedSettingsView(
    // ... existing params
    onDpiTestClick: () -> Unit = {},
) {
    // ... existing code
    
    PreferenceCategory(title = stringResource(R.string.dpi_bypass_category)) {
        ClickablePreference(
            title = stringResource(R.string.dpi_test_now),
            subtitle = stringResource(R.string.dpi_test_now_summary),
            icon = Icons.Outlined.Shield,
            onClick = onDpiTestClick
        )
    }
}
```

---

## 🎯 Features

✅ **First-boot auto-test** - Runs on first app launch  
✅ **Network change detection** - WiFi ↔ Mobile auto-test  
✅ **Per-network storage** - Best strategy per WiFi SSID / carrier  
✅ **Auto-apply** - Instant strategy switch  
✅ **Manual retest** - From Settings  
✅ **Strategy expiry** - Re-test after 24h  
✅ **Russian localization** - Full UI support  

---

## 📖 Full Documentation

- **Feature Summary:** https://github.com/mamalubitlal/chator-server/blob/main/chator-dpi-tester/FEATURE_SUMMARY.md
- **Integration Guide:** https://github.com/mamalubitlal/chator-server/blob/main/chator-dpi-tester/INTEGRATION_GUIDE.md

---

## 🚀 Build & Test

```bash
cd element-x-android
./gradlew assembleDebug
adb install app/build/outputs/apk/debug/app-debug.apk
```

---

**Ready to build Element X with automatic DPI bypass!** 🥞🚀
