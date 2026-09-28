# FreeDroidWarn (vendored)

Vendored copy of [woheller69/FreeDroidWarn](https://github.com/woheller69/FreeDroidWarn),
tag `V1.14` (commit `33964ab732c4d2955dd2b3e20cc52c1455052b5c`), Apache-2.0. See
[LICENSE](LICENSE) in this directory.

The library shows a one-time-per-upgrade dialog explaining that this project does
not register with Google's Android Developer Verification program, and points
affected users to <https://keepandroidopen.org> and workarounds. `MainActivity`
calls `FreeDroidWarn.showWarningOnUpgrade` on startup.

Source and resources are copied from upstream so future updates are plain
directory diffs, with two local deviations:

- upstream's `values-in -> values-id` locale symlink is materialized as a real
  directory so Windows checkouts stay buildable;
- `FreeDroidWarn.java` persists the seen version before showing the dialog
  instead of only on its OK button, so any dismissal (back button, outside
  tap) counts and the dialog cannot reappear on every launch.

`MainActivity` additionally gates the notice: it stays quiet before
2026-11-01 while the README and `docs/android-install.md` carry the stance,
and fresh installs are treated as already informed.

To update, replace `src/` with the new `library/src/` tree and
refresh `LICENSE`; only this README, the Gradle build file, and the
`com.android.library` plugin version in `settings.gradle.kts` are local additions.
Vendoring instead of using JitPack keeps the APK buildable fully from source,
which the F-Droid inclusion plan requires.
