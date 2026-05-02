/// Storage boundary expected by the Rust FFI facade.
///
/// Flutter clients should implement this with platform secure storage such as
/// Keychain or Keystore. The payload is opaque to Dart and must be passed back
/// to Rust unchanged.
abstract interface class OpenCloudSessionStorage {
  Future<String?> readSessionPayload();

  Future<void> writeSessionPayload(String payload);

  Future<void> clearSessionPayload();
}
