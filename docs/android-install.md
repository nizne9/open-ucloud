# Installing the Android Client

Open UCloud is free and open-source software distributed independently of Google Play. Android packages are published exclusively as release-signed APKs attached to [GitHub Releases](https://github.com/nizne9/open-ucloud/releases), split by device ABI, with cryptographic `.sha256` checksum files provided for each package.

---

## 1. Select the Correct Package

Most modern Android smartphones and tablets use 64-bit ARM processors:

| Package File | Target Hardware Architecture | Typical Devices |
| --- | --- | --- |
| `open-ucloud-client-android-arm64-v8a.apk` | 64-bit ARM (`aarch64`) | **Almost all modern Android phones (Recommended)** |
| `open-ucloud-client-android-armeabi-v7a.apk` | 32-bit ARM (`armv7`) | Older legacy Android phones |
| `open-ucloud-client-android-x86_64.apk` | 64-bit Intel/AMD (`x86_64`) | Android emulators, ChromeOS, x86 Android tablets |

---

## 2. Verify Package Integrity

Before installing, verify that the downloaded APK matches the official build checksum:

```bash
# Verify checksum file
sha256sum -c open-ucloud-client-android-arm64-v8a.apk.sha256
```

To verify the release certificate signature using the Android SDK build tools:

```bash
apksigner verify --print-certs open-ucloud-client-android-arm64-v8a.apk
```

---

## 3. Standard Installation Steps

1. **Download the APK**: Download the matching APK and `.sha256` file from the latest [GitHub Release](https://github.com/nizne9/open-ucloud/releases).
2. **Enable Unknown Apps**: In Android **Settings**, search for **"Install unknown apps"**, select your browser or file manager, and toggle **"Allow from this source"**.
3. **Install the APK**: Tap the downloaded `.apk` file and confirm the installation.

---

## 4. Android Distribution Stance & The 2027 Enforcement

[![Keep Android Open](https://img.shields.io/badge/Keep_Android_Open-keepandroidopen.org-blue)](https://keepandroidopen.org/)

Open UCloud supports open ecosystems and user software freedom. This project will **not** register with Google's Android Developer Verification program. Beginning in 2027, this program requires third-party developers to escrow identity records and private signing keys with Google, blocking unverified applications on certified Android devices.

For background on the campaign and technical policy details, see [Keep Android Open](https://keepandroidopen.org/).

### Installation Alternatives After 2027

Device owners will retain several viable paths to run and update Open UCloud:

1. **Sideloading Escape Hatch**: Certified Google Android devices maintain an opt-out toggle within **Developer Options**. While requiring multiple confirmation steps, it allows unverified apps to run locally.
2. **ADB Sideloading**: Installation over the Android Debug Bridge remains unobstructed:
   ```bash
   # Initial installation
   adb install open-ucloud-client-android-arm64-v8a.apk

   # Updating an existing install
   adb install -r open-ucloud-client-android-arm64-v8a.apk
   ```
3. **De-Googled Operating Systems**: Devices running open-source ROMs (such as GrapheneOS, LineageOS, CalyxOS, or /e/OS) operate independently of Google Play Services and are completely unaffected by Google's developer verification restrictions.
4. **Desktop Clients**: Unrestricted desktop versions (Linux, Windows, and macOS) remain fully supported and feature-complete alternatives.

---

## 5. The In-App Notice (FreeDroidWarn)

The Open UCloud Android client embeds a vendored copy of [FreeDroidWarn](https://github.com/woheller69/FreeDroidWarn) (Apache-2.0 licensed, located in `apps/client/android/freedroidwarn/`).

FreeDroidWarn displays a single informational dialog upon initial app launch or upgrade, explaining developer verification policies, user rights, and community workarounds.
