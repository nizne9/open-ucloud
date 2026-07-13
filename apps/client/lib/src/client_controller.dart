import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_cloud_ffi/open_cloud_ffi.dart';

import 'open_cloud_gateway.dart';
import 'session_storage.dart';

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

const _defaultCapabilities = FfiClientCapabilities(
  selfAttendance: false,
  attendanceQrPayloadParsing: false,
);

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
    this.pendingPassword,
    this.captchaImage,
    this.courses = const [],
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
    this.capabilities = _defaultCapabilities,
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
  final String? pendingPassword;
  final String? captchaImage;
  final List<CourseItem> courses;
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
    String? pendingPassword,
    String? captchaImage,
    List<CourseItem>? courses,
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
      pendingPassword: clearLogin
          ? null
          : pendingPassword ?? this.pendingPassword,
      captchaImage: clearLogin ? null : captchaImage ?? this.captchaImage,
      courses: courses ?? this.courses,
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

final sessionStorageProvider = Provider<OpenCloudSessionStorage>(
  (_) => SecureOpenCloudSessionStorage(),
);

final openCloudGatewayProvider = Provider<OpenCloudGateway>(
  (_) => FfiOpenCloudGateway(),
);

final clientControllerProvider =
    NotifierProvider<ClientController, ClientState>(ClientController.new);

class ClientController extends Notifier<ClientState> {
  int _assignmentListGeneration = 0;
  int _resourceListGeneration = 0;
  int _resourceDownloadGeneration = 0;
  bool _resourceDownloadPollInFlight = false;
  Timer? _resourceDownloadPollTimer;

  @override
  ClientState build() {
    ref.onDispose(() {
      _resourceDownloadPollTimer?.cancel();
    });
    return const ClientState.bootstrapping();
  }

  Future<void> bootstrap() async {
    state = const ClientState.bootstrapping();
    final storage = ref.read(sessionStorageProvider);
    final String? payload;
    try {
      payload = await storage.readSessionPayload();
    } catch (error) {
      try {
        await storage.clearSessionPayload();
      } catch (_) {}
      state = ClientState(
        phase: ClientPhase.unauthenticated,
        errorMessage: '无法读取安全存储：$error',
      );
      return;
    }
    if (payload == null || payload.isEmpty) {
      state = const ClientState(phase: ClientPhase.unauthenticated);
      return;
    }

    final gateway = ref.read(openCloudGatewayProvider);
    try {
      await gateway.init();
      final capabilities = await _loadCapabilitiesOrDefault(gateway);
      final session = await gateway.sessionSummary(payload);
      state = ClientState(
        phase: ClientPhase.loadingCourses,
        session: session,
        capabilities: capabilities,
      );
      await _loadCourses(payload, session, capabilities);
    } on FfiAuthError catch (error) {
      await storage.clearSessionPayload();
      state = ClientState(
        phase: ClientPhase.unauthenticated,
        errorMessage: error.message,
      );
    } catch (error) {
      await storage.clearSessionPayload();
      state = ClientState(
        phase: ClientPhase.unauthenticated,
        errorMessage: '无法恢复登录会话：$error',
      );
    }
  }

  Future<void> startLogin({
    required String username,
    required String password,
  }) async {
    final normalizedUsername = username.trim();
    if (normalizedUsername.isEmpty || password.isEmpty) {
      state = state.copyWith(errorMessage: '请输入用户名和密码。');
      return;
    }

    state = ClientState(
      phase: ClientPhase.startingLogin,
      pendingUsername: normalizedUsername,
      pendingPassword: password,
    );
    final gateway = ref.read(openCloudGatewayProvider);
    try {
      await gateway.init();
      final response = await gateway.authStart(normalizedUsername);
      if (response.auth.requiresCaptcha) {
        state = state.copyWith(
          phase: ClientPhase.awaitingCaptcha,
          loginFlow: response.flow,
          captchaImage: response.auth.captchaImage,
          clearError: true,
        );
        return;
      }
      await finishLogin(captcha: null, flow: response.flow);
    } on FfiAuthError catch (error) {
      state = ClientState(
        phase: ClientPhase.unauthenticated,
        errorMessage: error.message,
      );
    } catch (error) {
      state = ClientState(
        phase: ClientPhase.unauthenticated,
        errorMessage: '登录初始化失败：$error',
      );
    }
  }

  Future<void> finishLogin({
    required String? captcha,
    FfiLoginFlow? flow,
  }) async {
    final activeFlow = flow ?? state.loginFlow;
    final username = state.pendingUsername;
    final password = state.pendingPassword;
    if (activeFlow == null || username == null || password == null) {
      state = const ClientState(
        phase: ClientPhase.unauthenticated,
        errorMessage: '登录流程已失效，请重新开始。',
      );
      return;
    }

    state = state.copyWith(phase: ClientPhase.finishingLogin, clearError: true);
    final gateway = ref.read(openCloudGatewayProvider);
    final storage = ref.read(sessionStorageProvider);
    try {
      final result = await gateway.authFinish(
        FfiAuthFinishRequest(
          captcha: captcha == null || captcha.trim().isEmpty
              ? null
              : captcha.trim(),
          flowId: activeFlow.execution,
          password: password,
          role: null,
          username: username,
        ),
        activeFlow,
      );
      await storage.writeSessionPayload(result.sessionPayload);
      final session = FfiAuthSessionResponse(
        selectedRole: result.auth.selectedRole,
        user: result.auth.user,
      );
      final capabilities = await _loadCapabilitiesOrDefault(gateway);
      state = ClientState(
        phase: ClientPhase.loadingCourses,
        session: session,
        capabilities: capabilities,
      );
      await _loadCourses(result.sessionPayload, session, capabilities);
    } on FfiAuthError catch (error) {
      state = state.copyWith(
        phase: activeFlow.captchaId == null
            ? ClientPhase.unauthenticated
            : ClientPhase.awaitingCaptcha,
        errorMessage: error.message,
      );
    } catch (error) {
      state = state.copyWith(
        phase: activeFlow.captchaId == null
            ? ClientPhase.unauthenticated
            : ClientPhase.awaitingCaptcha,
        errorMessage: '登录失败：$error',
      );
    }
  }

  Future<void> refreshCourses() async {
    final storage = ref.read(sessionStorageProvider);
    final String? payload;
    try {
      payload = await storage.readSessionPayload();
    } catch (error) {
      state = state.copyWith(
        phase: state.session == null
            ? ClientPhase.unauthenticated
            : ClientPhase.authenticated,
        errorMessage: '无法读取安全存储：$error',
      );
      return;
    }
    final session = state.session;
    if (payload == null || session == null) {
      state = const ClientState(phase: ClientPhase.unauthenticated);
      return;
    }
    state = state.copyWith(phase: ClientPhase.loadingCourses, clearError: true);
    await _loadCourses(payload, session);
  }

  Future<void> parseAttendanceQrPayloadText(String payload) async {
    state = state.copyWith(
      clearAttendanceQrResult: true,
      clearAttendanceQrError: true,
    );
    final gateway = ref.read(openCloudGatewayProvider);
    try {
      final parsed = await gateway.parseAttendanceQrPayloadText(payload);
      state = state.copyWith(
        parsedAttendanceQrPayload: parsed,
        clearAttendanceQrError: true,
      );
    } on FfiAuthError catch (error) {
      state = state.copyWith(
        attendanceQrInputError: error.message,
        clearAttendanceQrResult: true,
      );
    } catch (error) {
      state = state.copyWith(
        attendanceQrInputError: '二维码文本解析失败：$error',
        clearAttendanceQrResult: true,
      );
    }
  }

  void clearAttendanceQrPayloadParseState() {
    state = state.copyWith(
      clearAttendanceQrResult: true,
      clearAttendanceQrError: true,
    );
  }

  void editLoginCredentials() {
    state = ClientState(
      phase: ClientPhase.unauthenticated,
      pendingUsername: state.pendingUsername,
      pendingPassword: state.pendingPassword,
    );
  }

  Future<void> logout() async {
    _assignmentListGeneration += 1;
    _resourceListGeneration += 1;
    await _cancelActiveResourceDownloadSilently();
    final gateway = ref.read(openCloudGatewayProvider);
    final storage = ref.read(sessionStorageProvider);
    try {
      final response = await gateway.logout();
      if (response.clearSession) {
        await storage.clearSessionPayload();
      }
    } finally {
      state = const ClientState(phase: ClientPhase.unauthenticated);
    }
  }

  void selectTab(ClientTab tab) {
    if (tab != ClientTab.resources) {
      unawaited(_cancelActiveResourceDownloadSilently());
    }
    state = state.copyWith(
      selectedTab: tab,
      resourceDownloading: tab == ClientTab.resources
          ? state.resourceDownloading
          : false,
      downloadedPaths: const [],
      resourceDownloadProgressCurrent: 0,
      resourceDownloadProgressTotal: 0,
      resourceDownloadBytes: 0,
      clearResourceDownloadTask: true,
      clearResourceDownloadCurrentFileName: true,
      clearOperationMessage: true,
      clearError: true,
    );
  }

  Future<void> loadUndoneAssignments({
    ClientTab selectedTab = ClientTab.assignments,
    bool clearGlobalError = true,
  }) async {
    final generation = ++_assignmentListGeneration;
    state = state.copyWith(
      selectedTab: selectedTab,
      assignmentView: AssignmentView.undone,
      assignments: const [],
      assignmentsLoaded: false,
      assignmentsLoading: true,
      assignmentDetailLoading: false,
      clearSelectedAssignmentCourse: true,
      clearAssignmentSelection: true,
      clearPendingAssignmentsError: true,
      clearOperationMessage: true,
      clearError: clearGlobalError,
    );
    final payload = await _readSessionPayloadOrUnauthenticated();
    if (payload == null) {
      if (_isCurrentAssignmentListGeneration(generation)) {
        state = state.copyWith(
          assignmentsLoading: false,
          pendingAssignmentsErrorMessage:
              state.phase == ClientPhase.authenticated
              ? state.errorMessage
              : null,
        );
      }
      return;
    }
    final gateway = ref.read(openCloudGatewayProvider);
    try {
      final response = await gateway.assignmentsUndone(sessionPayload: payload);
      if (!_isCurrentAssignmentListGeneration(generation)) {
        return;
      }
      await _persistUpdatedPayload(response.updatedSessionPayload);
      if (!_isCurrentAssignmentListGeneration(generation)) {
        return;
      }
      state = state.copyWith(
        assignments: response.records,
        assignmentsLoaded: true,
        assignmentsLoading: false,
        clearPendingAssignmentsError: true,
      );
    } on FfiAuthError catch (error) {
      if (!_isCurrentAssignmentListGeneration(generation)) {
        return;
      }
      await _handleSessionError(
        error,
        fallbackPhase: ClientPhase.authenticated,
      );
      state = state.copyWith(
        assignmentsLoaded: false,
        assignmentsLoading: false,
        pendingAssignmentsErrorMessage: error.message,
      );
    } catch (error) {
      if (!_isCurrentAssignmentListGeneration(generation)) {
        return;
      }
      final message = '未完成作业加载失败：$error';
      state = state.copyWith(
        assignmentsLoaded: false,
        assignmentsLoading: false,
        pendingAssignmentsErrorMessage: message,
        errorMessage: message,
      );
    }
  }

  Future<void> loadCourseAssignments(String siteId) async {
    final generation = ++_assignmentListGeneration;
    final course = _courseById(siteId);
    state = state.copyWith(
      selectedTab: ClientTab.assignments,
      assignmentView: AssignmentView.course,
      selectedAssignmentCourseId: siteId,
      assignments: const [],
      assignmentsLoaded: false,
      assignmentsLoading: true,
      assignmentDetailLoading: false,
      clearAssignmentSelection: true,
      clearOperationMessage: true,
      clearError: true,
    );
    final payload = await _readSessionPayloadOrUnauthenticated();
    if (payload == null) {
      if (_isCurrentAssignmentListGeneration(generation)) {
        state = state.copyWith(assignmentsLoading: false);
      }
      return;
    }
    final gateway = ref.read(openCloudGatewayProvider);
    try {
      final response = await gateway.assignmentsForCourse(
        sessionPayload: payload,
        siteId: siteId,
        siteName: course?.name ?? '',
        keyword: '',
      );
      if (!_isCurrentAssignmentListGeneration(generation)) {
        return;
      }
      await _persistUpdatedPayload(response.updatedSessionPayload);
      if (!_isCurrentAssignmentListGeneration(generation)) {
        return;
      }
      state = state.copyWith(
        assignments: response.records,
        assignmentsLoaded: true,
        assignmentsLoading: false,
      );
    } on FfiAuthError catch (error) {
      if (!_isCurrentAssignmentListGeneration(generation)) {
        return;
      }
      await _handleSessionError(
        error,
        fallbackPhase: ClientPhase.authenticated,
      );
      state = state.copyWith(
        assignmentsLoaded: false,
        assignmentsLoading: false,
      );
    } catch (error) {
      if (!_isCurrentAssignmentListGeneration(generation)) {
        return;
      }
      state = state.copyWith(
        assignmentsLoaded: false,
        assignmentsLoading: false,
        errorMessage: '课程作业加载失败：$error',
      );
    }
  }

  Future<void> selectAssignment(FfiAssignmentSummary assignment) async {
    state = state.copyWith(
      selectedAssignmentId: assignment.id,
      assignmentDetailLoading: true,
      clearAssignmentDetail: true,
      clearOperationMessage: true,
      clearError: true,
    );
    final payload = await _readSessionPayloadOrUnauthenticated();
    if (payload == null) {
      state = state.copyWith(assignmentDetailLoading: false);
      return;
    }
    final gateway = ref.read(openCloudGatewayProvider);
    try {
      final detail = await gateway.assignmentDetail(
        sessionPayload: payload,
        assignmentId: assignment.id,
      );
      if (state.selectedAssignmentId != assignment.id) {
        if (state.selectedAssignmentId == null) {
          state = state.copyWith(assignmentDetailLoading: false);
        }
        return;
      }
      await _persistUpdatedPayload(detail.updatedSessionPayload);
      state = state.copyWith(
        assignmentDetail: detail,
        assignmentDraft: detail.submittedContent,
        assignmentAttachments: [
          for (final attachment in detail.submittedAttachments)
            AssignmentAttachmentState(
              name: attachment.name,
              resourceId: attachment.resourceId,
              previewUrl: attachment.previewUrl,
            ),
        ],
        assignmentDetailLoading: false,
      );
    } on FfiAuthError catch (error) {
      if (error.code == FfiAuthErrorCode.sessionExpired) {
        await _handleSessionError(
          error,
          fallbackPhase: ClientPhase.authenticated,
        );
        return;
      }
      if (state.selectedAssignmentId != assignment.id) {
        if (state.selectedAssignmentId == null) {
          state = state.copyWith(assignmentDetailLoading: false);
        }
        return;
      }
      await _handleSessionError(
        error,
        fallbackPhase: ClientPhase.authenticated,
      );
      if (state.phase == ClientPhase.authenticated) {
        state = state.copyWith(
          assignmentDetailLoading: false,
          clearAssignmentSelection: true,
        );
      } else {
        state = state.copyWith(assignmentDetailLoading: false);
      }
    } catch (error) {
      if (state.selectedAssignmentId != assignment.id) {
        if (state.selectedAssignmentId == null) {
          state = state.copyWith(assignmentDetailLoading: false);
        }
        return;
      }
      state = state.copyWith(
        assignmentDetailLoading: false,
        clearAssignmentSelection: true,
        errorMessage: '作业详情加载失败：$error',
      );
    }
  }

  void clearAssignmentSelection() {
    if (state.assignmentUploading || state.assignmentSubmitting) {
      return;
    }
    state = state.copyWith(
      assignmentDetailLoading: false,
      clearAssignmentSelection: true,
      clearOperationMessage: true,
      clearError: true,
    );
  }

  void updateAssignmentDraft(String value) {
    state = state.copyWith(assignmentDraft: value);
  }

  Future<void> uploadAssignmentAttachment(String filePath) async {
    final detail = state.assignmentDetail;
    if (detail == null) {
      state = state.copyWith(errorMessage: '请先选择一个作业。');
      return;
    }
    if (detail.status == FfiAssignmentStatus.expired) {
      state = state.copyWith(errorMessage: '当前作业已截止，不能继续上传附件。');
      return;
    }
    final payload = await _readSessionPayloadOrUnauthenticated();
    if (payload == null) {
      return;
    }
    if (state.selectedAssignmentId != detail.id ||
        state.assignmentDetail?.id != detail.id) {
      return;
    }
    state = state.copyWith(
      assignmentUploading: true,
      clearError: true,
      clearOperationMessage: true,
    );
    final gateway = ref.read(openCloudGatewayProvider);
    try {
      final uploaded = await gateway.assignmentUpload(
        sessionPayload: payload,
        assignmentId: detail.id,
        filePath: filePath,
      );
      if (state.selectedAssignmentId != detail.id ||
          state.assignmentDetail?.id != detail.id) {
        state = state.copyWith(assignmentUploading: false);
        return;
      }
      await _persistUpdatedPayload(uploaded.updatedSessionPayload);
      state = state.copyWith(
        assignmentAttachments: [
          ...state.assignmentAttachments,
          AssignmentAttachmentState(
            name: uploaded.fileName,
            resourceId: uploaded.resourceId,
            previewUrl: uploaded.previewUrl,
          ),
        ],
        assignmentUploading: false,
        operationMessage: '已上传附件 ${uploaded.fileName}',
        operationContext: OperationContext.assignmentDetail,
        clearError: true,
      );
    } on FfiAuthError catch (error) {
      if (error.code != FfiAuthErrorCode.sessionExpired &&
          (state.selectedAssignmentId != detail.id ||
              state.assignmentDetail?.id != detail.id)) {
        state = state.copyWith(assignmentUploading: false);
        return;
      }
      await _handleSessionError(
        error,
        fallbackPhase: ClientPhase.authenticated,
      );
      state = state.copyWith(assignmentUploading: false);
    } catch (error) {
      if (state.selectedAssignmentId != detail.id ||
          state.assignmentDetail?.id != detail.id) {
        state = state.copyWith(assignmentUploading: false);
        return;
      }
      state = state.copyWith(
        assignmentUploading: false,
        errorMessage: '附件上传失败：$error',
      );
    }
  }

  void removeAssignmentAttachment(String resourceId) {
    AssignmentAttachmentState? removed;
    final attachments = <AssignmentAttachmentState>[];
    for (final attachment in state.assignmentAttachments) {
      if (attachment.resourceId == resourceId) {
        removed = attachment;
        continue;
      }
      attachments.add(attachment);
    }
    if (removed == null) {
      return;
    }
    state = state.copyWith(
      assignmentAttachments: attachments,
      operationMessage: '已移除附件 ${removed.name}',
      operationContext: OperationContext.assignmentDetail,
      clearError: true,
    );
  }

  Future<void> submitAssignmentDraft([String? draftText]) async {
    final detail = state.assignmentDetail;
    if (detail == null) {
      state = state.copyWith(errorMessage: '请先选择一个作业。');
      return;
    }
    if (detail.status == FfiAssignmentStatus.expired) {
      state = state.copyWith(errorMessage: '当前作业已截止，不能继续提交。');
      return;
    }
    final attachmentIds = [
      for (final attachment in state.assignmentAttachments)
        if (attachment.status == 'uploaded') attachment.resourceId,
    ];
    final draft = draftText ?? state.assignmentDraft;
    final resubmitting = detail.status == FfiAssignmentStatus.submitted;
    if (draft.trim().isEmpty && attachmentIds.isEmpty) {
      state = state.copyWith(errorMessage: '请先填写作业内容或上传附件。');
      return;
    }
    final attachments = state.assignmentAttachments;
    final payload = await _readSessionPayloadOrUnauthenticated();
    if (payload == null) {
      return;
    }
    if (state.selectedAssignmentId != detail.id ||
        state.assignmentDetail?.id != detail.id) {
      return;
    }
    state = state.copyWith(
      assignmentSubmitting: true,
      clearError: true,
      clearOperationMessage: true,
    );
    final gateway = ref.read(openCloudGatewayProvider);
    try {
      final response = await gateway.assignmentSubmit(
        sessionPayload: payload,
        assignmentId: detail.id,
        content: draft,
        attachmentIds: attachmentIds,
      );
      if (state.selectedAssignmentId != detail.id ||
          state.assignmentDetail?.id != detail.id) {
        state = state.copyWith(assignmentSubmitting: false);
        return;
      }
      await _persistUpdatedPayload(response.updatedSessionPayload);
      state = state.copyWith(
        assignmentSubmitting: false,
        assignmentDetail: FfiAssignmentDetailResponse(
          className: detail.className,
          comment: detail.comment,
          content: detail.content,
          endTime: detail.endTime,
          id: detail.id,
          isOvertimeCommit: detail.isOvertimeCommit,
          score: detail.score,
          siteId: detail.siteId,
          siteName: detail.siteName,
          startTime: detail.startTime,
          status: FfiAssignmentStatus.submitted,
          submittedAt: DateTime.now().toIso8601String(),
          submittedAttachments: [
            for (final attachment in attachments)
              FfiAssignmentResource(
                name: attachment.name,
                previewUrl: attachment.previewUrl,
                resourceId: attachment.resourceId,
              ),
          ],
          submittedContent: draft,
          teacherResources: detail.teacherResources,
          title: detail.title,
        ),
        operationMessage: resubmitting ? '作业已重新提交' : '作业已提交',
        operationContext: OperationContext.assignmentDetail,
      );
    } on FfiAuthError catch (error) {
      if (error.code != FfiAuthErrorCode.sessionExpired &&
          (state.selectedAssignmentId != detail.id ||
              state.assignmentDetail?.id != detail.id)) {
        state = state.copyWith(assignmentSubmitting: false);
        return;
      }
      await _handleSessionError(
        error,
        fallbackPhase: ClientPhase.authenticated,
      );
      state = state.copyWith(assignmentSubmitting: false);
    } catch (error) {
      if (state.selectedAssignmentId != detail.id ||
          state.assignmentDetail?.id != detail.id) {
        state = state.copyWith(assignmentSubmitting: false);
        return;
      }
      state = state.copyWith(
        assignmentSubmitting: false,
        errorMessage: '作业提交失败：$error',
      );
    }
  }

  Future<void> loadResourcesForCourse(String siteId) async {
    final generation = ++_resourceListGeneration;
    unawaited(_cancelActiveResourceDownloadSilently());
    final course = _courseById(siteId);
    state = state.copyWith(
      selectedTab: ClientTab.resources,
      selectedResourceCourseId: siteId,
      resources: const [],
      resourcesLoading: true,
      resourceDownloading: false,
      downloadedPaths: const [],
      resourceDownloadProgressCurrent: 0,
      resourceDownloadProgressTotal: 0,
      resourceDownloadBytes: 0,
      clearResourceDownloadTask: true,
      clearResourceDownloadCurrentFileName: true,
      resourceDetailLoading: false,
      clearResourceSelection: true,
      clearOperationMessage: true,
      clearError: true,
    );
    final payload = await _readSessionPayloadOrUnauthenticated();
    if (payload == null) {
      if (_isCurrentResourceListGeneration(generation)) {
        state = state.copyWith(resourcesLoading: false);
      }
      return;
    }
    final gateway = ref.read(openCloudGatewayProvider);
    try {
      final response = await gateway.resourcesForCourse(
        sessionPayload: payload,
        siteId: siteId,
        siteName: course?.name ?? '',
      );
      if (!_isCurrentResourceListGeneration(generation)) {
        return;
      }
      await _persistUpdatedPayload(response.updatedSessionPayload);
      if (!_isCurrentResourceListGeneration(generation)) {
        return;
      }
      state = state.copyWith(
        resources: response.records,
        resourcesLoading: false,
      );
    } on FfiAuthError catch (error) {
      if (!_isCurrentResourceListGeneration(generation)) {
        return;
      }
      await _handleSessionError(
        error,
        fallbackPhase: ClientPhase.authenticated,
      );
      state = state.copyWith(resourcesLoading: false);
    } catch (error) {
      if (!_isCurrentResourceListGeneration(generation)) {
        return;
      }
      state = state.copyWith(
        resourcesLoading: false,
        errorMessage: '课程资料加载失败：$error',
      );
    }
  }

  Future<void> selectResource(FfiCourseResourceSummary resource) async {
    unawaited(_cancelActiveResourceDownloadSilently());
    state = state.copyWith(
      selectedResourceId: resource.resourceId,
      resourceDetailLoading: true,
      downloadedPaths: const [],
      resourceDownloadProgressCurrent: 0,
      resourceDownloadProgressTotal: 0,
      resourceDownloadBytes: 0,
      clearResourceDownloadTask: true,
      clearResourceDownloadCurrentFileName: true,
      clearResourceDetail: true,
      clearOperationMessage: true,
      clearError: true,
    );
    final payload = await _readSessionPayloadOrUnauthenticated();
    if (payload == null) {
      state = state.copyWith(resourceDetailLoading: false);
      return;
    }
    final gateway = ref.read(openCloudGatewayProvider);
    try {
      final response = await gateway.resourceDetail(
        sessionPayload: payload,
        resourceId: resource.resourceId,
        siteId: resource.siteId,
        siteName: resource.siteName,
      );
      if (state.selectedResourceId != resource.resourceId) {
        if (state.selectedResourceId == null) {
          state = state.copyWith(resourceDetailLoading: false);
        }
        return;
      }
      await _persistUpdatedPayload(response.updatedSessionPayload);
      state = state.copyWith(
        resourceDetail: response.detail,
        resourceDetailLoading: false,
      );
    } on FfiAuthError catch (error) {
      if (error.code == FfiAuthErrorCode.sessionExpired) {
        await _handleSessionError(
          error,
          fallbackPhase: ClientPhase.authenticated,
        );
        return;
      }
      if (state.selectedResourceId != resource.resourceId) {
        if (state.selectedResourceId == null) {
          state = state.copyWith(resourceDetailLoading: false);
        }
        return;
      }
      await _handleSessionError(
        error,
        fallbackPhase: ClientPhase.authenticated,
      );
      if (state.phase == ClientPhase.authenticated) {
        state = state.copyWith(
          resourceDetailLoading: false,
          clearResourceSelection: true,
        );
      } else {
        state = state.copyWith(resourceDetailLoading: false);
      }
    } catch (error) {
      if (state.selectedResourceId != resource.resourceId) {
        if (state.selectedResourceId == null) {
          state = state.copyWith(resourceDetailLoading: false);
        }
        return;
      }
      state = state.copyWith(
        resourceDetailLoading: false,
        clearResourceSelection: true,
        errorMessage: '资料详情加载失败：$error',
      );
    }
  }

  void clearResourceSelection() {
    unawaited(_cancelActiveResourceDownloadSilently());
    state = state.copyWith(
      resourceDetailLoading: false,
      resourceDownloading: false,
      downloadedPaths: const [],
      resourceDownloadTaskId: null,
      resourceDownloadProgressCurrent: 0,
      resourceDownloadProgressTotal: 0,
      resourceDownloadBytes: 0,
      clearResourceSelection: true,
      clearResourceDownloadTask: true,
      clearResourceDownloadCurrentFileName: true,
      clearOperationMessage: true,
      clearError: true,
    );
  }

  Future<void> downloadResource(String outputPath) async {
    final detail = state.resourceDetail;
    if (detail == null) {
      state = state.copyWith(errorMessage: '请先选择一个资料。');
      return;
    }
    final payload = await _readSessionPayloadOrUnauthenticated();
    if (payload == null) {
      return;
    }
    final resourceId = detail.resourceId;
    final siteId = detail.siteId;
    _resourceDownloadGeneration += 1;
    final downloadGeneration = _resourceDownloadGeneration;
    state = state.copyWith(
      resourceDownloading: true,
      resourceDownloadProgressCurrent: 0,
      resourceDownloadProgressTotal: 1,
      resourceDownloadBytes: 0,
      resourceDownloadCurrentFileName: detail.name,
      downloadedPaths: const [],
      operationContext: OperationContext.resourceDetail,
      clearResourceDownloadTask: true,
      clearError: true,
      clearOperationMessage: true,
    );
    final gateway = ref.read(openCloudGatewayProvider);
    try {
      final response = await gateway.resourceDownloadStart(
        sessionPayload: payload,
        resourceId: resourceId,
        siteId: siteId,
        siteName: detail.siteName,
        outputPath: outputPath,
      );
      if (downloadGeneration != _resourceDownloadGeneration) {
        await gateway.downloadTaskCancel(taskId: response.taskId);
        await gateway.downloadTaskDispose(taskId: response.taskId);
        return;
      }
      state = state.copyWith(
        resourceDownloadTaskId: response.taskId,
        resourceDownloadProgressCurrent: response.status.current,
        resourceDownloadProgressTotal: response.status.total,
      );
      await _startResourceDownloadPolling(
        response.taskId,
        downloadGeneration,
        OperationContext.resourceDetail,
        isStillCurrent: () =>
            state.selectedTab == ClientTab.resources &&
            state.selectedResourceId == resourceId &&
            state.resourceDetail?.resourceId == resourceId &&
            state.resourceDetail?.siteId == siteId,
      );
    } on FfiAuthError catch (error) {
      if (downloadGeneration != _resourceDownloadGeneration &&
          error.code != FfiAuthErrorCode.sessionExpired) {
        return;
      }
      await _handleSessionError(
        error,
        fallbackPhase: ClientPhase.authenticated,
      );
      if (downloadGeneration == _resourceDownloadGeneration) {
        state = state.copyWith(
          resourceDownloading: false,
          clearResourceDownloadTask: true,
          clearResourceDownloadCurrentFileName: true,
        );
      }
    } catch (error) {
      if (downloadGeneration != _resourceDownloadGeneration) {
        return;
      }
      state = state.copyWith(
        resourceDownloading: false,
        clearResourceDownloadTask: true,
        clearResourceDownloadCurrentFileName: true,
        errorMessage: '资料下载失败：$error',
      );
    }
  }

  Future<void> downloadCourseResources(String outputDir) async {
    if (state.resources.isEmpty) {
      state = state.copyWith(errorMessage: '当前课程暂无可下载资料。');
      return;
    }
    final first = state.resources.first;
    final siteId = first.siteId;
    final siteName = first.siteName;
    final payload = await _readSessionPayloadOrUnauthenticated();
    if (payload == null) {
      return;
    }
    _resourceDownloadGeneration += 1;
    final downloadGeneration = _resourceDownloadGeneration;
    state = state.copyWith(
      resourceDownloading: true,
      resourceDownloadProgressCurrent: 0,
      resourceDownloadProgressTotal: state.resources.length,
      resourceDownloadBytes: 0,
      downloadedPaths: const [],
      operationContext: OperationContext.resourceList,
      clearResourceDownloadTask: true,
      clearResourceDownloadCurrentFileName: true,
      clearOperationMessage: true,
      clearError: true,
    );
    final gateway = ref.read(openCloudGatewayProvider);
    try {
      final response = await gateway.resourceDownloadCourseStart(
        sessionPayload: payload,
        siteId: siteId,
        siteName: siteName,
        outputDir: outputDir,
      );
      if (downloadGeneration != _resourceDownloadGeneration) {
        await gateway.downloadTaskCancel(taskId: response.taskId);
        await gateway.downloadTaskDispose(taskId: response.taskId);
        return;
      }
      state = state.copyWith(
        resourceDownloadTaskId: response.taskId,
        resourceDownloadProgressCurrent: response.status.current,
        resourceDownloadProgressTotal: response.status.total == 0
            ? state.resources.length
            : response.status.total,
      );
      await _startResourceDownloadPolling(
        response.taskId,
        downloadGeneration,
        OperationContext.resourceList,
        isStillCurrent: () =>
            state.selectedTab == ClientTab.resources &&
            state.selectedResourceCourseId == siteId,
      );
    } on FfiAuthError catch (error) {
      if (downloadGeneration != _resourceDownloadGeneration &&
          error.code != FfiAuthErrorCode.sessionExpired) {
        return;
      }
      await _handleSessionError(
        error,
        fallbackPhase: ClientPhase.authenticated,
      );
      if (downloadGeneration == _resourceDownloadGeneration) {
        state = state.copyWith(
          resourceDownloading: false,
          clearResourceDownloadTask: true,
          clearResourceDownloadCurrentFileName: true,
        );
      }
    } catch (error) {
      if (downloadGeneration != _resourceDownloadGeneration) {
        return;
      }
      state = state.copyWith(
        resourceDownloading: false,
        clearResourceDownloadTask: true,
        clearResourceDownloadCurrentFileName: true,
        errorMessage: '课程资料下载失败：$error',
      );
    }
  }

  Future<void> cancelActiveResourceDownload({OperationContext? context}) async {
    final taskId = state.resourceDownloadTaskId;
    if (taskId == null) {
      if (state.resourceDownloading) {
        _resourceDownloadGeneration += 1;
        state = state.copyWith(
          resourceDownloading: false,
          operationMessage: '下载已取消',
          operationContext: context ?? state.operationContext,
          clearResourceDownloadCurrentFileName: true,
        );
      }
      return;
    }
    _resourceDownloadGeneration += 1;
    _resourceDownloadPollTimer?.cancel();
    _resourceDownloadPollTimer = null;
    final gateway = ref.read(openCloudGatewayProvider);
    try {
      final status = await gateway.downloadTaskCancel(taskId: taskId);
      await _persistUpdatedPayload(status.updatedSessionPayload);
      state = state.copyWith(
        resourceDownloading: false,
        downloadedPaths: status.writtenPaths,
        resourceDownloadProgressCurrent: status.current,
        resourceDownloadProgressTotal: status.total,
        resourceDownloadBytes: status.bytesDownloaded.toInt(),
        operationMessage: '下载已取消',
        operationContext: context ?? state.operationContext,
        clearResourceDownloadTask: true,
        clearResourceDownloadCurrentFileName: true,
      );
    } catch (_) {
      state = state.copyWith(
        resourceDownloading: false,
        clearResourceDownloadTask: true,
        clearResourceDownloadCurrentFileName: true,
      );
    } finally {
      try {
        await gateway.downloadTaskDispose(taskId: taskId);
      } catch (_) {}
    }
  }

  Future<void> _cancelActiveResourceDownloadSilently() async {
    final taskId = state.resourceDownloadTaskId;
    if (taskId == null) {
      if (state.resourceDownloading) {
        _resourceDownloadGeneration += 1;
        _resourceDownloadPollTimer?.cancel();
        _resourceDownloadPollTimer = null;
      }
      return;
    }
    _resourceDownloadGeneration += 1;
    _resourceDownloadPollTimer?.cancel();
    _resourceDownloadPollTimer = null;
    final gateway = ref.read(openCloudGatewayProvider);
    try {
      await gateway.downloadTaskCancel(taskId: taskId);
    } catch (_) {}
    try {
      await gateway.downloadTaskDispose(taskId: taskId);
    } catch (_) {}
  }

  Future<void> _startResourceDownloadPolling(
    String taskId,
    int downloadGeneration,
    OperationContext context, {
    required bool Function() isStillCurrent,
  }) async {
    _resourceDownloadPollTimer?.cancel();
    _resourceDownloadPollTimer = Timer.periodic(
      const Duration(milliseconds: 300),
      (timer) {
        unawaited(
          _pollResourceDownloadTaskIfIdle(
            taskId,
            downloadGeneration,
            context,
            isStillCurrent: isStillCurrent,
          ),
        );
      },
    );
    await _pollResourceDownloadTaskIfIdle(
      taskId,
      downloadGeneration,
      context,
      isStillCurrent: isStillCurrent,
    );
  }

  Future<void> _pollResourceDownloadTaskIfIdle(
    String taskId,
    int downloadGeneration,
    OperationContext context, {
    required bool Function() isStillCurrent,
  }) async {
    if (_resourceDownloadPollInFlight) {
      return;
    }
    _resourceDownloadPollInFlight = true;
    try {
      await _pollResourceDownloadTask(
        taskId,
        downloadGeneration,
        context,
        isStillCurrent: isStillCurrent,
      );
    } finally {
      _resourceDownloadPollInFlight = false;
    }
  }

  Future<void> _pollResourceDownloadTask(
    String taskId,
    int downloadGeneration,
    OperationContext context, {
    required bool Function() isStillCurrent,
  }) async {
    if (downloadGeneration != _resourceDownloadGeneration) {
      return;
    }
    final gateway = ref.read(openCloudGatewayProvider);
    final FfiDownloadTaskStatus status;
    try {
      status = await gateway.downloadTaskStatus(taskId: taskId);
    } catch (error) {
      if (downloadGeneration != _resourceDownloadGeneration) {
        return;
      }
      _resourceDownloadPollTimer?.cancel();
      _resourceDownloadPollTimer = null;
      state = state.copyWith(
        resourceDownloading: false,
        errorMessage: '下载状态更新失败：$error',
        clearResourceDownloadTask: true,
        clearResourceDownloadCurrentFileName: true,
      );
      return;
    }

    if (downloadGeneration != _resourceDownloadGeneration) {
      return;
    }
    await _persistUpdatedPayload(status.updatedSessionPayload);

    final terminal = switch (status.state) {
      FfiDownloadTaskState.succeeded ||
      FfiDownloadTaskState.failed ||
      FfiDownloadTaskState.cancelled ||
      FfiDownloadTaskState.disposed => true,
      _ => false,
    };

    if (!isStillCurrent()) {
      if (terminal) {
        await gateway.downloadTaskDispose(taskId: taskId);
      }
      return;
    }

    if (!terminal && _matchesCurrentResourceDownloadStatus(status)) {
      return;
    }

    state = state.copyWith(
      resourceDownloading: !terminal,
      downloadedPaths: status.writtenPaths,
      resourceDownloadProgressCurrent: status.current,
      resourceDownloadProgressTotal: status.total,
      resourceDownloadBytes: status.bytesDownloaded.toInt(),
      resourceDownloadCurrentFileName: status.currentFileName,
      operationMessage:
          terminal && status.state == FfiDownloadTaskState.succeeded
          ? _downloadMessage(status.writtenPaths.length)
          : terminal && status.state == FfiDownloadTaskState.cancelled
          ? '下载已取消'
          : null,
      operationContext: context,
      errorMessage: terminal && status.state == FfiDownloadTaskState.failed
          ? status.errorMessage ?? '下载失败。'
          : null,
      clearResourceDownloadTask: terminal,
      clearResourceDownloadCurrentFileName: terminal,
    );

    if (terminal) {
      _resourceDownloadPollTimer?.cancel();
      _resourceDownloadPollTimer = null;
      await gateway.downloadTaskDispose(taskId: taskId);
    }
  }

  String _downloadMessage(int count) {
    return '已下载 $count 个资料文件';
  }

  bool _matchesCurrentResourceDownloadStatus(FfiDownloadTaskStatus status) {
    return state.resourceDownloading &&
        _stringListsEqual(state.downloadedPaths, status.writtenPaths) &&
        state.resourceDownloadProgressCurrent == status.current &&
        state.resourceDownloadProgressTotal == status.total &&
        state.resourceDownloadBytes == status.bytesDownloaded.toInt() &&
        state.resourceDownloadCurrentFileName == status.currentFileName;
  }

  bool _stringListsEqual(List<String> left, List<String> right) {
    if (identical(left, right)) {
      return true;
    }
    if (left.length != right.length) {
      return false;
    }
    for (var index = 0; index < left.length; index += 1) {
      if (left[index] != right[index]) {
        return false;
      }
    }
    return true;
  }

  Future<void> _loadCourses(
    String sessionPayload,
    FfiAuthSessionResponse session, [
    FfiClientCapabilities? capabilities,
  ]) async {
    final gateway = ref.read(openCloudGatewayProvider);
    final storage = ref.read(sessionStorageProvider);
    try {
      final response = await gateway.courses(
        sessionPayload: sessionPayload,
        withGoing: true,
      );
      final updatedPayload = response.updatedSessionPayload;
      if (updatedPayload != null) {
        await storage.writeSessionPayload(updatedPayload);
      }
      final goingBySite = {
        for (final going in response.goingSites) going.siteId: going.groupId,
      };
      final courses = [
        for (final course in response.records)
          CourseItem(
            id: course.id,
            name: course.siteName,
            going: goingBySite.containsKey(course.id),
            groupId: goingBySite[course.id],
          ),
      ];
      final courseIds = {for (final course in courses) course.id};
      final nextAssignmentCourseId = state.selectedAssignmentCourseId;
      final assignmentCourseApplies =
          state.assignmentView == AssignmentView.course;
      final keepAssignmentCourse =
          !assignmentCourseApplies ||
          nextAssignmentCourseId == null ||
          courseIds.contains(nextAssignmentCourseId);
      final fallbackAssignmentCourseId = courses.isEmpty
          ? null
          : courses.first.id;
      final nextResourceCourseId = state.selectedResourceCourseId;
      final keepResourceCourse =
          nextResourceCourseId == null ||
          courseIds.contains(nextResourceCourseId);
      final fallbackResourceCourseId = courses.isEmpty
          ? null
          : courses.first.id;
      if (!keepResourceCourse) {
        _resourceListGeneration += 1;
        unawaited(_cancelActiveResourceDownloadSilently());
      }

      state = state.copyWith(
        phase: ClientPhase.authenticated,
        session: session,
        capabilities: capabilities ?? state.capabilities,
        courses: courses,
        assignmentView: keepAssignmentCourse
            ? state.assignmentView
            : fallbackAssignmentCourseId == null
            ? AssignmentView.undone
            : AssignmentView.course,
        selectedAssignmentCourseId: !assignmentCourseApplies
            ? null
            : keepAssignmentCourse
            ? state.selectedAssignmentCourseId
            : fallbackAssignmentCourseId,
        clearSelectedAssignmentCourse:
            !assignmentCourseApplies ||
            (!keepAssignmentCourse && fallbackAssignmentCourseId == null),
        assignments: keepAssignmentCourse ? state.assignments : const [],
        assignmentsLoaded: keepAssignmentCourse
            ? state.assignmentsLoaded
            : false,
        assignmentsLoading: keepAssignmentCourse
            ? state.assignmentsLoading
            : false,
        assignmentDetailLoading: keepAssignmentCourse
            ? state.assignmentDetailLoading
            : false,
        resources: keepResourceCourse ? state.resources : const [],
        resourcesLoading: keepResourceCourse ? state.resourcesLoading : false,
        resourceDetailLoading: keepResourceCourse
            ? state.resourceDetailLoading
            : false,
        selectedResourceCourseId: keepResourceCourse
            ? state.selectedResourceCourseId
            : fallbackResourceCourseId,
        clearSelectedResourceCourse:
            !keepResourceCourse && fallbackResourceCourseId == null,
        resourceDownloading: keepResourceCourse
            ? state.resourceDownloading
            : false,
        downloadedPaths: keepResourceCourse ? state.downloadedPaths : const [],
        resourceDownloadProgressCurrent: keepResourceCourse
            ? state.resourceDownloadProgressCurrent
            : 0,
        resourceDownloadProgressTotal: keepResourceCourse
            ? state.resourceDownloadProgressTotal
            : 0,
        resourceDownloadBytes: keepResourceCourse
            ? state.resourceDownloadBytes
            : 0,
        clearAssignmentSelection: !keepAssignmentCourse,
        clearResourceSelection: !keepResourceCourse,
        clearResourceDownloadTask: !keepResourceCourse,
        clearResourceDownloadCurrentFileName: !keepResourceCourse,
        clearOperationMessage: !keepAssignmentCourse || !keepResourceCourse,
        clearError: true,
      );
    } on FfiAuthError catch (error) {
      if (error.code == FfiAuthErrorCode.sessionExpired) {
        await storage.clearSessionPayload();
        state = ClientState(
          phase: ClientPhase.unauthenticated,
          errorMessage: error.message,
        );
        return;
      }
      state = state.copyWith(
        phase: ClientPhase.authenticated,
        session: session,
        capabilities: capabilities ?? state.capabilities,
        courses: state.courses,
        errorMessage: error.message,
      );
    } catch (error) {
      state = state.copyWith(
        phase: ClientPhase.authenticated,
        session: session,
        capabilities: capabilities ?? state.capabilities,
        courses: state.courses,
        errorMessage: '课程加载失败：$error',
      );
    }
  }

  Future<FfiClientCapabilities> _loadCapabilitiesOrDefault(
    OpenCloudGateway gateway,
  ) async {
    try {
      return await gateway.capabilities();
    } catch (_) {
      return _defaultCapabilities;
    }
  }

  Future<String?> _readSessionPayloadOrUnauthenticated() async {
    final storage = ref.read(sessionStorageProvider);
    try {
      final payload = await storage.readSessionPayload();
      if (payload == null || payload.isEmpty) {
        state = const ClientState(phase: ClientPhase.unauthenticated);
        return null;
      }
      return payload;
    } catch (error) {
      state = state.copyWith(errorMessage: '无法读取安全存储：$error');
      return null;
    }
  }

  Future<void> _persistUpdatedPayload(String? payload) async {
    if (payload != null) {
      await ref.read(sessionStorageProvider).writeSessionPayload(payload);
    }
  }

  Future<void> _handleSessionError(
    FfiAuthError error, {
    required ClientPhase fallbackPhase,
  }) async {
    if (error.code == FfiAuthErrorCode.sessionExpired) {
      await ref.read(sessionStorageProvider).clearSessionPayload();
      state = ClientState(
        phase: ClientPhase.unauthenticated,
        errorMessage: error.message,
      );
      return;
    }
    state = state.copyWith(phase: fallbackPhase, errorMessage: error.message);
  }

  CourseItem? _courseById(String siteId) {
    for (final course in state.courses) {
      if (course.id == siteId) {
        return course;
      }
    }
    return null;
  }

  bool _isCurrentAssignmentListGeneration(int generation) {
    return generation == _assignmentListGeneration;
  }

  bool _isCurrentResourceListGeneration(int generation) {
    return generation == _resourceListGeneration;
  }
}
