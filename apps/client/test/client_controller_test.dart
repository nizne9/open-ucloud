import 'package:flutter_test/flutter_test.dart';
import 'package:open_cloud_client/src/client_controller.dart';
import 'package:open_cloud_client/src/open_cloud_gateway.dart';
import 'package:open_cloud_ffi/open_cloud_ffi.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'support/fakes.dart';

void main() {
  test('restores session and persists refreshed payload', () async {
    final storage = MemorySessionStorage('old-payload');
    final gateway = FakeOpenCloudGateway(
      session: _session(),
      courseResponse: const FfiCourseResponse(
        records: [FfiCourseSite(id: 'site-1', siteName: '软件测试')],
        goingSites: [FfiGoingSite(groupId: 'group-1', siteId: 'site-1')],
        updatedSessionPayload: 'new-payload',
      ),
    );
    final container = _container(storage: storage, gateway: gateway);

    await container.read(clientControllerProvider.notifier).bootstrap();

    final state = container.read(clientControllerProvider);
    expect(state.phase, ClientPhase.authenticated);
    expect(state.courses.single.going, isTrue);
    expect(storage.payload, 'new-payload');
  });

  test('clears storage when persisted session is expired', () async {
    final storage = MemorySessionStorage('expired-payload');
    final gateway = FakeOpenCloudGateway(
      sessionSummaryError: const FfiAuthError(
        code: FfiAuthErrorCode.sessionExpired,
        message: 'expired',
      ),
    );
    final container = _container(storage: storage, gateway: gateway);

    await container.read(clientControllerProvider.notifier).bootstrap();

    final state = container.read(clientControllerProvider);
    expect(state.phase, ClientPhase.unauthenticated);
    expect(state.errorMessage, 'expired');
    expect(storage.payload, isNull);
  });

  test('storage read failures return to unauthenticated state', () async {
    final storage = MemorySessionStorage('payload', Exception('locked'));
    final gateway = FakeOpenCloudGateway(session: _session());
    final container = _container(storage: storage, gateway: gateway);

    await container.read(clientControllerProvider.notifier).bootstrap();

    final state = container.read(clientControllerProvider);
    expect(state.phase, ClientPhase.unauthenticated);
    expect(state.errorMessage, contains('无法读取安全存储'));
    expect(storage.payload, isNull);
    expect(gateway.initialized, isFalse);
  });

  test('refresh storage read failures keep existing courses visible', () async {
    final storage = MemorySessionStorage('payload');
    final gateway = FakeOpenCloudGateway(
      session: _session(),
      courseResponse: const FfiCourseResponse(
        records: [FfiCourseSite(id: 'site-1', siteName: '软件测试')],
        goingSites: [],
      ),
    );
    final container = _container(storage: storage, gateway: gateway);
    await container.read(clientControllerProvider.notifier).bootstrap();
    storage.readError = Exception('locked');

    await container.read(clientControllerProvider.notifier).refreshCourses();

    final state = container.read(clientControllerProvider);
    expect(state.phase, ClientPhase.authenticated);
    expect(state.courses.single.name, '软件测试');
    expect(state.errorMessage, contains('无法读取安全存储'));
    expect(gateway.coursesCalls, 1);
  });

  test('logout clears secure storage', () async {
    final storage = MemorySessionStorage('payload');
    final container = _container(
      storage: storage,
      gateway: FakeOpenCloudGateway(session: _session()),
    );

    await container.read(clientControllerProvider.notifier).logout();

    expect(storage.payload, isNull);
    expect(
      container.read(clientControllerProvider).phase,
      ClientPhase.unauthenticated,
    );
  });
}

ProviderContainer _container({
  required MemorySessionStorage storage,
  required OpenCloudGateway gateway,
}) {
  return ProviderContainer(
    overrides: [
      sessionStorageProvider.overrideWithValue(storage),
      openCloudGatewayProvider.overrideWithValue(gateway),
    ],
  );
}

FfiAuthSessionResponse _session() {
  return const FfiAuthSessionResponse(
    selectedRole: FfiRoleName.student,
    user: FfiSessionUser(
      account: '2024000000',
      realName: 'Alice',
      userId: 'u-1',
      userName: '2024000000',
    ),
  );
}
