import 'dart:io';

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    show ExternalLibrary;
import 'package:open_cloud_ffi/open_cloud_ffi.dart' as open_cloud_ffi;
import 'package:path/path.dart' as p;

abstract interface class OpenCloudGateway {
  Future<void> init();

  Future<open_cloud_ffi.FfiAuthStartResponse> authStart(String username);

  Future<open_cloud_ffi.FfiAuthFinishResponse> authFinish(
    open_cloud_ffi.FfiAuthFinishRequest request,
    open_cloud_ffi.FfiLoginFlow flow,
  );

  Future<open_cloud_ffi.FfiAuthSessionResponse> sessionSummary(
    String sessionPayload,
  );

  Future<open_cloud_ffi.FfiCourseResponse> courses({
    required String sessionPayload,
    required bool withGoing,
  });

  Future<open_cloud_ffi.FfiLogoutResponse> logout();
}

class FfiOpenCloudGateway implements OpenCloudGateway {
  bool _initialized = false;

  @override
  Future<void> init() async {
    if (_initialized) {
      return;
    }

    final libraryPath = _findDebugLibraryPath();
    if (libraryPath == null) {
      await open_cloud_ffi.RustLib.init();
    } else {
      await open_cloud_ffi.RustLib.init(
        externalLibrary: ExternalLibrary.open(libraryPath),
      );
    }
    _initialized = true;
  }

  @override
  Future<open_cloud_ffi.FfiAuthStartResponse> authStart(String username) {
    return open_cloud_ffi.authStart(username: username);
  }

  @override
  Future<open_cloud_ffi.FfiAuthFinishResponse> authFinish(
    open_cloud_ffi.FfiAuthFinishRequest request,
    open_cloud_ffi.FfiLoginFlow flow,
  ) {
    return open_cloud_ffi.authFinish(request: request, flow: flow);
  }

  @override
  Future<open_cloud_ffi.FfiAuthSessionResponse> sessionSummary(
    String sessionPayload,
  ) {
    return open_cloud_ffi.sessionSummary(sessionPayload: sessionPayload);
  }

  @override
  Future<open_cloud_ffi.FfiCourseResponse> courses({
    required String sessionPayload,
    required bool withGoing,
  }) {
    return open_cloud_ffi.courses(
      sessionPayload: sessionPayload,
      withGoing: withGoing,
    );
  }

  @override
  Future<open_cloud_ffi.FfiLogoutResponse> logout() {
    return open_cloud_ffi.logout();
  }
}

String? _findDebugLibraryPath() {
  var directory = Directory.current.absolute;
  for (var depth = 0; depth < 8; depth += 1) {
    final candidate = File(
      p.join(directory.path, 'target', 'debug', 'libopen_cloud_ffi.so'),
    );
    if (candidate.existsSync()) {
      return candidate.path;
    }
    final parent = directory.parent;
    if (parent.path == directory.path) {
      return null;
    }
    directory = parent;
  }
  return null;
}
