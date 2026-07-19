import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_cloud_ffi/open_cloud_ffi.dart';

import 'client_state.dart';
import 'open_cloud_gateway.dart';
import 'session_storage.dart';

export 'client_state.dart';

final sessionStorageProvider = Provider<OpenCloudSessionStorage>(
  (_) => SecureOpenCloudSessionStorage(),
);

final openCloudGatewayProvider = Provider<OpenCloudGateway>(
  (_) => FfiOpenCloudGateway(),
);

final clientControllerProvider =
    NotifierProvider<ClientController, ClientState>(ClientController.new);

class ClientController extends Notifier<ClientState> {
  String? _pendingPassword;
  String? _lastPersistedPayload;
  int _assignmentListGeneration = 0;
  int _resourceListGeneration = 0;
  int _resourceDownloadGeneration = 0;
  int _downloadItemSerial = 0;
  bool _downloadQueuePumping = false;
  bool _resourceDownloadPollInFlight = false;
  Timer? _resourceDownloadPollTimer;
  List<FfiAssignmentSummary>? _undoneAssignmentsCache;
  final _courseAssignmentsCache = <String, List<FfiAssignmentSummary>>{};

  @override
  ClientState build() {
    ref.onDispose(() {
      _pendingPassword = null;
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
        errorMessage: '无法读取安全存储：${displayErrorText(error)}',
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
        errorMessage: '无法恢复登录会话：${displayErrorText(error)}',
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

    _pendingPassword = password;
    state = ClientState(
      phase: ClientPhase.startingLogin,
      pendingUsername: normalizedUsername,
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
      _pendingPassword = null;
      state = ClientState(
        phase: ClientPhase.unauthenticated,
        errorMessage: error.message,
      );
    } catch (error) {
      _pendingPassword = null;
      state = ClientState(
        phase: ClientPhase.unauthenticated,
        errorMessage: '登录初始化失败：${displayErrorText(error)}',
      );
    }
  }

  Future<void> finishLogin({
    required String? captcha,
    FfiLoginFlow? flow,
  }) async {
    final activeFlow = flow ?? state.loginFlow;
    final username = state.pendingUsername;
    final password = _pendingPassword;
    if (activeFlow == null || username == null || password == null) {
      _pendingPassword = null;
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
      _pendingPassword = null;
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
      final canRetryCaptcha =
          activeFlow.captchaId != null && _pendingPassword != null;
      if (!canRetryCaptcha) {
        _pendingPassword = null;
      }
      state = state.copyWith(
        phase: canRetryCaptcha
            ? ClientPhase.awaitingCaptcha
            : ClientPhase.unauthenticated,
        errorMessage: error.message,
      );
    } catch (error) {
      final canRetryCaptcha =
          activeFlow.captchaId != null && _pendingPassword != null;
      if (!canRetryCaptcha) {
        _pendingPassword = null;
      }
      state = state.copyWith(
        phase: canRetryCaptcha
            ? ClientPhase.awaitingCaptcha
            : ClientPhase.unauthenticated,
        errorMessage: '登录失败：${displayErrorText(error)}',
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
        errorMessage: '无法读取安全存储：${displayErrorText(error)}',
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
        attendanceQrInputError: '二维码文本解析失败：${displayErrorText(error)}',
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
    _pendingPassword = null;
    state = ClientState(
      phase: ClientPhase.unauthenticated,
      pendingUsername: state.pendingUsername,
    );
  }

  Future<void> logout() async {
    _pendingPassword = null;
    _lastPersistedPayload = null;
    _assignmentListGeneration += 1;
    _resourceListGeneration += 1;
    _resourceDownloadGeneration += 1;
    _resourceDownloadPollTimer?.cancel();
    _resourceDownloadPollTimer = null;
    _undoneAssignmentsCache = null;
    _courseAssignmentsCache.clear();
    await _cancelAllDownloads();
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
    state = state.copyWith(
      selectedTab: tab,
      clearOperationMessage: true,
      clearError: true,
    );
  }

  Future<void> loadUndoneAssignments({
    ClientTab selectedTab = ClientTab.assignments,
    bool clearGlobalError = true,
    bool refresh = false,
  }) async {
    final generation = ++_assignmentListGeneration;
    final cached = _undoneAssignmentsCache;
    if (cached != null && !refresh) {
      state = state.copyWith(
        selectedTab: selectedTab,
        assignmentView: AssignmentView.undone,
        assignments: cached,
        assignmentsLoaded: true,
        assignmentsLoading: false,
        assignmentDetailLoading: false,
        clearAssignmentSelection: true,
        clearPendingAssignmentsError: true,
        clearOperationMessage: true,
        clearError: clearGlobalError,
      );
      return;
    }
    state = state.copyWith(
      selectedTab: selectedTab,
      assignmentView: AssignmentView.undone,
      assignments: const [],
      assignmentsLoaded: false,
      assignmentsLoading: true,
      assignmentDetailLoading: false,
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
      _undoneAssignmentsCache = response.records;
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
      final message = '未完成作业加载失败：${displayErrorText(error)}';
      state = state.copyWith(
        assignmentsLoaded: false,
        assignmentsLoading: false,
        pendingAssignmentsErrorMessage: message,
        errorMessage: message,
      );
    }
  }

  Future<void> loadCourseAssignments(
    String siteId, {
    bool refresh = false,
  }) async {
    final generation = ++_assignmentListGeneration;
    final course = _courseById(siteId);
    final cached = _courseAssignmentsCache[siteId];
    if (cached != null && !refresh) {
      state = state.copyWith(
        selectedTab: ClientTab.assignments,
        assignmentView: AssignmentView.course,
        selectedAssignmentCourseId: siteId,
        assignments: cached,
        assignmentsLoaded: true,
        assignmentsLoading: false,
        assignmentDetailLoading: false,
        clearAssignmentSelection: true,
        clearOperationMessage: true,
        clearError: true,
      );
      return;
    }
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
      _courseAssignmentsCache[siteId] = response.records;
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
        errorMessage: '课程作业加载失败：${displayErrorText(error)}',
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
      state = state.copyWith(
        assignmentDetailLoading: false,
        clearAssignmentSelection: state.phase == ClientPhase.authenticated,
      );
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
      // Session expiry is handled even when the request went stale so the
      // persisted session is always cleared.
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
        errorMessage: '作业详情加载失败：${displayErrorText(error)}',
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
        errorMessage: '附件上传失败：${displayErrorText(error)}',
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
        attachment.resourceId,
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
      final undoneCache = _undoneAssignmentsCache;
      if (undoneCache != null) {
        _undoneAssignmentsCache = [
          for (final record in undoneCache)
            if (record.id != detail.id) record,
        ];
      }
      _courseAssignmentsCache.remove(detail.siteId);
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
          submittedAt: formatClientTimestamp(DateTime.now()),
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
        errorMessage: '作业提交失败：${displayErrorText(error)}',
      );
    }
  }

  Future<void> loadResourcesForCourse(String siteId) async {
    final generation = ++_resourceListGeneration;
    final course = _courseById(siteId);
    state = state.copyWith(
      selectedTab: ClientTab.resources,
      selectedResourceCourseId: siteId,
      resources: const [],
      resourcesLoading: true,
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
        errorMessage: '课程资料加载失败：${displayErrorText(error)}',
      );
    }
  }

  Future<void> selectResource(FfiCourseResourceSummary resource) async {
    state = state.copyWith(
      selectedResourceId: resource.resourceId,
      resourceDetailLoading: true,
      clearResourceDetail: true,
      clearOperationMessage: true,
      clearError: true,
    );
    final payload = await _readSessionPayloadOrUnauthenticated();
    if (payload == null) {
      state = state.copyWith(
        resourceDetailLoading: false,
        clearResourceSelection: state.phase == ClientPhase.authenticated,
      );
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
      // Session expiry is handled even when the request went stale so the
      // persisted session is always cleared.
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
        errorMessage: '资料详情加载失败：${displayErrorText(error)}',
      );
    }
  }

  void clearResourceSelection() {
    state = state.copyWith(
      resourceDetailLoading: false,
      clearResourceSelection: true,
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
    _enqueueDownload(
      label: detail.name,
      siteId: detail.siteId,
      siteName: detail.siteName,
      outputPath: outputPath,
      resourceId: detail.resourceId,
    );
  }

  Future<void> downloadCourseResources(String outputDir) async {
    if (state.resources.isEmpty) {
      state = state.copyWith(errorMessage: '当前课程暂无可下载资料。');
      return;
    }
    final first = state.resources.first;
    _enqueueDownload(
      label: first.siteName.isEmpty ? '课程资料' : first.siteName,
      siteId: first.siteId,
      siteName: first.siteName,
      outputPath: outputDir,
    );
  }

  void _enqueueDownload({
    required String label,
    required String siteId,
    required String siteName,
    required String outputPath,
    String? resourceId,
  }) {
    final duplicate = state.downloadTasks.any(
      (task) =>
          !task.isTerminal &&
          (resourceId == null
              ? task.isCourseDownload && task.siteId == siteId
              : task.resourceId == resourceId),
    );
    if (duplicate) {
      state = state.copyWith(operationMessage: '已在下载队列中：$label');
      return;
    }
    _downloadItemSerial += 1;
    final item = DownloadTaskItem(
      id: 'download-$_downloadItemSerial',
      label: label,
      siteId: siteId,
      siteName: siteName,
      outputPath: outputPath,
      resourceId: resourceId,
    );
    state = state.copyWith(
      downloadTasks: [...state.downloadTasks, item],
      operationMessage: '已加入下载队列：$label',
      clearError: true,
    );
    unawaited(_pumpDownloadQueue());
  }

  Future<void> cancelDownloadTask(String itemId) async {
    final item = _downloadTaskById(itemId);
    if (item == null) {
      return;
    }
    final taskId = item.taskId;
    if (taskId == null) {
      _removeDownloadTask(itemId);
      state = state.copyWith(operationMessage: '下载已取消');
      unawaited(_pumpDownloadQueue());
      return;
    }
    _resourceDownloadGeneration += 1;
    _resourceDownloadPollTimer?.cancel();
    _resourceDownloadPollTimer = null;
    final gateway = ref.read(openCloudGatewayProvider);
    try {
      final status = await gateway.downloadTaskCancel(taskId: taskId);
      await _persistUpdatedPayload(status.updatedSessionPayload);
      _updateDownloadTask(itemId, status: status);
      state = state.copyWith(operationMessage: '下载已取消');
    } catch (_) {
      _removeDownloadTask(itemId);
    } finally {
      try {
        await gateway.downloadTaskDispose(taskId: taskId);
      } catch (_) {}
    }
    unawaited(_pumpDownloadQueue());
  }

  void clearFinishedDownloads() {
    state = state.copyWith(
      downloadTasks: [
        for (final task in state.downloadTasks)
          if (!task.isTerminal) task,
      ],
    );
  }

  Future<void> _cancelAllDownloads() async {
    final gateway = ref.read(openCloudGatewayProvider);
    for (final task in state.downloadTasks) {
      final taskId = task.taskId;
      if (taskId == null) {
        continue;
      }
      try {
        await gateway.downloadTaskCancel(taskId: taskId);
      } catch (_) {}
      try {
        await gateway.downloadTaskDispose(taskId: taskId);
      } catch (_) {}
    }
  }

  /// Serial queue: starts the next queued item when nothing is running.
  Future<void> _pumpDownloadQueue() async {
    if (_downloadQueuePumping) {
      return;
    }
    _downloadQueuePumping = true;
    try {
      while (!state.downloadTasks.any(
        (task) => !task.isQueued && !task.isTerminal,
      )) {
        final queued = state.downloadTasks.where((task) => task.isQueued);
        if (queued.isEmpty) {
          return;
        }
        if (await _startDownloadTask(queued.first)) {
          return;
        }
        // The item failed to start and was removed; try the next one.
      }
    } finally {
      _downloadQueuePumping = false;
    }
  }

  /// Returns false when the item is gone from the queue (cancelled or failed
  /// to start) so the pump advances to the next queued item, true when it is
  /// now running.
  Future<bool> _startDownloadTask(DownloadTaskItem item) async {
    final payload = await _readSessionPayloadOrUnauthenticated();
    if (payload == null) {
      _removeDownloadTask(item.id);
      return false;
    }
    final current = _downloadTaskById(item.id);
    if (current == null || !current.isQueued) {
      return false;
    }
    final gateway = ref.read(openCloudGatewayProvider);
    try {
      final resourceId = item.resourceId;
      final response = resourceId == null
          ? await gateway.resourceDownloadCourseStart(
              sessionPayload: payload,
              siteId: item.siteId,
              siteName: item.siteName,
              outputDir: item.outputPath,
            )
          : await gateway.resourceDownloadStart(
              sessionPayload: payload,
              resourceId: resourceId,
              siteId: item.siteId,
              siteName: item.siteName,
              outputPath: item.outputPath,
            );
      if (_downloadTaskById(item.id) == null) {
        // Cancelled while the start call was in flight. Best-effort cleanup:
        // a failure here must not stall the rest of the queue.
        try {
          await gateway.downloadTaskCancel(taskId: response.taskId);
        } catch (_) {}
        try {
          await gateway.downloadTaskDispose(taskId: response.taskId);
        } catch (_) {}
        return false;
      }
      await _persistUpdatedPayload(response.status.updatedSessionPayload);
      var status = response.status;
      if (resourceId == null &&
          status.total == 0 &&
          state.resources.isNotEmpty) {
        status = _downloadTaskStatusWith(status, total: state.resources.length);
      }
      _updateDownloadTask(item.id, taskId: response.taskId, status: status);
      _startDownloadPolling(response.taskId);
      return true;
    } on FfiAuthError catch (error) {
      _removeDownloadTask(item.id);
      await _handleSessionError(
        error,
        fallbackPhase: ClientPhase.authenticated,
      );
      if (state.phase == ClientPhase.authenticated) {
        state = state.copyWith(errorMessage: '下载启动失败：${error.message}');
      }
      return false;
    } catch (error) {
      _removeDownloadTask(item.id);
      state = state.copyWith(errorMessage: '下载启动失败：${displayErrorText(error)}');
      return false;
    }
  }

  void _startDownloadPolling(String taskId) {
    _resourceDownloadPollTimer?.cancel();
    final generation = ++_resourceDownloadGeneration;
    _resourceDownloadPollTimer = Timer.periodic(
      const Duration(milliseconds: 300),
      (_) => unawaited(_pollDownloadTaskIfIdle(taskId, generation)),
    );
    unawaited(_pollDownloadTaskIfIdle(taskId, generation));
  }

  Future<void> _pollDownloadTaskIfIdle(String taskId, int generation) async {
    if (_resourceDownloadPollInFlight) {
      return;
    }
    _resourceDownloadPollInFlight = true;
    try {
      await _pollDownloadTask(taskId, generation);
    } finally {
      _resourceDownloadPollInFlight = false;
    }
  }

  Future<void> _pollDownloadTask(String taskId, int generation) async {
    if (generation != _resourceDownloadGeneration) {
      return;
    }
    final item = _downloadTaskByTaskId(taskId);
    if (item == null) {
      _resourceDownloadPollTimer?.cancel();
      _resourceDownloadPollTimer = null;
      return;
    }
    final gateway = ref.read(openCloudGatewayProvider);
    final FfiDownloadTaskStatus status;
    try {
      status = await gateway.downloadTaskStatus(taskId: taskId);
    } catch (error) {
      if (generation != _resourceDownloadGeneration) {
        return;
      }
      _resourceDownloadPollTimer?.cancel();
      _resourceDownloadPollTimer = null;
      final message = '下载状态更新失败：${displayErrorText(error)}';
      final lastKnown = item.status;
      if (lastKnown != null) {
        _updateDownloadTask(
          item.id,
          status: _downloadTaskStatusWith(
            lastKnown,
            state: FfiDownloadTaskState.failed,
            errorMessage: message,
          ),
        );
      }
      state = state.copyWith(errorMessage: message);
      try {
        await gateway.downloadTaskCancel(taskId: taskId);
      } catch (_) {}
      try {
        await gateway.downloadTaskDispose(taskId: taskId);
      } catch (_) {}
      unawaited(_pumpDownloadQueue());
      return;
    }
    if (generation != _resourceDownloadGeneration) {
      return;
    }
    await _persistUpdatedPayload(status.updatedSessionPayload);

    final terminal = isTerminalDownloadState(status.state);
    if (!terminal && _sameDownloadStatus(item.status, status)) {
      return;
    }
    _updateDownloadTask(item.id, status: status);
    if (!terminal) {
      return;
    }

    _resourceDownloadPollTimer?.cancel();
    _resourceDownloadPollTimer = null;
    try {
      await gateway.downloadTaskDispose(taskId: taskId);
    } catch (_) {}
    if (status.state == FfiDownloadTaskState.succeeded) {
      state = state.copyWith(
        operationMessage: '已下载 ${status.writtenPaths.length} 个资料文件',
      );
    } else if (status.state == FfiDownloadTaskState.failed) {
      state = state.copyWith(errorMessage: status.errorMessage ?? '下载失败。');
    }
    unawaited(_pumpDownloadQueue());
  }

  DownloadTaskItem? _downloadTaskById(String id) {
    return state.downloadTasks.where((task) => task.id == id).firstOrNull;
  }

  DownloadTaskItem? _downloadTaskByTaskId(String taskId) {
    return state.downloadTasks
        .where((task) => task.taskId == taskId)
        .firstOrNull;
  }

  void _updateDownloadTask(
    String id, {
    String? taskId,
    FfiDownloadTaskStatus? status,
  }) {
    state = state.copyWith(
      downloadTasks: [
        for (final task in state.downloadTasks)
          if (task.id == id)
            task.copyWith(taskId: taskId, status: status)
          else
            task,
      ],
    );
  }

  void _removeDownloadTask(String id) {
    state = state.copyWith(
      downloadTasks: [
        for (final task in state.downloadTasks)
          if (task.id != id) task,
      ],
    );
  }

  FfiDownloadTaskStatus _downloadTaskStatusWith(
    FfiDownloadTaskStatus status, {
    FfiDownloadTaskState? state,
    int? total,
    String? errorMessage,
  }) {
    return FfiDownloadTaskStatus(
      taskId: status.taskId,
      state: state ?? status.state,
      current: status.current,
      total: total ?? status.total,
      bytesDownloaded: status.bytesDownloaded,
      currentFileName: status.currentFileName,
      writtenPaths: status.writtenPaths,
      records: status.records,
      errorMessage: errorMessage ?? status.errorMessage,
      updatedSessionPayload: status.updatedSessionPayload,
    );
  }

  bool _sameDownloadStatus(
    FfiDownloadTaskStatus? current,
    FfiDownloadTaskStatus next,
  ) {
    if (current == null) {
      return false;
    }
    return current.state == next.state &&
        current.current == next.current &&
        current.total == next.total &&
        current.bytesDownloaded == next.bytesDownloaded &&
        current.currentFileName == next.currentFileName;
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
      _undoneAssignmentsCache = null;
      _courseAssignmentsCache.clear();
      final nextAssignmentCourseId = state.selectedAssignmentCourseId;
      final assignmentCourseApplies =
          state.assignmentView == AssignmentView.course;
      final keepAssignmentCourse =
          !assignmentCourseApplies ||
          nextAssignmentCourseId == null ||
          courseIds.contains(nextAssignmentCourseId);
      final assignmentSelectionValid =
          nextAssignmentCourseId != null &&
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
      }

      state = state.copyWith(
        phase: ClientPhase.authenticated,
        session: session,
        capabilities: capabilities ?? state.capabilities,
        courses: courses,
        coursesSyncedAt: DateTime.now(),
        assignmentView: keepAssignmentCourse
            ? state.assignmentView
            : fallbackAssignmentCourseId == null
            ? AssignmentView.undone
            : AssignmentView.course,
        selectedAssignmentCourseId: assignmentSelectionValid
            ? state.selectedAssignmentCourseId
            : assignmentCourseApplies
            ? fallbackAssignmentCourseId
            : null,
        clearSelectedAssignmentCourse:
            !assignmentSelectionValid &&
            (!assignmentCourseApplies || fallbackAssignmentCourseId == null),
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
        clearAssignmentSelection: !keepAssignmentCourse,
        clearResourceSelection: !keepResourceCourse,
        clearOperationMessage: !keepAssignmentCourse || !keepResourceCourse,
        clearError: true,
      );
    } on FfiAuthError catch (error) {
      if (error.code == FfiAuthErrorCode.sessionExpired) {
        _pendingPassword = null;
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
        errorMessage: '课程加载失败：${displayErrorText(error)}',
      );
    }
  }

  Future<FfiClientCapabilities> _loadCapabilitiesOrDefault(
    OpenCloudGateway gateway,
  ) async {
    try {
      return await gateway.capabilities();
    } catch (_) {
      return defaultClientCapabilities;
    }
  }

  Future<String?> _readSessionPayloadOrUnauthenticated() async {
    final storage = ref.read(sessionStorageProvider);
    try {
      final payload = await storage.readSessionPayload();
      if (payload == null || payload.isEmpty) {
        _pendingPassword = null;
        state = const ClientState(phase: ClientPhase.unauthenticated);
        return null;
      }
      return payload;
    } catch (error) {
      state = state.copyWith(
        errorMessage: '无法读取安全存储：${displayErrorText(error)}',
      );
      return null;
    }
  }

  Future<void> _persistUpdatedPayload(String? payload) async {
    if (payload == null || payload == _lastPersistedPayload) {
      return;
    }
    _lastPersistedPayload = payload;
    await ref.read(sessionStorageProvider).writeSessionPayload(payload);
  }

  Future<void> _handleSessionError(
    FfiAuthError error, {
    required ClientPhase fallbackPhase,
  }) async {
    if (error.code == FfiAuthErrorCode.sessionExpired) {
      _pendingPassword = null;
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
