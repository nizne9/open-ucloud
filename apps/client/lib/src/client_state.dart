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

/// Converts an arbitrary error into text suitable for display, preferring the
/// upstream auth message over raw exception wrappers.
String displayErrorText(Object error) {
  if (error is FfiAuthError) {
    return error.message;
  }
  final text = error.toString();
  const prefix = 'Exception: ';
  return text.startsWith(prefix) ? text.substring(prefix.length) : text;
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
    this.errorMessage,
  });

  final String name;
  final String resourceId;
  final String? previewUrl;
  final String? errorMessage;
}

/// Whether a download task state is terminal (no further updates expected).
bool isTerminalDownloadState(FfiDownloadTaskState state) {
  return state == FfiDownloadTaskState.succeeded ||
      state == FfiDownloadTaskState.failed ||
      state == FfiDownloadTaskState.cancelled;
}

/// One entry in the download queue. Queued items have no [taskId] yet; the
/// id is assigned when the Rust-side task actually starts.
class DownloadTaskItem {
  const DownloadTaskItem({
    required this.id,
    required this.label,
    required this.siteId,
    required this.siteName,
    required this.outputPath,
    this.resourceId,
    this.taskId,
    this.status,
  });

  /// Local identity, stable across status updates.
  final String id;
  final String label;
  final String siteId;
  final String siteName;

  /// Target file path for single downloads, directory for course downloads.
  final String outputPath;

  /// Null for whole-course downloads.
  final String? resourceId;

  /// Rust-side task id, assigned once the task starts.
  final String? taskId;
  final FfiDownloadTaskStatus? status;

  bool get isCourseDownload => resourceId == null;
  bool get isQueued => taskId == null;
  bool get isTerminal {
    final state = status?.state;
    return state != null && isTerminalDownloadState(state);
  }

  bool get isRunning =>
      !isQueued && status?.state == FfiDownloadTaskState.running;

  DownloadTaskItem copyWith({String? taskId, FfiDownloadTaskStatus? status}) {
    return DownloadTaskItem(
      id: id,
      label: label,
      siteId: siteId,
      siteName: siteName,
      outputPath: outputPath,
      resourceId: resourceId,
      taskId: taskId ?? this.taskId,
      status: status ?? this.status,
    );
  }
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
    this.selectedResourceCourseId,
    this.selectedResourceId,
    this.resourceDetail,
    this.downloadTasks = const [],
    this.capabilities = defaultClientCapabilities,
    this.parsedAttendanceQrPayload,
    this.attendanceQrInputError,
    this.operationMessage,
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
  final String? selectedResourceCourseId;
  final String? selectedResourceId;
  final FfiCourseResourceDetail? resourceDetail;
  final List<DownloadTaskItem> downloadTasks;
  final FfiClientCapabilities capabilities;
  final FfiAttendanceQrPayload? parsedAttendanceQrPayload;
  final String? attendanceQrInputError;
  final String? operationMessage;
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
    String? selectedResourceCourseId,
    String? selectedResourceId,
    FfiCourseResourceDetail? resourceDetail,
    List<DownloadTaskItem>? downloadTasks,
    FfiClientCapabilities? capabilities,
    FfiAttendanceQrPayload? parsedAttendanceQrPayload,
    String? attendanceQrInputError,
    String? operationMessage,
    String? errorMessage,
    bool clearSession = false,
    bool clearLogin = false,
    bool clearSelectedAssignmentCourse = false,
    bool clearAssignmentSelection = false,
    bool clearAssignmentDetail = false,
    bool clearSelectedResourceCourse = false,
    bool clearResourceSelection = false,
    bool clearResourceDetail = false,
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
      selectedResourceCourseId: clearSelectedResourceCourse
          ? null
          : selectedResourceCourseId ?? this.selectedResourceCourseId,
      selectedResourceId: clearResourceSelection
          ? null
          : selectedResourceId ?? this.selectedResourceId,
      resourceDetail: clearResourceSelection || clearResourceDetail
          ? null
          : resourceDetail ?? this.resourceDetail,
      downloadTasks: downloadTasks ?? this.downloadTasks,
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
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
    );
  }
}
