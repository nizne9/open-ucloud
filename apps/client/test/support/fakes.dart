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
    this.sessionSummaryError,
  });

  final FfiAuthSessionResponse? session;
  final FfiCourseResponse courseResponse;
  final FfiAuthError? sessionSummaryError;
  bool initialized = false;

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
  Future<FfiCourseResponse> courses({
    required String sessionPayload,
    required bool withGoing,
  }) async {
    return courseResponse;
  }

  @override
  Future<FfiLogoutResponse> logout() async {
    return const FfiLogoutResponse(clearSession: true);
  }
}
