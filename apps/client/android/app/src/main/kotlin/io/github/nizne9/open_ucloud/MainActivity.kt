package io.github.nizne9.open_ucloud

import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import org.woheller69.freeDroidWarn.FreeDroidWarn

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        @Suppress("DEPRECATION")
        val versionCode = packageManager.getPackageInfo(packageName, 0).versionCode
        FreeDroidWarn.showWarningOnUpgrade(this, versionCode)
    }
}
