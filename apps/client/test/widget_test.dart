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

  testWidgets('assignment refresh uses selected course', (tester) async {
    final gateway = FakeOpenCloudGateway(
      session: _session(),
      courseResponse: _twoCourseResponse(),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sessionStorageProvider.overrideWithValue(
            MemorySessionStorage('payload'),
          ),
          openCloudGatewayProvider.overrideWithValue(gateway),
        ],
        child: const OpenCloudApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('作业'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('按课程'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('计算机网络').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('刷新作业'));
    await tester.pumpAndSettle();

    expect(gateway.lastCourseAssignmentsSiteId, 'site-2');
  });

  testWidgets('resource refresh uses selected course', (tester) async {
    final gateway = FakeOpenCloudGateway(
      session: _session(),
      courseResponse: _twoCourseResponse(),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sessionStorageProvider.overrideWithValue(
            MemorySessionStorage('payload'),
          ),
          openCloudGatewayProvider.overrideWithValue(gateway),
        ],
        child: const OpenCloudApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('资料'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('计算机网络').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('刷新资料'));
    await tester.pumpAndSettle();

    expect(gateway.lastResourcesSiteId, 'site-2');
  });
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

FfiCourseResponse _twoCourseResponse() {
  return const FfiCourseResponse(
    records: [
      FfiCourseSite(id: 'site-1', siteName: '软件测试'),
      FfiCourseSite(id: 'site-2', siteName: '计算机网络'),
    ],
    goingSites: [],
  );
}
