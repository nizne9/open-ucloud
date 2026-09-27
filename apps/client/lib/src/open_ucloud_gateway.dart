import 'dart:io';

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    show ExternalLibrary;
import 'package:open_ucloud_ffi/open_ucloud_ffi.dart' as open_ucloud_ffi;
import 'package:path/path.dart' as p;

abstract interface class OpenUcloudGateway {
  Future<void> init();

  Future<open_ucloud_ffi.FfiAuthStartResponse> authStart(String username);

  Future<open_ucloud_ffi.FfiAuthFinishResponse> authFinish(
    open_ucloud_ffi.FfiAuthFinishRequest request,
    open_ucloud_ffi.FfiLoginFlow flow,
  );

  Future<open_ucloud_ffi.FfiAuthSessionResponse> sessionSummary(
    String sessionPayload,
  );

  Future<open_ucloud_ffi.FfiClientCapabilities> capabilities();

  Future<open_ucloud_ffi.FfiAttendanceQrPayload> parseAttendanceQrPayloadText(
    String payload,
  );

  Future<open_ucloud_ffi.FfiCourseResponse> courses({
    required String sessionPayload,
    required bool withGoing,
  });

  Future<open_ucloud_ffi.FfiAssignmentListResponse> assignmentsUndone({
    required String sessionPayload,
  });

  Future<open_ucloud_ffi.FfiAssignmentListResponse> assignmentsForCourse({
    required String sessionPayload,
    required String siteId,
    required String siteName,
    required String keyword,
  });

  Future<open_ucloud_ffi.FfiAssignmentDetailResponse> assignmentDetail({
    required String sessionPayload,
    required String assignmentId,
  });

  Future<open_ucloud_ffi.FfiAssignmentUploadResponse> assignmentUpload({
    required String sessionPayload,
    required String assignmentId,
    required String filePath,
  });

  Future<open_ucloud_ffi.FfiAssignmentSubmitResponse> assignmentSubmit({
    required String sessionPayload,
    required String assignmentId,
    required String content,
    required List<String> attachmentIds,
  });

  Future<open_ucloud_ffi.FfiCourseResourcesResponse> resourcesForCourse({
    required String sessionPayload,
    required String siteId,
    required String siteName,
  });

  Future<open_ucloud_ffi.FfiCourseResourceDetailResponse> resourceDetail({
    required String sessionPayload,
    required String resourceId,
    required String siteId,
    required String siteName,
  });

  Future<open_ucloud_ffi.FfiDownloadTaskStartResponse> resourceDownloadStart({
    required String sessionPayload,
    required String resourceId,
    required String siteId,
    required String siteName,
    required String outputPath,
  });

  Future<open_ucloud_ffi.FfiDownloadTaskStartResponse>
  resourceDownloadCourseStart({
    required String sessionPayload,
    required String siteId,
    required String siteName,
    required String outputDir,
  });

  Future<open_ucloud_ffi.FfiDownloadTaskStatus> downloadTaskStatus({
    required String taskId,
  });

  Future<open_ucloud_ffi.FfiDownloadTaskStatus> downloadTaskCancel({
    required String taskId,
  });

  Future<void> downloadTaskDispose({required String taskId});

  Future<open_ucloud_ffi.FfiLogoutResponse> logout();
}

class FfiOpenUcloudGateway implements OpenUcloudGateway {
  bool _initialized = false;

  @override
  Future<void> init() async {
    if (_initialized) {
      return;
    }

    final libraryPath = _findBundledLibraryPath() ?? _findDebugLibraryPath();
    if (libraryPath == null) {
      await open_ucloud_ffi.RustLib.init();
    } else {
      await open_ucloud_ffi.RustLib.init(
        externalLibrary: ExternalLibrary.open(libraryPath),
      );
    }
    _initialized = true;
  }

  @override
  Future<open_ucloud_ffi.FfiAuthStartResponse> authStart(String username) {
    return open_ucloud_ffi.authStart(username: username);
  }

  @override
  Future<open_ucloud_ffi.FfiAuthFinishResponse> authFinish(
    open_ucloud_ffi.FfiAuthFinishRequest request,
    open_ucloud_ffi.FfiLoginFlow flow,
  ) {
    return open_ucloud_ffi.authFinish(request: request, flow: flow);
  }

  @override
  Future<open_ucloud_ffi.FfiAuthSessionResponse> sessionSummary(
    String sessionPayload,
  ) {
    return open_ucloud_ffi.sessionSummary(sessionPayload: sessionPayload);
  }

  @override
  Future<open_ucloud_ffi.FfiClientCapabilities> capabilities() {
    return open_ucloud_ffi.capabilities();
  }

  @override
  Future<open_ucloud_ffi.FfiAttendanceQrPayload> parseAttendanceQrPayloadText(
    String payload,
  ) {
    return open_ucloud_ffi.parseAttendanceQrPayloadText(payload: payload);
  }

  @override
  Future<open_ucloud_ffi.FfiCourseResponse> courses({
    required String sessionPayload,
    required bool withGoing,
  }) {
    return open_ucloud_ffi.courses(
      sessionPayload: sessionPayload,
      withGoing: withGoing,
    );
  }

  @override
  Future<open_ucloud_ffi.FfiAssignmentListResponse> assignmentsUndone({
    required String sessionPayload,
  }) {
    return open_ucloud_ffi.assignmentsUndone(sessionPayload: sessionPayload);
  }

  @override
  Future<open_ucloud_ffi.FfiAssignmentListResponse> assignmentsForCourse({
    required String sessionPayload,
    required String siteId,
    required String siteName,
    required String keyword,
  }) {
    return open_ucloud_ffi.assignmentsForCourse(
      sessionPayload: sessionPayload,
      siteId: siteId,
      siteName: siteName,
      keyword: keyword,
    );
  }

  @override
  Future<open_ucloud_ffi.FfiAssignmentDetailResponse> assignmentDetail({
    required String sessionPayload,
    required String assignmentId,
  }) {
    return open_ucloud_ffi.assignmentDetail(
      sessionPayload: sessionPayload,
      assignmentId: assignmentId,
    );
  }

  @override
  Future<open_ucloud_ffi.FfiAssignmentUploadResponse> assignmentUpload({
    required String sessionPayload,
    required String assignmentId,
    required String filePath,
  }) {
    return open_ucloud_ffi.assignmentUpload(
      sessionPayload: sessionPayload,
      assignmentId: assignmentId,
      filePath: filePath,
    );
  }

  @override
  Future<open_ucloud_ffi.FfiAssignmentSubmitResponse> assignmentSubmit({
    required String sessionPayload,
    required String assignmentId,
    required String content,
    required List<String> attachmentIds,
  }) {
    return open_ucloud_ffi.assignmentSubmit(
      sessionPayload: sessionPayload,
      assignmentId: assignmentId,
      content: content,
      attachmentIds: attachmentIds,
    );
  }

  @override
  Future<open_ucloud_ffi.FfiCourseResourcesResponse> resourcesForCourse({
    required String sessionPayload,
    required String siteId,
    required String siteName,
  }) {
    return open_ucloud_ffi.resourcesForCourse(
      sessionPayload: sessionPayload,
      siteId: siteId,
      siteName: siteName,
    );
  }

  @override
  Future<open_ucloud_ffi.FfiCourseResourceDetailResponse> resourceDetail({
    required String sessionPayload,
    required String resourceId,
    required String siteId,
    required String siteName,
  }) {
    return open_ucloud_ffi.resourceDetail(
      sessionPayload: sessionPayload,
      resourceId: resourceId,
      siteId: siteId,
      siteName: siteName,
    );
  }

  @override
  Future<open_ucloud_ffi.FfiDownloadTaskStartResponse> resourceDownloadStart({
    required String sessionPayload,
    required String resourceId,
    required String siteId,
    required String siteName,
    required String outputPath,
  }) {
    return open_ucloud_ffi.resourceDownloadStart(
      sessionPayload: sessionPayload,
      resourceId: resourceId,
      siteId: siteId,
      siteName: siteName,
      outputPath: outputPath,
    );
  }

  @override
  Future<open_ucloud_ffi.FfiDownloadTaskStartResponse>
  resourceDownloadCourseStart({
    required String sessionPayload,
    required String siteId,
    required String siteName,
    required String outputDir,
  }) {
    return open_ucloud_ffi.resourceDownloadCourseStart(
      sessionPayload: sessionPayload,
      siteId: siteId,
      siteName: siteName,
      outputDir: outputDir,
    );
  }

  @override
  Future<open_ucloud_ffi.FfiDownloadTaskStatus> downloadTaskStatus({
    required String taskId,
  }) {
    return open_ucloud_ffi.downloadTaskStatus(taskId: taskId);
  }

  @override
  Future<open_ucloud_ffi.FfiDownloadTaskStatus> downloadTaskCancel({
    required String taskId,
  }) {
    return open_ucloud_ffi.downloadTaskCancel(taskId: taskId);
  }

  @override
  Future<void> downloadTaskDispose({required String taskId}) {
    return open_ucloud_ffi.downloadTaskDispose(taskId: taskId);
  }

  @override
  Future<open_ucloud_ffi.FfiLogoutResponse> logout() {
    return open_ucloud_ffi.logout();
  }
}

String? _findDebugLibraryPath() {
  final libraryName = _debugLibraryName();
  if (libraryName == null) {
    return null;
  }

  var directory = Directory.current.absolute;
  for (var depth = 0; depth < 8; depth += 1) {
    final candidate = File(
      p.join(directory.path, 'target', 'debug', libraryName),
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

String? _findBundledLibraryPath() {
  if (!Platform.isMacOS) {
    return null;
  }
  final candidate = File(
    bundledMacOsLibraryPathForExecutable(Platform.resolvedExecutable),
  );
  if (candidate.existsSync()) {
    return candidate.path;
  }
  return null;
}

String bundledMacOsLibraryPathForExecutable(String executablePath) {
  final contentsDir = p.dirname(p.dirname(executablePath));
  return p.join(contentsDir, 'Frameworks', 'libopen_ucloud_ffi.dylib');
}

String? _debugLibraryName() {
  if (Platform.isLinux) {
    return 'libopen_ucloud_ffi.so';
  }
  if (Platform.isMacOS) {
    return 'libopen_ucloud_ffi.dylib';
  }
  return null;
}
