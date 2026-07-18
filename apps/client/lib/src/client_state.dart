import 'package:open_cloud_ffi/open_cloud_ffi.dart';

enum ClientPhase {
  bootstrapping,
  unauthenticated,
  startingLogin,
  awaitingCaptcha,
  finishingLogin,
  loadingCourses,
  authenticated,
}

enum ClientTab { dashboard, assignments, resources, account }

enum AssignmentView { undone, course }

enum OperationContext {
  assignmentDetail,
  assignmentList,
  resourceDetail,
  resourceList,
}

const defaultClientCapabilities = FfiClientCapabilities(
  selfAttendance: false,
  attendanceQrPayloadParsing: false,
);

/// Formats a local timestamp for display, e.g. `2026-07-18 15:04`.
String formatClientTimestamp(DateTime value) {
  String twoDigits(int number) => number.toString().padLeft(2, '0');
  return '${value.year}-${twoDigits(value.month)}-${twoDigits(value.day)} '
      '${twoDigits(value.hour)}:${twoDigits(value.minute)}';
}

class CourseItem {
  const CourseItem({
    required this.id,
    required this.name,
    required this.going,
    this.groupId,
  });

  final String id;
  final String name;
  final bool going;
  final String? groupId;
}

class AssignmentAttachmentState {
  const AssignmentAttachmentState({
    required this.name,
    required this.resourceId,
    this.previewUrl,
    this.status = 'uploaded',
    this.errorMessage,
  });

  final String name;
  final String resourceId;
  final String? previewUrl;
  final String status;
  final String? errorMessage;
}

class ClientState {
  const ClientState({
    required this.phase,
    this.selectedTab = ClientTab.dashboard,
    this.session,
    this.loginFlow,
    this.pendingUsername,
    this.captchaImage,
    this.courses = const [],
    this.coursesSyncedAt,
    this.assignmentView = AssignmentView.undone,
    this.assignments = const [],
    this.assignmentsLoaded = false,
    this.assignmentsLoading = false,
    this.pendingAssignmentsErrorMessage,
    this.assignmentDetailLoading = false,
    this.assignmentUploading = false,
    this.assignmentSubmitting = false,
    this.selectedAssignmentCourseId,
    this.selectedAssignmentId,
    this.assignmentDetail,
    this.assignmentDraft = '',
    this.assignmentAttachments = const [],
    this.resources = const [],
    this.resourcesLoading = false,
    this.resourceDetailLoading = false,
    this.resourceDownloading = false,
    this.selectedResourceCourseId,
    this.selectedResourceId,
    this.resourceDetail,
    this.downloadedPaths = const [],
    this.resourceDownloadTaskId,
    this.resourceDownloadProgressCurrent = 0,
    this.resourceDownloadProgressTotal = 0,
    this.resourceDownloadBytes = 0,
    this.resourceDownloadCurrentFileName,
    this.capabilities = defaultClientCapabilities,
    this.parsedAttendanceQrPayload,
    this.attendanceQrInputError,
    this.operationMessage,
    this.operationContext,
    this.errorMessage,
  });

  const ClientState.bootstrapping() : this(phase: ClientPhase.bootstrapping);

  final ClientPhase phase;
  final ClientTab selectedTab;
  final FfiAuthSessionResponse? session;
  final FfiLoginFlow? loginFlow;
  final String? pendingUsername;
  final String? captchaImage;
  final List<CourseItem> courses;
  final DateTime? coursesSyncedAt;
  final AssignmentView assignmentView;
  final List<FfiAssignmentSummary> assignments;
  final bool assignmentsLoaded;
  final bool assignmentsLoading;
  final String? pendingAssignmentsErrorMessage;
  final bool assignmentDetailLoading;
  final bool assignmentUploading;
  final bool assignmentSubmitting;
  final String? selectedAssignmentCourseId;
  final String? selectedAssignmentId;
  final FfiAssignmentDetailResponse? assignmentDetail;
  final String assignmentDraft;
  final List<AssignmentAttachmentState> assignmentAttachments;
  final List<FfiCourseResourceSummary> resources;
  final bool resourcesLoading;
  final bool resourceDetailLoading;
  final bool resourceDownloading;
  final String? selectedResourceCourseId;
  final String? selectedResourceId;
  final FfiCourseResourceDetail? resourceDetail;
  final List<String> downloadedPaths;
  final String? resourceDownloadTaskId;
  final int resourceDownloadProgressCurrent;
  final int resourceDownloadProgressTotal;
  final int resourceDownloadBytes;
  final String? resourceDownloadCurrentFileName;
  final FfiClientCapabilities capabilities;
  final FfiAttendanceQrPayload? parsedAttendanceQrPayload;
  final String? attendanceQrInputError;
  final String? operationMessage;
  final OperationContext? operationContext;
  final String? errorMessage;

  bool get isBusy =>
      phase == ClientPhase.bootstrapping ||
      phase == ClientPhase.startingLogin ||
      phase == ClientPhase.finishingLogin ||
      phase == ClientPhase.loadingCourses;

  bool get undoneAssignmentsLoaded =>
      assignmentView == AssignmentView.undone && assignmentsLoaded;

  ClientState copyWith({
    ClientPhase? phase,
    ClientTab? selectedTab,
    FfiAuthSessionResponse? session,
    FfiLoginFlow? loginFlow,
    String? pendingUsername,
    String? captchaImage,
    List<CourseItem>? courses,
    DateTime? coursesSyncedAt,
    AssignmentView? assignmentView,
    List<FfiAssignmentSummary>? assignments,
    bool? assignmentsLoaded,
    bool? assignmentsLoading,
    String? pendingAssignmentsErrorMessage,
    bool? assignmentDetailLoading,
    bool? assignmentUploading,
    bool? assignmentSubmitting,
    String? selectedAssignmentCourseId,
    String? selectedAssignmentId,
    FfiAssignmentDetailResponse? assignmentDetail,
    String? assignmentDraft,
    List<AssignmentAttachmentState>? assignmentAttachments,
    List<FfiCourseResourceSummary>? resources,
    bool? resourcesLoading,
    bool? resourceDetailLoading,
    bool? resourceDownloading,
    String? selectedResourceCourseId,
    String? selectedResourceId,
    FfiCourseResourceDetail? resourceDetail,
    List<String>? downloadedPaths,
    String? resourceDownloadTaskId,
    int? resourceDownloadProgressCurrent,
    int? resourceDownloadProgressTotal,
    int? resourceDownloadBytes,
    String? resourceDownloadCurrentFileName,
    FfiClientCapabilities? capabilities,
    FfiAttendanceQrPayload? parsedAttendanceQrPayload,
    String? attendanceQrInputError,
    String? operationMessage,
    OperationContext? operationContext,
    String? errorMessage,
    bool clearSession = false,
    bool clearLogin = false,
    bool clearSelectedAssignmentCourse = false,
    bool clearAssignmentSelection = false,
    bool clearAssignmentDetail = false,
    bool clearSelectedResourceCourse = false,
    bool clearResourceSelection = false,
    bool clearResourceDetail = false,
    bool clearResourceDownloadTask = false,
    bool clearResourceDownloadCurrentFileName = false,
    bool clearAttendanceQrResult = false,
    bool clearAttendanceQrError = false,
    bool clearPendingAssignmentsError = false,
    bool clearOperationMessage = false,
    bool clearError = false,
  }) {
    return ClientState(
      phase: phase ?? this.phase,
      selectedTab: selectedTab ?? this.selectedTab,
      session: clearSession ? null : session ?? this.session,
      loginFlow: clearLogin ? null : loginFlow ?? this.loginFlow,
      pendingUsername: clearLogin
          ? null
          : pendingUsername ?? this.pendingUsername,
      captchaImage: clearLogin ? null : captchaImage ?? this.captchaImage,
      courses: courses ?? this.courses,
      coursesSyncedAt: coursesSyncedAt ?? this.coursesSyncedAt,
      assignmentView: assignmentView ?? this.assignmentView,
      assignments: assignments ?? this.assignments,
      assignmentsLoaded: assignmentsLoaded ?? this.assignmentsLoaded,
      assignmentsLoading: assignmentsLoading ?? this.assignmentsLoading,
      pendingAssignmentsErrorMessage: clearPendingAssignmentsError
          ? null
          : pendingAssignmentsErrorMessage ??
                this.pendingAssignmentsErrorMessage,
      assignmentDetailLoading:
          assignmentDetailLoading ?? this.assignmentDetailLoading,
      assignmentUploading: assignmentUploading ?? this.assignmentUploading,
      assignmentSubmitting: assignmentSubmitting ?? this.assignmentSubmitting,
      selectedAssignmentCourseId: clearSelectedAssignmentCourse
          ? null
          : selectedAssignmentCourseId ?? this.selectedAssignmentCourseId,
      selectedAssignmentId: clearAssignmentSelection
          ? null
          : selectedAssignmentId ?? this.selectedAssignmentId,
      assignmentDetail: clearAssignmentSelection || clearAssignmentDetail
          ? null
          : assignmentDetail ?? this.assignmentDetail,
      assignmentDraft: clearAssignmentSelection || clearAssignmentDetail
          ? ''
          : assignmentDraft ?? this.assignmentDraft,
      assignmentAttachments: clearAssignmentSelection || clearAssignmentDetail
          ? const []
          : assignmentAttachments ?? this.assignmentAttachments,
      resources: resources ?? this.resources,
      resourcesLoading: resourcesLoading ?? this.resourcesLoading,
      resourceDetailLoading:
          resourceDetailLoading ?? this.resourceDetailLoading,
      resourceDownloading: resourceDownloading ?? this.resourceDownloading,
      selectedResourceCourseId: clearSelectedResourceCourse
          ? null
          : selectedResourceCourseId ?? this.selectedResourceCourseId,
      selectedResourceId: clearResourceSelection
          ? null
          : selectedResourceId ?? this.selectedResourceId,
      resourceDetail: clearResourceSelection || clearResourceDetail
          ? null
          : resourceDetail ?? this.resourceDetail,
      downloadedPaths: downloadedPaths ?? this.downloadedPaths,
      resourceDownloadTaskId: clearResourceDownloadTask
          ? null
          : resourceDownloadTaskId ?? this.resourceDownloadTaskId,
      resourceDownloadProgressCurrent:
          resourceDownloadProgressCurrent ??
          this.resourceDownloadProgressCurrent,
      resourceDownloadProgressTotal:
          resourceDownloadProgressTotal ?? this.resourceDownloadProgressTotal,
      resourceDownloadBytes:
          resourceDownloadBytes ?? this.resourceDownloadBytes,
      resourceDownloadCurrentFileName: clearResourceDownloadCurrentFileName
          ? null
          : resourceDownloadCurrentFileName ??
                this.resourceDownloadCurrentFileName,
      capabilities: capabilities ?? this.capabilities,
      parsedAttendanceQrPayload: clearAttendanceQrResult
          ? null
          : parsedAttendanceQrPayload ?? this.parsedAttendanceQrPayload,
      attendanceQrInputError: clearAttendanceQrError
          ? null
          : attendanceQrInputError ?? this.attendanceQrInputError,
      operationMessage: clearOperationMessage
          ? null
          : operationMessage ?? this.operationMessage,
      operationContext:
          operationContext ??
          (clearOperationMessage ? null : this.operationContext),
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
    );
  }
}
