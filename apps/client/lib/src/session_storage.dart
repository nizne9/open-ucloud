import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:open_cloud_ffi/open_cloud_ffi.dart';

class SecureOpenCloudSessionStorage implements OpenCloudSessionStorage {
  SecureOpenCloudSessionStorage({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const _sessionPayloadKey = 'open_cloud.session_payload.v1';

  final FlutterSecureStorage _storage;

  @override
  Future<String?> readSessionPayload() {
    return _storage.read(key: _sessionPayloadKey);
  }

  @override
  Future<void> writeSessionPayload(String payload) {
    return _storage.write(key: _sessionPayloadKey, value: payload);
  }

  @override
  Future<void> clearSessionPayload() {
    return _storage.delete(key: _sessionPayloadKey);
  }
}
