package io.github.nizne9.open_ucloud

import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import org.woheller69.freeDroidWarn.FreeDroidWarn

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        showAndroidVerificationNoticeIfDue()
    }

    private fun showAndroidVerificationNoticeIfDue() {
        // Stay quiet while enforcement is still far out; the README badge and
        // docs/android-install.md carry the stance until the deadline nears.
        if (System.currentTimeMillis() < NOTICE_NOT_BEFORE_EPOCH_MILLIS) return

        @Suppress("DEPRECATION")
        val versionCode = packageManager.getPackageInfo(packageName, 0).versionCode
        val preferences = getSharedPreferences("${packageName}_preferences", MODE_PRIVATE)
        if (!preferences.contains(NOTICE_VERSION_KEY)) {
            // Fresh installs arrive from release notes that already explain
            // the stance; treat the notice as seen instead of greeting them
            // with the warning.
            preferences.edit().putInt(NOTICE_VERSION_KEY, versionCode).apply()
        } else {
            FreeDroidWarn.showWarningOnUpgrade(this, versionCode)
        }
    }

    private companion object {
        // 2026-11-01T00:00:00Z.
        private const val NOTICE_NOT_BEFORE_EPOCH_MILLIS = 1_793_491_200_000L

        // Mirrors the key the vendored FreeDroidWarn uses for its
        // once-per-version bookkeeping in the same preferences file.
        private const val NOTICE_VERSION_KEY = "versionCodeWarn"
    }
}
