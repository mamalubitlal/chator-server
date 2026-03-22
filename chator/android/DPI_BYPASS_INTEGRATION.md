# чатор DPI Bypass Integration Guide

## Overview

This guide explains how to integrate ByeByeDPI strategy testing into the чатор Android app (Element X fork).

---

## 📁 Files to Copy

### From ByeByeDPI → чатор

```
byebyedpi-temp/app/src/main/java/io/github/romanvht/byedpi/utility/
├── MatrixStrategyTester.kt          ← NEW! Matrix-specific tester
├── SiteCheckUtils.kt                 ← HTTP testing logic
├── DomainListUtils.kt                ← Domain list loading
└── StrategyResult.kt                 ← Data classes

byebyedpi-temp/app/src/main/assets/
├── proxytest_strategies.list         ← 71 ByeDPI strategies
├── proxytest_matrix.sites            ← NEW! Matrix domains only
└── (optional) other .sites files

byebyedpi-temp/app/src/main/cpp/byedpi/        ← Native ByeDPI library
byebyedpi-temp/app/src/main/jni/hev-socks5-tunnel/  ← SOCKS5 tunnel
```

---

## 🔧 Integration Steps

### Step 1: Add Dependencies

**File:** `chator-android/app/build.gradle.kts`

```kotlin
dependencies {
    // Add Gson for JSON parsing
    implementation("com.google.code.gson:gson:2.10.1")
    
    // Add Kotlin coroutines (if not already present)
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.7.3")
}
```

### Step 2: Copy Utility Classes

Copy these to `chator-android/app/src/main/java/im/vector/app/features/settings/dpi/`:

- `MatrixStrategyTester.kt`
- `SiteCheckUtils.kt`
- `StrategyResult.kt`
- `DomainResult.kt`

### Step 3: Copy Assets

Copy to `chator-android/app/src/main/assets/`:

- `proxytest_strategies.list`
- `proxytest_matrix.sites`

### Step 4: Add Native Libraries

**Complex step** - requires CMake integration:

1. Copy `byebyedpi-temp/app/src/main/cpp/byedpi/` → `chator-android/app/src/main/cpp/byedpi/`
2. Copy `hev-socks5-tunnel/` → `chator-android/app/src/main/jni/hev-socks5-tunnel/`
3. Update `CMakeLists.txt` to build both libraries
4. Add JNI bindings in Kotlin

### Step 5: Create UI Activity

**File:** `chator-android/app/src/main/java/im/vector/app/features/settings/dpi/DpiTestActivity.kt`

```kotlin
package im.vector.app.features.settings.dpi

import android.os.Bundle
import androidx.appcompat.app.AppCompatActivity
import androidx.lifecycle.lifecycleScope
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import im.vector.app.R
import kotlinx.coroutines.launch

class DpiTestActivity : AppCompatActivity() {
    
    private lateinit var tester: MatrixStrategyTester
    private lateinit var adapter: DpiTestResultAdapter
    
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_dpi_test)
        
        tester = MatrixStrategyTester(this)
        
        val recyclerView = findViewById<RecyclerView>(R.id.resultsRecyclerView)
        adapter = DpiTestResultAdapter()
        recyclerView.layoutManager = LinearLayoutManager(this)
        recyclerView.adapter = adapter
        
        findViewById<Button>(R.id.startTestButton).setOnClickListener {
            startTesting()
        }
    }
    
    private fun startTesting() {
        lifecycleScope.launch {
            tester.testAllStrategies(
                onProgress = { strategyIdx, total, domain, success ->
                    // Update UI
                },
                onStrategyComplete = { strategy, successCount, totalCount ->
                    // Update strategy result
                },
                onComplete = { results ->
                    // Show final results
                }
            )
        }
    }
}
```

### Step 6: Add Settings Entry

**File:** `chator-android/app/src/main/res/xml/settings_advanced.xml`

```xml
<Preference
    android:key="dpi_bypass_test"
    android:title="@string/dpi_bypass_test"
    android:summary="@string/dpi_bypass_test_summary"
    android:icon="@drawable/ic_shield">
    <intent
        android:targetClass="im.vector.app.features.settings.dpi.DpiTestActivity"
        android:targetPackage="im.vector.app" />
</Preference>
```

### Step 7: Add Strings

**File:** `chator-android/app/src/main/res/values/strings.xml`

```xml
<string name="dpi_bypass_test">DPI Bypass Test</string>
<string name="dpi_bypass_test_summary">Test connection strategies for blocked networks</string>
<string name="dpi_test_running">Testing strategies…</string>
<string name="dpi_test_complete">Test complete. Best strategy: %1$s</string>
```

**File:** `chator-android/app/src/main/res/values-ru/strings.xml`

```xml
<string name="dpi_bypass_test">Обход DPI</string>
<string name="dpi_bypass_test_summary">Тест стратегий для заблокированных сетей</string>
<string name="dpi_test_running">Тестирование стратегий…</string>
<string name="dpi_test_complete">Тест завершён. Лучшая стратегия: %1$s</string>
```

### Step 8: Auto-Test on First Boot

**File:** `chator-android/app/src/main/java/im/vector/app/VectorApplication.kt`

```kotlin
override fun onCreate() {
    super.onCreate()
    
    // Check if first boot
    val prefs = getSharedPreferences("chator_prefs", MODE_PRIVATE)
    val isFirstBoot = prefs.getBoolean("first_boot", true)
    
    if (isFirstBoot) {
        // Schedule DPI test in background
        scheduleDpiTest()
        prefs.edit().putBoolean("first_boot", false).apply()
    }
}

private fun scheduleDpiTest() {
    // Use WorkManager to run test in background
    val workRequest = OneTimeWorkRequestBuilder<DpiTestWorker>().build()
    WorkManager.getInstance(this).enqueue(workRequest)
}
```

---

## 🎯 Simplified Approach (No Native Code)

If native integration is too complex, use **SOCKS proxy mode**:

1. User installs separate **ByeByeDPI app**
2. чатор detects connection issues
3. чатор shows: "Install ByeByeDPI for bypass"
4. Deep link to ByeByeDPI with pre-configured Matrix domains
5. User runs test in ByeByeDPI, copies best strategy
6. User enters strategy in чатор settings

**Much simpler** - no native code merging required!

---

## 📱 UI Mockup

```
┌────────────────────────────────────┐
│  чатор - DPI Bypass Test           │
├────────────────────────────────────┤
│                                    │
│  Testing Matrix domains:           │
│  ✓ matrix.org                      │
│  ✓ vector.im                       │
│  ⏳ accounts.matrix.org            │
│  ○ turn.matrix.org                 │
│                                    │
│  Strategy 15/71: --disorder 1      │
│  ████████░░░░░░░░░░ 45%            │
│                                    │
│  [Stop Test]                       │
│                                    │
│  Results:                          │
│  1. --disorder 1        ✓ 8/8     │
│  2. --split 1+s       ✓ 7/8       │
│  3. --fake -1 -ttl 8  ✓ 6/8       │
│                                    │
│  [Apply Best Strategy]             │
└────────────────────────────────────┘
```

---

## ✅ Recommended Path

**For v1.0:** Use simplified approach (separate ByeByeDPI app)
**For v2.0:** Full native integration

This gets the feature working quickly without complex native code merging.

---

## 📚 Resources

- ByeByeDPI: https://github.com/romanvht/ByeByeDPI
- ByeDPI: https://github.com/hufrea/byedpi
- Hev SOCKS5 Tunnel: https://github.com/heiher/hev-socks5-tunnel
- Element Android: https://github.com/element-hq/element-android
