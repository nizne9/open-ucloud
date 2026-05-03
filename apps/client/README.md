# open_cloud_client

Open UCloud Flutter client. The current Linux desktop client supports login,
secure session restoration, course listing, assignment list/detail/upload/submit,
and course resource list/detail/single or batch downloads.

## Local Development

The first supported target is Linux desktop. Build the Rust FFI library before
running the Flutter shell:

```bash
cargo build -p open-cloud-ffi
cd apps/client
flutter run -d linux
```

The app stores only the opaque `sessionPayload` returned by Rust in platform
secure storage. Login protocol handling, token expiration checks, and token
refresh remain in the Rust core/FFI boundary.

File selection, save-location picking, and directory picking use Flutter's
`file_selector` package. Downloaded resource bytes are written by Rust through
the FFI facade, preserving non-overwriting path allocation.

Verification:

```bash
dart analyze
flutter test
```
