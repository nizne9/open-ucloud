import java.util.Locale
import java.util.Properties

plugins {
    id("com.android.application")
    // Kotlin sources are compiled by AGP's built-in Kotlin support.
    id("dev.flutter.flutter-gradle-plugin")
}

val releaseSigningProperties =
    Properties().apply {
        val propertiesFile = rootProject.file("key.properties")
        if (propertiesFile.isFile) {
            propertiesFile.inputStream().use { load(it) }
        }
    }

fun releaseSigningValue(
    propertyName: String,
    environmentName: String,
): String? =
    releaseSigningProperties.getProperty(propertyName)?.takeIf { it.isNotBlank() }
        ?: System.getenv(environmentName)?.takeIf { it.isNotBlank() }

val releaseStoreFilePath =
    releaseSigningValue("storeFile", "ANDROID_RELEASE_STORE_FILE")
val releaseStoreType =
    releaseSigningValue("storeType", "ANDROID_RELEASE_STORE_TYPE") ?: "pkcs12"
val releaseStorePassword =
    releaseSigningValue("storePassword", "ANDROID_RELEASE_STORE_PASSWORD")
val releaseKeyAlias =
    releaseSigningValue("keyAlias", "ANDROID_RELEASE_KEY_ALIAS")
val releaseKeyPassword =
    releaseSigningValue("keyPassword", "ANDROID_RELEASE_KEY_PASSWORD")
val releaseSigningConfigured =
    listOf(
        releaseStoreFilePath,
        releaseStorePassword,
        releaseKeyAlias,
        releaseKeyPassword,
    ).all { !it.isNullOrBlank() }

fun requestedTaskName(taskName: String): String = taskName.substringAfterLast(':')

// AGP 9 rejects Provider values on SourceSet APIs; resolve to a concrete File.
fun ffiJniLibsDir(buildType: String): File =
    layout.buildDirectory.dir("generated/openUcloudFfiJniLibs/$buildType").get().asFile

val androidReleaseSigningTasks =
    setOf(
        "assembleRelease",
        "bundleRelease",
        "installRelease",
        "packageRelease",
        "packageReleaseBundle",
        "packageReleaseUniversalApk",
        "signReleaseBundle",
    )

fun requiresAndroidReleaseSigning(taskName: String): Boolean {
    val requestedTask = requestedTaskName(taskName)
    return requestedTask in androidReleaseSigningTasks
}

val releaseSigningRequested =
    gradle.startParameter.taskNames.any(::requiresAndroidReleaseSigning)

android {
    namespace = "io.github.nizne9.open_ucloud"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "io.github.nizne9.open_ucloud"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            if (releaseSigningConfigured) {
                storeFile = file(releaseStoreFilePath!!)
                storeType = releaseStoreType
                storePassword = releaseStorePassword
                keyAlias = releaseKeyAlias
                keyPassword = releaseKeyPassword
            } else if (releaseSigningRequested) {
                error(
                    "Android release signing is not configured. Set apps/client/android/key.properties " +
                        "or ANDROID_RELEASE_* environment variables before building release APKs or app bundles."
                )
            }
        }
    }

    buildTypes {
        debug {
            signingConfig = signingConfigs.getByName("debug")
        }
        getByName("profile") {
            initWith(getByName("debug"))
            signingConfig = signingConfigs.getByName("debug")
        }
        release {
            if (releaseSigningConfigured) {
                signingConfig = signingConfigs.getByName("release")
            } else if (releaseSigningRequested) {
                error(
                    "Android release signing is not configured. Set apps/client/android/key.properties " +
                        "or ANDROID_RELEASE_* environment variables before building release APKs or app bundles."
                )
            }
        }
    }

    sourceSets["debug"].jniLibs.srcDir(ffiJniLibsDir("debug"))
    sourceSets["profile"].jniLibs.srcDir(ffiJniLibsDir("profile"))
    sourceSets["release"].jniLibs.srcDir(ffiJniLibsDir("release"))
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    implementation(project(":freedroidwarn"))
}

val repoRoot = rootProject.projectDir.parentFile.parentFile.parentFile
val localProperties =
    Properties().apply {
        val localPropertiesFile = rootProject.file("local.properties")
        if (localPropertiesFile.isFile) {
            localPropertiesFile.inputStream().use { load(it) }
        }
    }
val androidSdkDir =
    localProperties.getProperty("sdk.dir") ?: System.getenv("ANDROID_HOME")
        ?: error("Android SDK path is not configured. Set sdk.dir or ANDROID_HOME.")
val androidNdkDir = file("$androidSdkDir/ndk/${flutter.ndkVersion}")
val androidApiLevel = "23"
val hostOsName = System.getProperty("os.name").lowercase(Locale.ROOT)
val hostArchName = System.getProperty("os.arch").lowercase(Locale.ROOT)
val androidNdkHostTags =
    when {
        hostOsName.contains("linux") -> listOf("linux-x86_64")
        hostOsName.contains("mac") || hostOsName.contains("darwin") ->
            if (hostArchName == "aarch64" || hostArchName == "arm64") {
                listOf("darwin-aarch64", "darwin-x86_64")
            } else {
                listOf("darwin-x86_64", "darwin-aarch64")
            }
        hostOsName.contains("windows") -> listOf("windows-x86_64")
        else -> error("Unsupported Android build host: $hostOsName/$hostArchName")
    }
val androidLlvmPrebuiltDir = androidNdkDir.resolve("toolchains/llvm/prebuilt")
val androidLlvmBin =
    androidNdkHostTags
        .map { androidLlvmPrebuiltDir.resolve("$it/bin") }
        .firstOrNull { it.isDirectory }
        ?: error(
            "Android NDK LLVM prebuilt directory was not found. Checked: ${
                androidNdkHostTags.joinToString { androidLlvmPrebuiltDir.resolve("$it/bin").absolutePath }
            }"
        )
val androidNdkHostTag = androidLlvmBin.parentFile.name
val hostExecutableNames =
    if (hostOsName.contains("windows")) {
        listOf("%s.cmd", "%s.bat", "%s.exe", "%s")
    } else {
        listOf("%s")
    }
val openUcloudFfiAndroidTargets =
    mapOf(
        "arm64-v8a" to Pair("aarch64-linux-android", "aarch64-linux-android$androidApiLevel-clang"),
        "armeabi-v7a" to Pair("armv7-linux-androideabi", "armv7a-linux-androideabi$androidApiLevel-clang"),
        "x86_64" to Pair("x86_64-linux-android", "x86_64-linux-android$androidApiLevel-clang"),
    )

fun androidLlvmTool(baseName: String) =
    hostExecutableNames
        .map { androidLlvmBin.resolve(it.format(baseName)) }
        .firstOrNull { it.isFile }
        ?: error("Android NDK tool $baseName was not found in ${androidLlvmBin.absolutePath}")

fun registerOpenUcloudFfiAndroidTask(
    buildType: String,
    cargoRelease: Boolean,
) {
    val capitalizedBuildType = buildType.replaceFirstChar { it.titlecase(Locale.ROOT) }
    val cargoProfile = if (cargoRelease) "release" else "debug"
    val outputDir = layout.buildDirectory.dir("generated/openUcloudFfiJniLibs/$buildType")

    tasks.register("buildOpenUcloudFfi${capitalizedBuildType}Android") {
        group = "build"
        description = "Builds the Open UCloud Rust FFI library for Android $buildType APKs."

        inputs.property("openUcloudFfiBuildType", buildType)
        inputs.property("openUcloudFfiCargoProfile", cargoProfile)
        inputs.property("openUcloudFfiNdkHostTag", androidNdkHostTag)
        inputs.file(repoRoot.resolve("Cargo.toml"))
        inputs.file(repoRoot.resolve("Cargo.lock"))
        inputs.dir(repoRoot.resolve("crates"))
        outputs.dir(outputDir)

        doLast {
            require(androidNdkDir.isDirectory) {
                "Android NDK ${flutter.ndkVersion} was not found at $androidNdkDir"
            }

            openUcloudFfiAndroidTargets.forEach { (abi, targetConfig) ->
                val (rustTarget, linkerName) = targetConfig
                val linker = androidLlvmTool(linkerName)
                val ar = androidLlvmTool("llvm-ar")

                val linkerEnv =
                    "CARGO_TARGET_${rustTarget.uppercase(Locale.ROOT).replace('-', '_')}_LINKER"
                val cargoArgs =
                    mutableListOf("build", "-p", "open-ucloud-ffi", "--target", rustTarget).apply {
                        if (cargoRelease) {
                            add("--release")
                        }
                    }

                val cargoEnvironment = mapOf(
                    linkerEnv to linker.absolutePath,
                    "CC_${rustTarget.replace('-', '_')}" to linker.absolutePath,
                    "AR_${rustTarget.replace('-', '_')}" to ar.absolutePath,
                )
                val cargoExitCode =
                    ProcessBuilder(listOf("cargo") + cargoArgs)
                        .directory(repoRoot)
                        .apply { environment().putAll(cargoEnvironment) }
                        .inheritIO()
                        .start()
                        .waitFor()
                require(cargoExitCode == 0) {
                    "cargo build failed for $rustTarget: cargo ${cargoArgs.joinToString(" ")}"
                }

                val sourceLibrary =
                    repoRoot.resolve("target/$rustTarget/$cargoProfile/libopen_ucloud_ffi.so")
                require(sourceLibrary.isFile) {
                    "Rust FFI build did not produce $sourceLibrary"
                }

                copy {
                    from(sourceLibrary)
                    into(outputDir.get().dir(abi))
                }
            }
        }
    }
}

registerOpenUcloudFfiAndroidTask(buildType = "debug", cargoRelease = false)
registerOpenUcloudFfiAndroidTask(buildType = "profile", cargoRelease = true)
registerOpenUcloudFfiAndroidTask(buildType = "release", cargoRelease = true)

tasks.matching { task ->
    task.name.startsWith("mergeDebug") &&
        (task.name.endsWith("JniLibFolders") || task.name.endsWith("NativeLibs"))
}.configureEach {
    dependsOn("buildOpenUcloudFfiDebugAndroid")
}

tasks.matching { task ->
    task.name.startsWith("mergeProfile") &&
        (task.name.endsWith("JniLibFolders") || task.name.endsWith("NativeLibs"))
}.configureEach {
    dependsOn("buildOpenUcloudFfiProfileAndroid")
}

tasks.matching { task ->
    task.name.startsWith("mergeRelease") &&
        (task.name.endsWith("JniLibFolders") || task.name.endsWith("NativeLibs"))
}.configureEach {
    dependsOn("buildOpenUcloudFfiReleaseAndroid")
}
