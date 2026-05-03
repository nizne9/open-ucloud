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

class ClientState {
  const ClientState({
    required this.phase,
    this.session,
    this.loginFlow,
    this.pendingUsername,
    this.pendingPassword,
    this.captchaImage,
    this.courses = const [],
    this.errorMessage,
  });

  const ClientState.bootstrapping() : this(phase: ClientPhase.bootstrapping);

  final ClientPhase phase;
  final FfiAuthSessionResponse? session;
  final FfiLoginFlow? loginFlow;
  final String? pendingUsername;
  final String? pendingPassword;
  final String? captchaImage;
  final List<CourseItem> courses;
  final String? errorMessage;

  bool get isBusy =>
      phase == ClientPhase.bootstrapping ||
      phase == ClientPhase.startingLogin ||
      phase == ClientPhase.finishingLogin ||
      phase == ClientPhase.loadingCourses;

  ClientState copyWith({
    ClientPhase? phase,
    FfiAuthSessionResponse? session,
    FfiLoginFlow? loginFlow,
    String? pendingUsername,
    String? pendingPassword,
    String? captchaImage,
    List<CourseItem>? courses,
    String? errorMessage,
    bool clearSession = false,
    bool clearLogin = false,
    bool clearError = false,
  }) {
    return ClientState(
      phase: phase ?? this.phase,
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
  @override
  ClientState build() => const ClientState.bootstrapping();

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
      final session = await gateway.sessionSummary(payload);
      state = ClientState(phase: ClientPhase.loadingCourses, session: session);
      await _loadCourses(payload, session);
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
      state = ClientState(phase: ClientPhase.loadingCourses, session: session);
      await _loadCourses(result.sessionPayload, session);
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
    final payload = await storage.readSessionPayload();
    final session = state.session;
    if (payload == null || session == null) {
      state = const ClientState(phase: ClientPhase.unauthenticated);
      return;
    }
    state = state.copyWith(phase: ClientPhase.loadingCourses, clearError: true);
    await _loadCourses(payload, session);
  }

  Future<void> logout() async {
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

  Future<void> _loadCourses(
    String sessionPayload,
    FfiAuthSessionResponse session,
  ) async {
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
      state = ClientState(
        phase: ClientPhase.authenticated,
        session: session,
        courses: [
          for (final course in response.records)
            CourseItem(
              id: course.id,
              name: course.siteName,
              going: goingBySite.containsKey(course.id),
              groupId: goingBySite[course.id],
            ),
        ],
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
      state = ClientState(
        phase: ClientPhase.authenticated,
        session: session,
        courses: state.courses,
        errorMessage: error.message,
      );
    } catch (error) {
      state = ClientState(
        phase: ClientPhase.authenticated,
        session: session,
        courses: state.courses,
        errorMessage: '课程加载失败：$error',
      );
    }
  }
}
