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

class FakeOpenCloudGateway implements OpenCloudGateway {
  FakeOpenCloudGateway({
    this.session,
    this.courseResponse = const FfiCourseResponse(records: [], goingSites: []),
    this.undoneAssignmentsResponse = const FfiAssignmentListResponse(
      records: [],
    ),
    this.courseAssignmentsResponse = const FfiAssignmentListResponse(
      records: [],
    ),
    this.assignmentDetailResponse,
    this.assignmentDetailFuture,
    List<Future<FfiAssignmentDetailResponse>>? assignmentDetailFutures,
    this.assignmentUploadResponse,
    this.assignmentSubmitResponse = const FfiAssignmentSubmitResponse(ok: true),
    this.resourcesResponse = const FfiCourseResourcesResponse(records: []),
    this.resourceDetailResponse,
    this.resourceDetailFuture,
    List<Future<FfiCourseResourceDetailResponse>>? resourceDetailFutures,
    this.resourceDownloadResponse = const FfiCourseResourceDownloadResponse(
      records: [],
      writtenPaths: [],
    ),
    this.capabilitiesResponse = const FfiClientCapabilities(
      selfAttendance: false,
      attendanceQrPayloadParsing: false,
    ),
    this.capabilitiesError,
    this.parseAttendanceQrPayloadResponse,
    this.parseAttendanceQrPayloadError,
    this.sessionSummaryError,
  }) : assignmentDetailFutures = assignmentDetailFutures ?? [],
       resourceDetailFutures = resourceDetailFutures ?? [];

  final FfiAuthSessionResponse? session;
  final FfiCourseResponse courseResponse;
  final FfiAssignmentListResponse undoneAssignmentsResponse;
  final FfiAssignmentListResponse courseAssignmentsResponse;
  final FfiAssignmentDetailResponse? assignmentDetailResponse;
  final Future<FfiAssignmentDetailResponse>? assignmentDetailFuture;
  final List<Future<FfiAssignmentDetailResponse>> assignmentDetailFutures;
  final FfiAssignmentUploadResponse? assignmentUploadResponse;
  final FfiAssignmentSubmitResponse assignmentSubmitResponse;
  final FfiCourseResourcesResponse resourcesResponse;
  final FfiCourseResourceDetailResponse? resourceDetailResponse;
  final Future<FfiCourseResourceDetailResponse>? resourceDetailFuture;
  final List<Future<FfiCourseResourceDetailResponse>> resourceDetailFutures;
  final FfiCourseResourceDownloadResponse resourceDownloadResponse;
  final FfiClientCapabilities capabilitiesResponse;
  final Object? capabilitiesError;
  final FfiAttendanceQrPayload? parseAttendanceQrPayloadResponse;
  final FfiAuthError? parseAttendanceQrPayloadError;
  final FfiAuthError? sessionSummaryError;
  bool initialized = false;
  int coursesCalls = 0;
  String? lastCourseAssignmentsSiteId;
  String? lastResourcesSiteId;
  List<String> submittedAttachmentIds = const [];

  @override
  Future<void> init() async {
    initialized = true;
  }

  @override
  Future<FfiAuthStartResponse> authStart(String username) async {
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
    return courseResponse;
  }

  @override
  Future<FfiAssignmentListResponse> assignmentsUndone({
    required String sessionPayload,
  }) async {
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
    return assignmentSubmitResponse;
  }

  @override
  Future<FfiCourseResourcesResponse> resourcesForCourse({
    required String sessionPayload,
    required String siteId,
    required String siteName,
  }) async {
    lastResourcesSiteId = siteId;
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
  Future<FfiCourseResourceDownloadResponse> resourceDownload({
    required String sessionPayload,
    required String resourceId,
    required String siteId,
    required String siteName,
    required String outputPath,
  }) async {
    return resourceDownloadResponse;
  }

  @override
  Future<FfiCourseResourceDownloadResponse> resourceDownloadCourse({
    required String sessionPayload,
    required String siteId,
    required String siteName,
    required String outputDir,
  }) async {
    return resourceDownloadResponse;
  }

  @override
  Future<FfiLogoutResponse> logout() async {
    return const FfiLogoutResponse(clearSession: true);
  }
}
