# open_cloud_client

Open UCloud Flutter client. The Linux-first desktop client supports login,
secure session restoration, course listing, assignment list/detail/upload/submit,
course resource list/detail/single or batch downloads, and a persisted
light/dark/system theme preference. Platform runners are present for Linux,
Android, Windows, and macOS.

## Local Development

Build the Rust FFI library before running the Linux Flutter shell:

```bash
sudo apt-get install clang cmake libgtk-3-dev libsecret-1-dev ninja-build pkg-config
cargo build -p open-cloud-ffi
cd apps/client
flutter run -d linux
```

macOS builds must run on a macOS host. The Xcode runner builds
`open-cloud-ffi` with the matching Cargo profile and copies
`libopen_cloud_ffi.dylib` into the app bundle:

```bash
cargo build -p open-cloud-ffi
cd apps/client
flutter build macos --debug
```

Release/profile packaging uses the release Rust dylib:

```bash
cargo build --release -p open-cloud-ffi
cd apps/client
flutter build macos --release
```

The app stores only the opaque `sessionPayload` returned by Rust in platform
secure storage. It also stores the selected theme mode locally. Login protocol
handling, token expiration checks, and token refresh remain in the Rust
core/FFI boundary.

File selection, save-location picking, and directory picking use Flutter's
`file_selector` package. Downloaded resource bytes are written by Rust through
the FFI facade, preserving non-overwriting path allocation.

Verification:

```bash
dart analyze
flutter test
```
