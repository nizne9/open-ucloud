import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_cloud_client/src/app.dart';
import 'package:open_cloud_client/src/client_controller.dart';
import 'package:open_cloud_ffi/open_cloud_ffi.dart';

import 'support/fakes.dart';

void main() {
  testWidgets('shows login form when no session exists', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sessionStorageProvider.overrideWithValue(MemorySessionStorage()),
          openCloudGatewayProvider.overrideWithValue(FakeOpenCloudGateway()),
        ],
        child: const OpenCloudApp(),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('登录 Open UCloud'), findsOneWidget);
    expect(find.byIcon(Icons.person_outline), findsOneWidget);
    expect(find.byIcon(Icons.lock_outline), findsOneWidget);
  });

  testWidgets('restores session and renders courses', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sessionStorageProvider.overrideWithValue(
            MemorySessionStorage('payload'),
          ),
          openCloudGatewayProvider.overrideWithValue(
            FakeOpenCloudGateway(
              session: const FfiAuthSessionResponse(
                selectedRole: FfiRoleName.student,
                user: FfiSessionUser(
                  account: '2024000000',
                  realName: 'Alice',
                  userId: 'u-1',
                  userName: '2024000000',
                ),
              ),
              courseResponse: const FfiCourseResponse(
                records: [FfiCourseSite(id: 'site-1', siteName: '软件测试')],
                goingSites: [
                  FfiGoingSite(groupId: 'group-1', siteId: 'site-1'),
                ],
              ),
            ),
          ),
        ],
        child: const OpenCloudApp(),
      ),
    );
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('Alice'), findsOneWidget);
    expect(find.text('软件测试'), findsOneWidget);
    expect(find.byIcon(Icons.notifications_active_outlined), findsOneWidget);
  });
}
