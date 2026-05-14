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

  Future<open_cloud_ffi.FfiClientCapabilities> capabilities();

  Future<open_cloud_ffi.FfiAttendanceQrPayload> parseAttendanceQrPayloadText(
    String payload,
  );

  Future<open_cloud_ffi.FfiCourseResponse> courses({
    required String sessionPayload,
    required bool withGoing,
  });

  Future<open_cloud_ffi.FfiAssignmentListResponse> assignmentsUndone({
    required String sessionPayload,
  });

  Future<open_cloud_ffi.FfiAssignmentListResponse> assignmentsForCourse({
    required String sessionPayload,
    required String siteId,
    required String siteName,
    required String keyword,
  });

  Future<open_cloud_ffi.FfiAssignmentDetailResponse> assignmentDetail({
    required String sessionPayload,
    required String assignmentId,
  });

  Future<open_cloud_ffi.FfiAssignmentUploadResponse> assignmentUpload({
    required String sessionPayload,
    required String assignmentId,
    required String filePath,
  });

  Future<open_cloud_ffi.FfiAssignmentSubmitResponse> assignmentSubmit({
    required String sessionPayload,
    required String assignmentId,
    required String content,
    required List<String> attachmentIds,
  });

  Future<open_cloud_ffi.FfiCourseResourcesResponse> resourcesForCourse({
    required String sessionPayload,
    required String siteId,
    required String siteName,
  });

  Future<open_cloud_ffi.FfiCourseResourceDetailResponse> resourceDetail({
    required String sessionPayload,
    required String resourceId,
    required String siteId,
    required String siteName,
  });

  Future<open_cloud_ffi.FfiDownloadTaskStartResponse> resourceDownloadStart({
    required String sessionPayload,
    required String resourceId,
    required String siteId,
    required String siteName,
    required String outputPath,
  });

  Future<open_cloud_ffi.FfiDownloadTaskStartResponse>
  resourceDownloadCourseStart({
    required String sessionPayload,
    required String siteId,
    required String siteName,
    required String outputDir,
  });

  Future<open_cloud_ffi.FfiDownloadTaskStatus> downloadTaskStatus({
    required String taskId,
  });

  Future<open_cloud_ffi.FfiDownloadTaskStatus> downloadTaskCancel({
    required String taskId,
  });

  Future<open_cloud_ffi.FfiLogoutResponse> downloadTaskDispose({
    required String taskId,
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
  Future<open_cloud_ffi.FfiClientCapabilities> capabilities() {
    return open_cloud_ffi.capabilities();
  }

  @override
  Future<open_cloud_ffi.FfiAttendanceQrPayload> parseAttendanceQrPayloadText(
    String payload,
  ) {
    return open_cloud_ffi.parseAttendanceQrPayloadText(payload: payload);
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
  Future<open_cloud_ffi.FfiAssignmentListResponse> assignmentsUndone({
    required String sessionPayload,
  }) {
    return open_cloud_ffi.assignmentsUndone(sessionPayload: sessionPayload);
  }

  @override
  Future<open_cloud_ffi.FfiAssignmentListResponse> assignmentsForCourse({
    required String sessionPayload,
    required String siteId,
    required String siteName,
    required String keyword,
  }) {
    return open_cloud_ffi.assignmentsForCourse(
      sessionPayload: sessionPayload,
      siteId: siteId,
      siteName: siteName,
      keyword: keyword,
    );
  }

  @override
  Future<open_cloud_ffi.FfiAssignmentDetailResponse> assignmentDetail({
    required String sessionPayload,
    required String assignmentId,
  }) {
    return open_cloud_ffi.assignmentDetail(
      sessionPayload: sessionPayload,
      assignmentId: assignmentId,
    );
  }

  @override
  Future<open_cloud_ffi.FfiAssignmentUploadResponse> assignmentUpload({
    required String sessionPayload,
    required String assignmentId,
    required String filePath,
  }) {
    return open_cloud_ffi.assignmentUpload(
      sessionPayload: sessionPayload,
      assignmentId: assignmentId,
      filePath: filePath,
    );
  }

  @override
  Future<open_cloud_ffi.FfiAssignmentSubmitResponse> assignmentSubmit({
    required String sessionPayload,
    required String assignmentId,
    required String content,
    required List<String> attachmentIds,
  }) {
    return open_cloud_ffi.assignmentSubmit(
      sessionPayload: sessionPayload,
      assignmentId: assignmentId,
      content: content,
      attachmentIds: attachmentIds,
    );
  }

  @override
  Future<open_cloud_ffi.FfiCourseResourcesResponse> resourcesForCourse({
    required String sessionPayload,
    required String siteId,
    required String siteName,
  }) {
    return open_cloud_ffi.resourcesForCourse(
      sessionPayload: sessionPayload,
      siteId: siteId,
      siteName: siteName,
    );
  }

  @override
  Future<open_cloud_ffi.FfiCourseResourceDetailResponse> resourceDetail({
    required String sessionPayload,
    required String resourceId,
    required String siteId,
    required String siteName,
  }) {
    return open_cloud_ffi.resourceDetail(
      sessionPayload: sessionPayload,
      resourceId: resourceId,
      siteId: siteId,
      siteName: siteName,
    );
  }

  @override
  Future<open_cloud_ffi.FfiDownloadTaskStartResponse> resourceDownloadStart({
    required String sessionPayload,
    required String resourceId,
    required String siteId,
    required String siteName,
    required String outputPath,
  }) {
    return open_cloud_ffi.resourceDownloadStart(
      sessionPayload: sessionPayload,
      resourceId: resourceId,
      siteId: siteId,
      siteName: siteName,
      outputPath: outputPath,
    );
  }

  @override
  Future<open_cloud_ffi.FfiDownloadTaskStartResponse>
  resourceDownloadCourseStart({
    required String sessionPayload,
    required String siteId,
    required String siteName,
    required String outputDir,
  }) {
    return open_cloud_ffi.resourceDownloadCourseStart(
      sessionPayload: sessionPayload,
      siteId: siteId,
      siteName: siteName,
      outputDir: outputDir,
    );
  }

  @override
  Future<open_cloud_ffi.FfiDownloadTaskStatus> downloadTaskStatus({
    required String taskId,
  }) {
    return open_cloud_ffi.downloadTaskStatus(taskId: taskId);
  }

  @override
  Future<open_cloud_ffi.FfiDownloadTaskStatus> downloadTaskCancel({
    required String taskId,
  }) {
    return open_cloud_ffi.downloadTaskCancel(taskId: taskId);
  }

  @override
  Future<open_cloud_ffi.FfiLogoutResponse> downloadTaskDispose({
    required String taskId,
  }) {
    return open_cloud_ffi.downloadTaskDispose(taskId: taskId);
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
