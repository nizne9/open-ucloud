# Installing the Android Client

Open UCloud is not distributed through Google Play. Android packages are
release-signed APKs attached to GitHub Releases, split by ABI, with a matching
`.sha256` file per asset. Most phones want the `arm64-v8a` APK.

This project will not register with Google's Android Developer Verification
program. Once enforcement starts in 2027, apps from non-registered developers
are blocked on certified Android devices unless the device owner takes one of
the paths below. This guide keeps those paths collected in one place; see
[Keep Android Open](https://keepandroidopen.org/) for the campaign background
and the current state of the program.

## Verify a Downloaded APK

```bash
sha256sum -c open-ucloud-client-android-arm64-v8a.apk.sha256
```

## Installing Today

1. Download the APK for your device ABI from the latest GitHub Release.
2. Allow your browser or file manager to install unknown apps for your device
   (Settings, search for "install unknown apps").
3. Open the APK and confirm the install.

From the app you can check the installed signature with
`apksigner verify --print-certs <apk>` from the Android build-tools if you want
to compare against the release certificate.

## After Verification Enforcement (2027)

The options below are expected to keep working. Exact device menus vary by
Android version and manufacturer, and the enforcement details themselves may
still change under regulatory review, so treat this section as reviewed before
each release rather than frozen.

- **Sideloading escape hatch.** Certified devices expose a per-app opt-out
  buried in Developer Options. It involves a multi-step flow and a waiting
  period, and Google can revoke it. The campaign site documents the exact
  steps per Android version.
- **ADB install.** Google has stated that installing over ADB keeps working.
  Enable USB debugging in Developer Options, then from a host with the
  platform-tools installed:

  ```bash
  adb install open-ucloud-client-android-arm64-v8a.apk
  ```

  Updates install the same way with `adb install -r`.
- **De-Googled ROMs.** Devices running GrapheneOS, LineageOS, CalyxOS, or
  /e/OS without certified Google Play Services are outside the program's
  reach entirely.
- **Desktop clients.** Linux, Windows, and macOS builds are unaffected by the
  program and remain the zero-friction alternative.

## The In-App Notice

The Flutter client embeds a vendored copy of
[FreeDroidWarn](https://github.com/woheller69/FreeDroidWarn), which shows a
dialog once per app upgrade explaining why this app is not verified with
Google and where to read about workarounds. The notice lives in
`apps/client/android/freedroidwarn/` and is Apache-2.0 licensed.
