plugins {
    id("com.android.library")
}

android {
    namespace = "org.woheller69.freeDroidWarn"
    compileSdk = 36

    defaultConfig {
        minSdk = 21
    }

    buildTypes {
        // The Flutter app module builds a profile variant; mirror it so the
        // dependency resolves without fallback matching.
        create("profile") {
            initWith(getByName("debug"))
        }
    }
}

dependencies {
    implementation("androidx.core:core:1.17.0")
}
