pluginManagement {
    val flutterSdkPath =
        run {
            val properties = java.util.Properties()
            val localPropertiesFile = file("local.properties")
            if (localPropertiesFile.isFile) {
                localPropertiesFile.inputStream().use { properties.load(it) }
            }
            val flutterSdkPath = properties.getProperty("flutter.sdk") ?: System.getenv("FLUTTER_ROOT")
            require(flutterSdkPath != null) { "Set flutter.sdk in local.properties or FLUTTER_ROOT." }
            flutterSdkPath
        }

    settings.extra["flutterSdkPath"] = flutterSdkPath

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "8.11.1" apply false
    id("org.jetbrains.kotlin.android") version "2.2.20" apply false
}

include(":app")
