import 'dart:async';

import 'package:open_cloud_client/src/open_cloud_gateway.dart';
import 'package:open_cloud_ffi/open_cloud_ffi.dart';

class MemorySessionStorage implements OpenCloudSessionStorage {
  MemorySessionStorage([this.payload, this.readError]);

  String? payload;
  Object? readError;

  @override
  Future<void> clearSessionPayload() async {
    payload = null;
  }

  @override
  Future<String?> readSessionPayload() async {
    final error = readError;
    if (error != null) {
      throw error;
    }
    return payload;
  }

  @override
  Future<void> writeSessionPayload(String payload) async {
    this.payload = payload;
  }
}

FfiDownloadTaskStatus _succeededDownloadStatus(
  String taskId,
  FfiCourseResourceDownloadResponse response,
) {
  return FfiDownloadTaskStatus(
    taskId: taskId,
    state: FfiDownloadTaskState.succeeded,
    current: response.writtenPaths.length,
    total: response.records.length,
    bytesDownloaded: BigInt.zero,
    writtenPaths: response.writtenPaths,
    records: response.records,
    updatedSessionPayload: response.updatedSessionPayload,
  );
}

class FfiCourseResourceDownloadResponse {
  const FfiCourseResourceDownloadResponse({
    required this.records,
    required this.writtenPaths,
    this.updatedSessionPayload,
  });

  final List<FfiCourseResourceDetail> records;
  final List<String> writtenPaths;
  final String? updatedSessionPayload;
}

class FakeOpenCloudGateway implements OpenCloudGateway {
  FakeOpenCloudGateway({
    this.authStartResponse,
    this.session,
    this.courseResponse = const FfiCourseResponse(records: [], goingSites: []),
    List<FfiCourseResponse>? courseResponses,
    this.courseError,
    this.undoneAssignmentsResponse = const FfiAssignmentListResponse(
      records: [],
    ),
    this.undoneAssignmentsFuture,
    this.undoneAssignmentsError,
    this.courseAssignmentsResponse = const FfiAssignmentListResponse(
      records: [],
    ),
    this.courseAssignmentsFuture,
    this.assignmentDetailResponse,
    this.assignmentDetailFuture,
    List<Future<FfiAssignmentDetailResponse>>? assignmentDetailFutures,
    this.assignmentUploadResponse,
    this.assignmentUploadFuture,
    this.assignmentSubmitResponse = const FfiAssignmentSubmitResponse(ok: true),
    this.assignmentSubmitFuture,
    this.resourcesResponse = const FfiCourseResourcesResponse(records: []),
    this.resourceDetailResponse,
    this.resourceDetailFuture,
    List<Future<FfiCourseResourceDetailResponse>>? resourceDetailFutures,
    this.resourceDownloadResponse = const FfiCourseResourceDownloadResponse(
      records: [],
      writtenPaths: [],
    ),
    this.resourceDownloadFuture,
    this.resourceDownloadCourseFuture,
    List<Future<FfiCourseResourceDownloadResponse>>? resourceDownloadFutures,
    List<Future<FfiCourseResourceDownloadResponse>>?
    resourceDownloadCourseFutures,
    List<Future<FfiDownloadTaskStatus>>? downloadTaskStatusFutures,
    List<FfiDownloadTaskStatus>? downloadTaskStatuses,
    List<Future<FfiCourseResourcesResponse>>? resourcesFutures,
    List<FfiCourseResourcesResponse>? resourcesResponses,
    this.capabilitiesResponse = const FfiClientCapabilities(
      selfAttendance: false,
      attendanceQrPayloadParsing: false,
    ),
    this.capabilitiesError,
    this.parseAttendanceQrPayloadResponse,
    this.parseAttendanceQrPayloadError,
    this.sessionSummaryError,
  }) : courseResponses = List.of(courseResponses ?? []),
       assignmentDetailFutures = List.of(assignmentDetailFutures ?? []),
       resourceDetailFutures = List.of(resourceDetailFutures ?? []),
       resourceDownloadFutures = List.of(resourceDownloadFutures ?? []),
       resourceDownloadCourseFutures = List.of(
         resourceDownloadCourseFutures ?? [],
       ),
       downloadTaskStatusFutures = List.of(downloadTaskStatusFutures ?? []),
       downloadTaskStatuses = List.of(downloadTaskStatuses ?? []),
       resourcesFutures = List.of(resourcesFutures ?? []),
       resourcesResponses = List.of(resourcesResponses ?? []);

  final FfiAuthSessionResponse? session;
  final FfiAuthStartResponse? authStartResponse;
  final FfiCourseResponse courseResponse;
  final List<FfiCourseResponse> courseResponses;
  final Object? courseError;
  final FfiAssignmentListResponse undoneAssignmentsResponse;
  final Future<FfiAssignmentListResponse>? undoneAssignmentsFuture;
  final Object? undoneAssignmentsError;
  final FfiAssignmentListResponse courseAssignmentsResponse;
  final Future<FfiAssignmentListResponse>? courseAssignmentsFuture;
  final FfiAssignmentDetailResponse? assignmentDetailResponse;
  final Future<FfiAssignmentDetailResponse>? assignmentDetailFuture;
  final List<Future<FfiAssignmentDetailResponse>> assignmentDetailFutures;
  final FfiAssignmentUploadResponse? assignmentUploadResponse;
  final Future<FfiAssignmentUploadResponse>? assignmentUploadFuture;
  final FfiAssignmentSubmitResponse assignmentSubmitResponse;
  final Future<FfiAssignmentSubmitResponse>? assignmentSubmitFuture;
  final FfiCourseResourcesResponse resourcesResponse;
  final FfiCourseResourceDetailResponse? resourceDetailResponse;
  final Future<FfiCourseResourceDetailResponse>? resourceDetailFuture;
  final List<Future<FfiCourseResourceDetailResponse>> resourceDetailFutures;
  final FfiCourseResourceDownloadResponse resourceDownloadResponse;
  final Future<FfiCourseResourceDownloadResponse>? resourceDownloadFuture;
  final Future<FfiCourseResourceDownloadResponse>? resourceDownloadCourseFuture;
  final List<Future<FfiCourseResourceDownloadResponse>> resourceDownloadFutures;
  final List<Future<FfiCourseResourceDownloadResponse>>
  resourceDownloadCourseFutures;
  final List<Future<FfiDownloadTaskStatus>> downloadTaskStatusFutures;
  final List<FfiDownloadTaskStatus> downloadTaskStatuses;
  final List<Future<FfiCourseResourcesResponse>> resourcesFutures;
  final List<FfiCourseResourcesResponse> resourcesResponses;
  final FfiClientCapabilities capabilitiesResponse;
  final Object? capabilitiesError;
  final FfiAttendanceQrPayload? parseAttendanceQrPayloadResponse;
  final FfiAuthError? parseAttendanceQrPayloadError;
  final FfiAuthError? sessionSummaryError;
  bool initialized = false;
  int coursesCalls = 0;
  int undoneAssignmentsCalls = 0;
  String? lastCourseAssignmentsSiteId;
  String? lastResourcesSiteId;
  List<String> submittedAttachmentIds = const [];
  int downloadTaskStatusCalls = 0;
  final List<String> cancelledDownloadTaskIds = [];
  final List<String> disposedDownloadTaskIds = [];

  @override
  Future<void> init() async {
    initialized = true;
  }

  @override
  Future<FfiAuthStartResponse> authStart(String username) async {
    final response = authStartResponse;
    if (response != null) {
      return response;
    }
    return FfiAuthStartResponse(
      auth: const FfiAuthStartResult(flowId: 'flow-1', requiresCaptcha: false),
      flow: FfiLoginFlow(
        cookie: 'cookie',
        createdAtMs: BigInt.one,
        execution: 'flow-1',
        username: username,
      ),
    );
  }

  @override
  Future<FfiAuthFinishResponse> authFinish(
    FfiAuthFinishRequest request,
    FfiLoginFlow flow,
  ) async {
    return const FfiAuthFinishResponse(
      auth: FfiAuthFinishResult(
        roles: [],
        selectedRole: FfiRoleName.student,
        user: FfiSessionUser(
          account: '2024000000',
          realName: 'Alice',
          userId: 'u-1',
          userName: '2024000000',
        ),
      ),
      sessionPayload: 'session-payload',
    );
  }

  @override
  Future<FfiAuthSessionResponse> sessionSummary(String sessionPayload) async {
    final error = sessionSummaryError;
    if (error != null) {
      throw error;
    }
    return session ??
        const FfiAuthSessionResponse(
          selectedRole: FfiRoleName.student,
          user: FfiSessionUser(
            account: '2024000000',
            realName: 'Alice',
            userId: 'u-1',
            userName: '2024000000',
          ),
        );
  }

  @override
  Future<FfiClientCapabilities> capabilities() async {
    final error = capabilitiesError;
    if (error != null) {
      throw error;
    }
    return capabilitiesResponse;
  }

  @override
  Future<FfiAttendanceQrPayload> parseAttendanceQrPayloadText(
    String payload,
  ) async {
    final error = parseAttendanceQrPayloadError;
    if (error != null) {
      throw error;
    }
    return parseAttendanceQrPayloadResponse ??
        const FfiAttendanceQrPayload(
          attendanceId: 'attendance-1',
          siteId: 'site-1',
          createTime: '2026-05-09 10:00:00+08:00',
          classLessonId: 'lesson-1',
        );
  }

  @override
  Future<FfiCourseResponse> courses({
    required String sessionPayload,
    required bool withGoing,
  }) async {
    coursesCalls += 1;
    final error = courseError;
    if (error != null) {
      throw error;
    }
    if (courseResponses.isNotEmpty) {
      return courseResponses.removeAt(0);
    }
    return courseResponse;
  }

  @override
  Future<FfiAssignmentListResponse> assignmentsUndone({
    required String sessionPayload,
  }) async {
    undoneAssignmentsCalls += 1;
    final error = undoneAssignmentsError;
    if (error != null) {
      throw error;
    }
    final future = undoneAssignmentsFuture;
    if (future != null) {
      return future;
    }
    return undoneAssignmentsResponse;
  }

  @override
  Future<FfiAssignmentListResponse> assignmentsForCourse({
    required String sessionPayload,
    required String siteId,
    required String siteName,
    required String keyword,
  }) async {
    lastCourseAssignmentsSiteId = siteId;
    final future = courseAssignmentsFuture;
    if (future != null) {
      return future;
    }
    return courseAssignmentsResponse;
  }

  @override
  Future<FfiAssignmentDetailResponse> assignmentDetail({
    required String sessionPayload,
    required String assignmentId,
  }) async {
    if (assignmentDetailFutures.isNotEmpty) {
      return assignmentDetailFutures.removeAt(0);
    }
    final future = assignmentDetailFuture;
    if (future != null) {
      return future;
    }
    return assignmentDetailResponse ??
        FfiAssignmentDetailResponse(
          className: '',
          comment: '',
          content: '',
          endTime: '',
          id: assignmentId,
          isOvertimeCommit: false,
          siteId: '',
          siteName: '',
          startTime: '',
          status: FfiAssignmentStatus.pending,
          submittedAt: '',
          submittedAttachments: const [],
          submittedContent: '',
          teacherResources: const [],
          title: assignmentId,
        );
  }

  @override
  Future<FfiAssignmentUploadResponse> assignmentUpload({
    required String sessionPayload,
    required String assignmentId,
    required String filePath,
  }) async {
    final future = assignmentUploadFuture;
    if (future != null) {
      return future;
    }
    return assignmentUploadResponse ??
        FfiAssignmentUploadResponse(
          assignmentId: assignmentId,
          fileName: filePath.split('/').last,
          resourceId: 'resource-1',
          siteId: '',
          siteName: '',
        );
  }

  @override
  Future<FfiAssignmentSubmitResponse> assignmentSubmit({
    required String sessionPayload,
    required String assignmentId,
    required String content,
    required List<String> attachmentIds,
  }) async {
    submittedAttachmentIds = attachmentIds;
    final future = assignmentSubmitFuture;
    if (future != null) {
      return future;
    }
    return assignmentSubmitResponse;
  }

  @override
  Future<FfiCourseResourcesResponse> resourcesForCourse({
    required String sessionPayload,
    required String siteId,
    required String siteName,
  }) async {
    lastResourcesSiteId = siteId;
    if (resourcesFutures.isNotEmpty) {
      return resourcesFutures.removeAt(0);
    }
    if (resourcesResponses.isNotEmpty) {
      return resourcesResponses.removeAt(0);
    }
    return resourcesResponse;
  }

  @override
  Future<FfiCourseResourceDetailResponse> resourceDetail({
    required String sessionPayload,
    required String resourceId,
    required String siteId,
    required String siteName,
  }) async {
    if (resourceDetailFutures.isNotEmpty) {
      return resourceDetailFutures.removeAt(0);
    }
    final future = resourceDetailFuture;
    if (future != null) {
      return future;
    }
    return resourceDetailResponse ??
        FfiCourseResourceDetailResponse(
          detail: FfiCourseResourceDetail(
            name: resourceId,
            resourceId: resourceId,
            siteId: siteId,
            siteName: siteName,
            updatedAt: '',
          ),
        );
  }

  @override
  Future<FfiDownloadTaskStartResponse> resourceDownloadStart({
    required String sessionPayload,
    required String resourceId,
    required String siteId,
    required String siteName,
    required String outputPath,
  }) async {
    final taskId = 'download-${DateTime.now().microsecondsSinceEpoch}';
    final response = resourceDownloadFutures.isNotEmpty
        ? await resourceDownloadFutures.removeAt(0)
        : resourceDownloadFuture != null
        ? await resourceDownloadFuture!
        : resourceDownloadResponse;
    downloadTaskStatuses.add(_succeededDownloadStatus(taskId, response));
    return FfiDownloadTaskStartResponse(
      taskId: taskId,
      status: FfiDownloadTaskStatus(
        taskId: taskId,
        state: FfiDownloadTaskState.running,
        current: 0,
        total: response.records.isEmpty ? 1 : response.records.length,
        bytesDownloaded: BigInt.zero,
        writtenPaths: const [],
        records: const [],
      ),
    );
  }

  @override
  Future<FfiDownloadTaskStartResponse> resourceDownloadCourseStart({
    required String sessionPayload,
    required String siteId,
    required String siteName,
    required String outputDir,
  }) async {
    final taskId = 'download-course-${DateTime.now().microsecondsSinceEpoch}';
    final response = resourceDownloadCourseFutures.isNotEmpty
        ? await resourceDownloadCourseFutures.removeAt(0)
        : resourceDownloadCourseFuture != null
        ? await resourceDownloadCourseFuture!
        : resourceDownloadResponse;
    downloadTaskStatuses.add(_succeededDownloadStatus(taskId, response));
    return FfiDownloadTaskStartResponse(
      taskId: taskId,
      status: FfiDownloadTaskStatus(
        taskId: taskId,
        state: FfiDownloadTaskState.running,
        current: 0,
        total: response.records.length,
        bytesDownloaded: BigInt.zero,
        writtenPaths: const [],
        records: const [],
      ),
    );
  }

  @override
  Future<FfiDownloadTaskStatus> downloadTaskStatus({
    required String taskId,
  }) async {
    downloadTaskStatusCalls += 1;
    if (downloadTaskStatusFutures.isNotEmpty) {
      return downloadTaskStatusFutures.removeAt(0);
    }
    if (downloadTaskStatuses.isNotEmpty) {
      return downloadTaskStatuses.removeAt(0);
    }
    return FfiDownloadTaskStatus(
      taskId: taskId,
      state: FfiDownloadTaskState.succeeded,
      current: 0,
      total: 0,
      bytesDownloaded: BigInt.zero,
      writtenPaths: const [],
      records: const [],
    );
  }

  @override
  Future<FfiDownloadTaskStatus> downloadTaskCancel({
    required String taskId,
  }) async {
    cancelledDownloadTaskIds.add(taskId);
    downloadTaskStatuses.clear();
    return FfiDownloadTaskStatus(
      taskId: taskId,
      state: FfiDownloadTaskState.cancelled,
      current: 0,
      total: 0,
      bytesDownloaded: BigInt.zero,
      writtenPaths: const [],
      records: const [],
      errorMessage: '下载已取消。',
    );
  }

  @override
  Future<FfiLogoutResponse> downloadTaskDispose({
    required String taskId,
  }) async {
    disposedDownloadTaskIds.add(taskId);
    return const FfiLogoutResponse(clearSession: false);
  }

  @override
  Future<FfiLogoutResponse> logout() async {
    return const FfiLogoutResponse(clearSession: true);
  }
}
