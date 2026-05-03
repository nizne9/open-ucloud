# open_cloud_client

Open UCloud Flutter client.

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

Verification:

```bash
dart analyze
flutter test
```
