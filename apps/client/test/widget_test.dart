import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_cloud_client/src/app.dart';
import 'package:open_cloud_client/src/client_controller.dart';
import 'package:open_cloud_ffi/open_cloud_ffi.dart';

import 'support/fakes.dart';

void main() {
  testWidgets('uses side navigation on expanded desktop width', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sessionStorageProvider.overrideWithValue(
            MemorySessionStorage('payload'),
          ),
          openCloudGatewayProvider.overrideWithValue(
            FakeOpenCloudGateway(
              session: _session(),
              courseResponse: const FfiCourseResponse(
                records: [FfiCourseSite(id: 'site-1', siteName: '软件测试')],
                goingSites: [],
              ),
            ),
          ),
        ],
        child: const OpenCloudApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('总览工作台'), findsWidgets);
    expect(find.text('查看课程、待交作业和资料更新。'), findsOneWidget);
    expect(find.text('登录状态'), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
    expect(find.byType(NavigationBar), findsNothing);
  });

  testWidgets('uses rail navigation on medium desktop width', (tester) async {
    tester.view.physicalSize = const Size(900, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sessionStorageProvider.overrideWithValue(
            MemorySessionStorage('payload'),
          ),
          openCloudGatewayProvider.overrideWithValue(
            FakeOpenCloudGateway(
              session: _session(),
              courseResponse: const FfiCourseResponse(
                records: [FfiCourseSite(id: 'site-1', siteName: '软件测试')],
                goingSites: [],
              ),
            ),
          ),
        ],
        child: const OpenCloudApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.text('总览'), findsWidgets);
  });

  testWidgets('dashboard loads pending assignments and shows account context', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final gateway = FakeOpenCloudGateway(
      session: _session(),
      courseResponse: const FfiCourseResponse(
        records: [
          FfiCourseSite(id: 'site-1', siteName: '软件测试'),
          FfiCourseSite(id: 'site-2', siteName: '计算机网络'),
        ],
        goingSites: [FfiGoingSite(groupId: 'group-1', siteId: 'site-1')],
      ),
      undoneAssignmentsResponse: const FfiAssignmentListResponse(
        records: [
          FfiAssignmentSummary(
            endTime: '2026-05-03 23:59:59',
            id: 'work-1',
            siteId: 'site-1',
            siteName: '软件测试',
            source: 'undone',
            startTime: '',
            status: FfiAssignmentStatus.pending,
            title: '实验报告',
          ),
        ],
      ),
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

    expect(find.text('今天需要关注'), findsOneWidget);
    expect(find.text('2'), findsWidgets);
    expect(find.text('本期课程'), findsOneWidget);
    expect(find.text('1'), findsWidgets);
    expect(find.text('待提交作业'), findsWidgets);
    expect(find.text('二维码文本'), findsOneWidget);
    expect(find.text('签到状态'), findsNothing);
    expect(find.text('实验报告'), findsWidgets);
    expect(find.text('Alice'), findsWidgets);
    expect(find.text('已登录'), findsOneWidget);
  });

  testWidgets(
    'dashboard stops automatic pending assignment retry after failure',
    (tester) async {
      tester.view.physicalSize = const Size(900, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final gateway = FakeOpenCloudGateway(
        session: _session(),
        courseResponse: const FfiCourseResponse(
          records: [FfiCourseSite(id: 'site-1', siteName: '软件测试')],
          goingSites: [],
        ),
        undoneAssignmentsError: Exception('network down'),
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

      for (var i = 0; i < 8; i += 1) {
        await tester.pump();
      }

      expect(gateway.undoneAssignmentsCalls, 1);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(OpenCloudApp)),
      );
      expect(
        container.read(clientControllerProvider).errorMessage,
        contains('未完成作业加载失败'),
      );
      expect(find.textContaining('未完成作业加载失败'), findsOneWidget);
      expect(find.text('当前没有待提交作业'), findsNothing);
    },
  );

  testWidgets('dashboard pending load ignores unrelated course errors', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final gateway = FakeOpenCloudGateway(
      session: _session(),
      courseError: Exception('courses down'),
      undoneAssignmentsResponse: const FfiAssignmentListResponse(
        records: [
          FfiAssignmentSummary(
            endTime: '2026-05-03 23:59:59',
            id: 'pending-after-course-error',
            siteId: 'site-1',
            siteName: '软件测试',
            source: 'undone',
            startTime: '',
            status: FfiAssignmentStatus.pending,
            title: '课程错误后的待办',
          ),
        ],
      ),
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

    expect(gateway.coursesCalls, 1);
    expect(gateway.undoneAssignmentsCalls, 1);
    expect(find.textContaining('课程加载失败'), findsOneWidget);
    expect(find.text('课程错误后的待办'), findsWidgets);
    expect(find.text('重试待办'), findsNothing);
  });

  testWidgets('assignment tab does not duplicate an active dashboard load', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final pendingAssignments = Completer<FfiAssignmentListResponse>();
    final gateway = FakeOpenCloudGateway(
      session: _session(),
      courseResponse: const FfiCourseResponse(
        records: [FfiCourseSite(id: 'site-1', siteName: '软件测试')],
        goingSites: [],
      ),
      undoneAssignmentsFuture: pendingAssignments.future,
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

    for (var i = 0; i < 8; i += 1) {
      await tester.pump();
      if (gateway.undoneAssignmentsCalls == 1) {
        break;
      }
    }

    expect(gateway.undoneAssignmentsCalls, 1);

    await tester.tap(find.text('作业'));
    await tester.pump();

    pendingAssignments.complete(const FfiAssignmentListResponse(records: []));
    await tester.pumpAndSettle();

    expect(gateway.undoneAssignmentsCalls, 1);
  });

  testWidgets(
    'dashboard reloads pending assignments after course assignment list',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final gateway = FakeOpenCloudGateway(
        session: _session(),
        courseResponse: const FfiCourseResponse(
          records: [FfiCourseSite(id: 'site-1', siteName: '软件测试')],
          goingSites: [],
        ),
        undoneAssignmentsResponse: const FfiAssignmentListResponse(
          records: [
            FfiAssignmentSummary(
              endTime: '2026-05-03 23:59:59',
              id: 'pending-1',
              siteId: 'site-1',
              siteName: '软件测试',
              source: 'undone',
              startTime: '',
              status: FfiAssignmentStatus.pending,
              title: '默认待办',
            ),
          ],
        ),
        courseAssignmentsResponse: const FfiAssignmentListResponse(
          records: [
            FfiAssignmentSummary(
              endTime: '2026-05-10 23:59:59',
              id: 'course-1',
              siteId: 'site-1',
              siteName: '软件测试',
              source: 'course',
              startTime: '',
              status: FfiAssignmentStatus.submitted,
              title: '课程作业',
            ),
          ],
        ),
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

      expect(find.text('默认待办'), findsWidgets);

      await tester.tap(find.text('查看作业'));
      await tester.pumpAndSettle();

      expect(find.text('课程作业'), findsOneWidget);

      await tester.tap(find.text('总览'));
      await tester.pumpAndSettle();

      expect(gateway.undoneAssignmentsCalls, 2);
      expect(find.text('默认待办'), findsWidgets);
      expect(find.text('课程作业'), findsNothing);
    },
  );

  testWidgets('account page exposes session actions', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sessionStorageProvider.overrideWithValue(
            MemorySessionStorage('payload'),
          ),
          openCloudGatewayProvider.overrideWithValue(
            FakeOpenCloudGateway(
              session: _session(),
              courseResponse: const FfiCourseResponse(
                records: [FfiCourseSite(id: 'site-1', siteName: '软件测试')],
                goingSites: [],
              ),
            ),
          ),
        ],
        child: const OpenCloudApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.person_outline));
    await tester.pumpAndSettle();

    expect(find.text('账户状态'), findsOneWidget);
    expect(find.text('Alice'), findsWidgets);
    expect(find.text('退出登录'), findsOneWidget);
    expect(find.text('同步课程'), findsWidgets);
    expect(find.byIcon(Icons.brightness_6_outlined), findsOneWidget);
  });

  testWidgets('compact layout uses bottom navigation with four entries', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sessionStorageProvider.overrideWithValue(
            MemorySessionStorage('payload'),
          ),
          openCloudGatewayProvider.overrideWithValue(
            FakeOpenCloudGateway(
              session: _session(),
              courseResponse: const FfiCourseResponse(
                records: [FfiCourseSite(id: 'site-1', siteName: '软件测试')],
                goingSites: [],
              ),
            ),
          ),
        ],
        child: const OpenCloudApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(BottomNavigationBar), findsOneWidget);
    expect(find.text('总览'), findsWidgets);
    expect(find.text('作业'), findsWidgets);
    expect(find.text('资料'), findsWidgets);
    expect(find.text('账户'), findsWidgets);
  });

  testWidgets('course actions do not overflow on narrow width', (tester) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sessionStorageProvider.overrideWithValue(
            MemorySessionStorage('payload'),
          ),
          openCloudGatewayProvider.overrideWithValue(
            FakeOpenCloudGateway(
              session: _session(),
              courseResponse: const FfiCourseResponse(
                records: [FfiCourseSite(id: 'site-1', siteName: '软件测试课程实践')],
                goingSites: [],
              ),
            ),
          ),
        ],
        child: const OpenCloudApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('查看作业'), findsOneWidget);
    expect(find.text('查看资料'), findsOneWidget);
  });

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

  testWidgets('captcha step is accessible and can return to credentials', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sessionStorageProvider.overrideWithValue(MemorySessionStorage()),
          openCloudGatewayProvider.overrideWithValue(
            FakeOpenCloudGateway(
              authStartResponse: FfiAuthStartResponse(
                auth: const FfiAuthStartResult(
                  captchaImage:
                      'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAFgwJ/lra3NwAAAABJRU5ErkJggg==',
                  flowId: 'flow-1',
                  requiresCaptcha: true,
                ),
                flow: FfiLoginFlow(
                  captchaId: 'captcha-1',
                  cookie: 'cookie',
                  createdAtMs: BigInt.one,
                  execution: 'flow-1',
                  username: 'alice',
                ),
              ),
            ),
          ),
        ],
        child: const OpenCloudApp(),
      ),
    );
    await tester.pump();
    await tester.pump();

    await tester.enterText(find.widgetWithText(TextField, '用户名'), 'alice');
    await tester.enterText(find.widgetWithText(TextField, '密码'), 'secret');
    await tester.tap(find.widgetWithText(FilledButton, '继续'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(TextField, '验证码'), findsOneWidget);
    expect(find.bySemanticsLabel('验证码图片'), findsOneWidget);
    expect(find.widgetWithText(TextButton, '修改账号密码'), findsOneWidget);

    await tester.tap(find.text('修改账号密码'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(TextField, '用户名'), findsOneWidget);
    expect(find.widgetWithText(TextField, '密码'), findsOneWidget);
    expect(find.widgetWithText(TextField, '验证码'), findsNothing);
  });

  testWidgets('restores session and renders courses', (tester) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

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

    expect(find.text('Alice'), findsWidgets);
    expect(find.text('软件测试'), findsOneWidget);
    expect(find.byIcon(Icons.notifications_active_outlined), findsOneWidget);
    expect(find.text('site-1 · 活动进行中'), findsOneWidget);
    expect(find.text('site-1 · going'), findsNothing);
    expect(find.text('解析二维码'), findsNothing);
  });

  testWidgets('renders QR parser entry when capability is enabled', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sessionStorageProvider.overrideWithValue(
            MemorySessionStorage('payload'),
          ),
          openCloudGatewayProvider.overrideWithValue(
            FakeOpenCloudGateway(
              capabilitiesResponse: const FfiClientCapabilities(
                selfAttendance: false,
                attendanceQrPayloadParsing: true,
              ),
              session: _session(),
              courseResponse: const FfiCourseResponse(
                records: [FfiCourseSite(id: 'site-1', siteName: '软件测试')],
                goingSites: [],
              ),
            ),
          ),
        ],
        child: const OpenCloudApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('解析二维码'), findsOneWidget);
  });

  testWidgets('renders QR parser entry even when no courses are loaded', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sessionStorageProvider.overrideWithValue(
            MemorySessionStorage('payload'),
          ),
          openCloudGatewayProvider.overrideWithValue(
            FakeOpenCloudGateway(
              capabilitiesResponse: const FfiClientCapabilities(
                selfAttendance: false,
                attendanceQrPayloadParsing: true,
              ),
              session: _session(),
              courseResponse: const FfiCourseResponse(
                records: [],
                goingSites: [],
              ),
            ),
          ),
        ],
        child: const OpenCloudApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('暂无课程'), findsOneWidget);
    expect(find.text('解析二维码'), findsOneWidget);
  });

  testWidgets('QR parser displays fields and matching course', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sessionStorageProvider.overrideWithValue(
            MemorySessionStorage('payload'),
          ),
          openCloudGatewayProvider.overrideWithValue(
            FakeOpenCloudGateway(
              capabilitiesResponse: const FfiClientCapabilities(
                selfAttendance: false,
                attendanceQrPayloadParsing: true,
              ),
              session: _session(),
              courseResponse: const FfiCourseResponse(
                records: [FfiCourseSite(id: 'site-1', siteName: '软件测试')],
                goingSites: [
                  FfiGoingSite(groupId: 'group-1', siteId: 'site-1'),
                ],
              ),
              parseAttendanceQrPayloadResponse: const FfiAttendanceQrPayload(
                attendanceId: 'attendance-1',
                siteId: 'site-1',
                createTime: '2026-05-09 10:00:00+08:00',
                classLessonId: 'lesson-1',
              ),
            ),
          ),
        ],
        child: const OpenCloudApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('解析二维码'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, '二维码文本'),
      'checkwork|id=attendance-1&siteId=site-1&createTime=2026-05-09 10:00:00+08:00&classLessonId=lesson-1',
    );
    await tester.tap(find.widgetWithText(FilledButton, '解析'));
    await tester.pumpAndSettle();

    expect(find.text('解析签到二维码内容'), findsOneWidget);
    expect(find.text('attendance-1'), findsOneWidget);
    expect(find.text('site-1'), findsWidgets);
    expect(find.text('2026-05-09 10:00:00+08:00'), findsOneWidget);
    expect(find.text('lesson-1'), findsOneWidget);
    expect(find.text('软件测试'), findsWidgets);
    expect(find.text('正在进行'), findsWidgets);

    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('解析二维码'));
    await tester.pumpAndSettle();

    expect(find.text('解析签到二维码内容'), findsOneWidget);
    expect(find.text('attendance-1'), findsNothing);
    expect(find.text('2026-05-09 10:00:00+08:00'), findsNothing);
  });

  testWidgets('QR parser shows invalid payload error', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sessionStorageProvider.overrideWithValue(
            MemorySessionStorage('payload'),
          ),
          openCloudGatewayProvider.overrideWithValue(
            FakeOpenCloudGateway(
              capabilitiesResponse: const FfiClientCapabilities(
                selfAttendance: false,
                attendanceQrPayloadParsing: true,
              ),
              session: _session(),
              courseResponse: const FfiCourseResponse(
                records: [FfiCourseSite(id: 'site-1', siteName: '软件测试')],
                goingSites: [],
              ),
              parseAttendanceQrPayloadError: const FfiAuthError(
                code: FfiAuthErrorCode.unknownAuthError,
                message: 'invalid checkwork payload',
              ),
            ),
          ),
        ],
        child: const OpenCloudApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('解析二维码'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, '二维码文本'), 'bad');
    await tester.tap(find.widgetWithText(FilledButton, '解析'));
    await tester.pumpAndSettle();

    expect(find.text('invalid checkwork payload'), findsOneWidget);
    expect(find.text('解析签到二维码内容'), findsOneWidget);
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

  testWidgets('assignment course picker resets after course refresh fallback', (
    tester,
  ) async {
    final gateway = FakeOpenCloudGateway(
      session: _session(),
      courseResponses: const [
        FfiCourseResponse(
          records: [
            FfiCourseSite(id: 'site-old', siteName: '旧课程'),
            FfiCourseSite(id: 'site-other', siteName: '其他课程'),
          ],
          goingSites: [],
        ),
        FfiCourseResponse(
          records: [FfiCourseSite(id: 'site-new', siteName: '新课程')],
          goingSites: [],
        ),
      ],
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
    await tester.tap(find.text('其他课程').last);
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(OpenCloudApp)),
    );
    expect(
      container.read(clientControllerProvider).selectedAssignmentCourseId,
      'site-other',
    );

    await container.read(clientControllerProvider.notifier).refreshCourses();
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('新课程'), findsOneWidget);
    expect(
      container.read(clientControllerProvider).selectedAssignmentCourseId,
      'site-new',
    );
  });

  testWidgets('assignment detail renders html content as readable blocks', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sessionStorageProvider.overrideWithValue(
            MemorySessionStorage('payload'),
          ),
          openCloudGatewayProvider.overrideWithValue(
            FakeOpenCloudGateway(
              session: _session(),
              undoneAssignmentsResponse: const FfiAssignmentListResponse(
                records: [
                  FfiAssignmentSummary(
                    endTime: '2026-05-03 23:59:59',
                    id: 'work-1',
                    siteId: 'site-1',
                    siteName: '机器学习',
                    source: 'undone',
                    startTime: '',
                    status: FfiAssignmentStatus.pending,
                    title: 'Transformer 作业',
                  ),
                ],
              ),
              assignmentDetailResponse: const FfiAssignmentDetailResponse(
                className: '',
                comment: '',
                content:
                    '<div>'
                    '<h3><strong>任务 1：基础 Transformer 编码器的文本分类</strong></h3>'
                    '<p>掌握&nbsp;<strong>Transformer</strong> 模型。</p>'
                    '<p>\n  格式化 <strong>HTML</strong>\n</p>'
                    '<p>第一行<br>第二行</p>'
                    '<pre>code\nline</pre>'
                    '<p><a href="https://example.com/spec">参考链接</a> 和 <code>BERT</code></p>'
                    '<ol><li>实现从零构建基础 Transformer 编码器。</li>'
                    '<li>使用 <code>BERT</code> 进行微调。</li></ol>'
                    '</div>',
                endTime: '2026-05-03 23:59:59',
                id: 'work-1',
                isOvertimeCommit: false,
                siteId: 'site-1',
                siteName: '机器学习',
                startTime: '',
                status: FfiAssignmentStatus.pending,
                submittedAt: '',
                submittedAttachments: [],
                submittedContent: '',
                teacherResources: [],
                title: 'Transformer 作业',
              ),
            ),
          ),
        ],
        child: const OpenCloudApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('作业'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Transformer 作业'));
    await tester.pump();
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();

    expect(find.textContaining('<h3>'), findsNothing);
    expect(find.text('任务 1：基础 Transformer 编码器的文本分类'), findsOneWidget);
    expect(find.text('掌握 Transformer 模型。'), findsOneWidget);
    expect(find.text('格式化 HTML'), findsOneWidget);
    expect(find.text('第一行\n第二行'), findsOneWidget);
    expect(find.text('code\nline'), findsOneWidget);
    expect(find.text('参考链接 (https://example.com/spec) 和 BERT'), findsOneWidget);
    expect(find.text('1. 实现从零构建基础 Transformer 编码器。'), findsOneWidget);
    expect(find.text('2. 使用 BERT 进行微调。'), findsOneWidget);
  });

  testWidgets('assignment list lazily scrolls and opens details', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(640, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final assignments = List.generate(
      60,
      (index) => FfiAssignmentSummary(
        endTime: '2026-05-${(index % 28) + 1} 23:59:59',
        id: 'work-${index + 1}',
        siteId: 'site-1',
        siteName: '软件测试',
        source: 'undone',
        startTime: '',
        status: FfiAssignmentStatus.pending,
        title: '作业 ${index + 1}',
      ),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sessionStorageProvider.overrideWithValue(
            MemorySessionStorage('payload'),
          ),
          openCloudGatewayProvider.overrideWithValue(
            FakeOpenCloudGateway(
              session: _session(),
              courseResponse: _twoCourseResponse(),
              undoneAssignmentsResponse: FfiAssignmentListResponse(
                records: assignments,
              ),
              assignmentDetailResponse: const FfiAssignmentDetailResponse(
                className: '',
                comment: '',
                content: '长列表详情',
                endTime: '2026-05-28 23:59:59',
                id: 'work-60',
                isOvertimeCommit: false,
                siteId: 'site-1',
                siteName: '软件测试',
                startTime: '',
                status: FfiAssignmentStatus.pending,
                submittedAt: '',
                submittedAttachments: [],
                submittedContent: '',
                teacherResources: [],
                title: '作业 60 详情',
              ),
            ),
          ),
        ],
        child: const OpenCloudApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('作业'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('作业 60'),
      500,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('作业 60'));
    await tester.pump();
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();

    expect(find.text('返回作业列表'), findsOneWidget);
    expect(find.text('作业 60 详情'), findsOneWidget);
    expect(find.text('长列表详情'), findsOneWidget);
  });

  testWidgets('assignment draft survives unrelated detail state changes', (
    tester,
  ) async {
    final upload = Completer<FfiAssignmentUploadResponse>();
    final container = ProviderContainer(
      overrides: [
        sessionStorageProvider.overrideWithValue(
          MemorySessionStorage('payload'),
        ),
        openCloudGatewayProvider.overrideWithValue(
          FakeOpenCloudGateway(
            session: _session(),
            undoneAssignmentsResponse: const FfiAssignmentListResponse(
              records: [
                FfiAssignmentSummary(
                  endTime: '2026-05-03 23:59:59',
                  id: 'work-1',
                  siteId: 'site-1',
                  siteName: '机器学习',
                  source: 'undone',
                  startTime: '',
                  status: FfiAssignmentStatus.pending,
                  title: '草稿作业',
                ),
              ],
            ),
            assignmentDetailResponse: const FfiAssignmentDetailResponse(
              className: '',
              comment: '',
              content: '',
              endTime: '2026-05-03 23:59:59',
              id: 'work-1',
              isOvertimeCommit: false,
              siteId: 'site-1',
              siteName: '机器学习',
              startTime: '',
              status: FfiAssignmentStatus.pending,
              submittedAt: '',
              submittedAttachments: [],
              submittedContent: '',
              teacherResources: [],
              title: '草稿作业',
            ),
            assignmentUploadFuture: upload.future,
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const OpenCloudApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('作业'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('草稿作业'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '本地输入的草稿');
    await tester.pump();

    final uploadTask = container
        .read(clientControllerProvider.notifier)
        .uploadAssignmentAttachment('/tmp/report.pdf');
    await tester.pump();

    expect(find.text('本地输入的草稿'), findsOneWidget);

    upload.complete(
      const FfiAssignmentUploadResponse(
        assignmentId: 'work-1',
        fileName: 'report.pdf',
        resourceId: 'resource-1',
        siteId: 'site-1',
        siteName: '机器学习',
      ),
    );
    await uploadTask;
  });

  testWidgets('assignment draft edits do not rebuild the assignment pane', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sessionStorageProvider.overrideWithValue(
            MemorySessionStorage('payload'),
          ),
          openCloudGatewayProvider.overrideWithValue(
            FakeOpenCloudGateway(
              session: _session(),
              undoneAssignmentsResponse: const FfiAssignmentListResponse(
                records: [
                  FfiAssignmentSummary(
                    endTime: '2026-05-03 23:59:59',
                    id: 'work-1',
                    siteId: 'site-1',
                    siteName: '机器学习',
                    source: 'undone',
                    startTime: '',
                    status: FfiAssignmentStatus.pending,
                    title: '草稿作业',
                  ),
                ],
              ),
              assignmentDetailResponse: const FfiAssignmentDetailResponse(
                className: '',
                comment: '',
                content: '',
                endTime: '2026-05-03 23:59:59',
                id: 'work-1',
                isOvertimeCommit: false,
                siteId: 'site-1',
                siteName: '机器学习',
                startTime: '',
                status: FfiAssignmentStatus.pending,
                submittedAt: '',
                submittedAttachments: [],
                submittedContent: '',
                teacherResources: [],
                title: '草稿作业',
              ),
            ),
          ),
        ],
        child: const OpenCloudApp(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('作业'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('草稿作业'));
    await tester.pumpAndSettle();

    final previousDebugPrint = debugPrint;
    final previousRebuildDebug = debugPrintRebuildDirtyWidgets;
    final rebuildLogs = <String>[];
    debugPrint = (message, {wrapWidth}) {
      if (message != null) {
        rebuildLogs.add(message);
      }
    };
    debugPrintRebuildDirtyWidgets = true;
    try {
      await tester.enterText(find.byType(TextField).last, '草稿内容');
      await tester.pump();
    } finally {
      debugPrint = previousDebugPrint;
      debugPrintRebuildDirtyWidgets = previousRebuildDebug;
    }

    expect(
      rebuildLogs.where((line) => line.contains('_AssignmentsPane')),
      isEmpty,
    );
    expect(
      rebuildLogs.where((line) => line.contains('_AssignmentDetailCard')),
      isEmpty,
    );
  });

  testWidgets('narrow assignment detail has a back path to the list', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(640, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sessionStorageProvider.overrideWithValue(
            MemorySessionStorage('payload'),
          ),
          openCloudGatewayProvider.overrideWithValue(
            FakeOpenCloudGateway(
              session: _session(),
              undoneAssignmentsResponse: const FfiAssignmentListResponse(
                records: [
                  FfiAssignmentSummary(
                    endTime: '2026-05-03 23:59:59',
                    id: 'work-1',
                    siteId: 'site-1',
                    siteName: '软件测试',
                    source: 'undone',
                    startTime: '',
                    status: FfiAssignmentStatus.pending,
                    title: '实验报告',
                  ),
                ],
              ),
            ),
          ),
        ],
        child: const OpenCloudApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('作业'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('实验报告'));
    await tester.pumpAndSettle();

    expect(find.text('返回作业列表'), findsOneWidget);
    expect(find.widgetWithText(TextField, '提交内容'), findsOneWidget);

    await tester.tap(find.text('返回作业列表'));
    await tester.pumpAndSettle();

    expect(find.text('实验报告'), findsOneWidget);
    expect(find.text('返回作业列表'), findsNothing);
  });

  testWidgets('assignment detail exposes submission metadata and attachments', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sessionStorageProvider.overrideWithValue(
            MemorySessionStorage('payload'),
          ),
          openCloudGatewayProvider.overrideWithValue(
            FakeOpenCloudGateway(
              session: _session(),
              undoneAssignmentsResponse: const FfiAssignmentListResponse(
                records: [
                  FfiAssignmentSummary(
                    endTime: '2026-05-03 23:59:59',
                    id: 'work-1',
                    siteId: 'site-1',
                    siteName: '软件测试',
                    source: 'undone',
                    startTime: '',
                    status: FfiAssignmentStatus.submitted,
                    title: '实验报告',
                  ),
                ],
              ),
              assignmentDetailResponse: const FfiAssignmentDetailResponse(
                className: '1 班',
                comment: '写得不错',
                content: '完成实验',
                endTime: '2026-05-03 23:59:59',
                id: 'work-1',
                isOvertimeCommit: true,
                score: 95,
                siteId: 'site-1',
                siteName: '软件测试',
                startTime: '2026-05-01 08:00:00',
                status: FfiAssignmentStatus.submitted,
                submittedAt: '2026-05-02 20:00:00',
                submittedAttachments: [
                  FfiAssignmentResource(
                    name: '答案.pdf',
                    previewUrl: 'https://example.com/answer.pdf',
                    resourceId: 'submitted-1',
                  ),
                ],
                submittedContent: '答案',
                teacherResources: [
                  FfiAssignmentResource(
                    name: '模板.docx',
                    previewUrl: 'https://example.com/template.docx',
                    resourceId: 'teacher-1',
                  ),
                ],
                title: '实验报告',
              ),
            ),
          ),
        ],
        child: const OpenCloudApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('作业'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('实验报告'));
    await tester.pumpAndSettle();

    expect(find.text('成绩 95.0'), findsOneWidget);
    expect(find.text('提交 2026-05-02 20:00:00'), findsOneWidget);
    expect(find.text('教师批语'), findsOneWidget);
    expect(find.text('写得不错'), findsOneWidget);
    expect(find.text('教师附件'), findsOneWidget);
    expect(find.text('模板.docx'), findsOneWidget);
    expect(find.text('已提交附件'), findsOneWidget);
    expect(find.text('答案.pdf'), findsWidgets);
    expect(find.byTooltip('打开链接'), findsNWidgets(3));
    expect(find.byTooltip('复制链接'), findsNWidgets(3));
    expect(find.widgetWithText(TextField, '提交内容'), findsOneWidget);
    expect(find.widgetWithText(TextField, '提交内容（只读）'), findsNothing);
    expect(find.widgetWithText(FilledButton, '重新提交'), findsOneWidget);

    await tester.ensureVisible(find.widgetWithText(FilledButton, '重新提交'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '重新提交'));
    await tester.pumpAndSettle();

    expect(find.text('重新提交'), findsWidgets);
    expect(find.textContaining('覆盖/更新'), findsOneWidget);
  });

  testWidgets('expired assignment detail remains read-only', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sessionStorageProvider.overrideWithValue(
            MemorySessionStorage('payload'),
          ),
          openCloudGatewayProvider.overrideWithValue(
            FakeOpenCloudGateway(
              session: _session(),
              undoneAssignmentsResponse: const FfiAssignmentListResponse(
                records: [
                  FfiAssignmentSummary(
                    endTime: '2026-05-03 23:59:59',
                    id: 'work-1',
                    siteId: 'site-1',
                    siteName: '软件测试',
                    source: 'undone',
                    startTime: '',
                    status: FfiAssignmentStatus.expired,
                    title: '过期实验报告',
                  ),
                ],
              ),
              assignmentDetailResponse: const FfiAssignmentDetailResponse(
                className: '',
                comment: '',
                content: '完成实验',
                endTime: '2026-05-03 23:59:59',
                id: 'work-1',
                isOvertimeCommit: false,
                siteId: 'site-1',
                siteName: '软件测试',
                startTime: '',
                status: FfiAssignmentStatus.expired,
                submittedAt: '',
                submittedAttachments: [],
                submittedContent: '旧答案',
                teacherResources: [],
                title: '过期实验报告',
              ),
            ),
          ),
        ],
        child: const OpenCloudApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('作业'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('过期实验报告'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(TextField, '提交内容（只读）'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, '添加附件'), findsOneWidget);
    expect(
      tester
          .widget<OutlinedButton>(find.widgetWithText(OutlinedButton, '添加附件'))
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '提交'))
          .onPressed,
      isNull,
    );
  });

  testWidgets('assignment draft asks before leaving and keeps text on cancel', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sessionStorageProvider.overrideWithValue(
            MemorySessionStorage('payload'),
          ),
          openCloudGatewayProvider.overrideWithValue(
            FakeOpenCloudGateway(
              session: _session(),
              courseResponse: _twoCourseResponse(),
              undoneAssignmentsResponse: const FfiAssignmentListResponse(
                records: [
                  FfiAssignmentSummary(
                    endTime: '2026-05-03 23:59:59',
                    id: 'work-1',
                    siteId: 'site-1',
                    siteName: '软件测试',
                    source: 'undone',
                    startTime: '',
                    status: FfiAssignmentStatus.pending,
                    title: '实验报告',
                  ),
                ],
              ),
              assignmentDetailResponse: const FfiAssignmentDetailResponse(
                className: '',
                comment: '',
                content: '完成实验',
                endTime: '2026-05-03 23:59:59',
                id: 'work-1',
                isOvertimeCommit: false,
                siteId: 'site-1',
                siteName: '软件测试',
                startTime: '',
                status: FfiAssignmentStatus.pending,
                submittedAt: '',
                submittedAttachments: [],
                submittedContent: '',
                teacherResources: [],
                title: '实验报告',
              ),
            ),
          ),
        ],
        child: const OpenCloudApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('作业'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('实验报告'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, '提交内容'), '未提交答案');
    await tester.pumpAndSettle();

    await tester.tap(find.text('返回作业列表'));
    await tester.pumpAndSettle();

    expect(find.text('放弃未提交的修改？'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.text('未提交答案'), findsOneWidget);

    await tester.tap(find.widgetWithText(OutlinedButton, '同步课程'));
    await tester.pumpAndSettle();

    expect(find.text('放弃未提交的修改？'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.text('未提交答案'), findsOneWidget);

    await tester.tap(find.text('资料'));
    await tester.pumpAndSettle();

    expect(find.text('放弃未提交的修改？'), findsOneWidget);
    await tester.tap(find.text('放弃修改'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('作业'));
    await tester.pumpAndSettle();

    expect(find.text('未提交答案'), findsNothing);
    expect(find.text('返回作业列表'), findsNothing);
  });

  testWidgets('draft attachments are not shown as submitted attachments', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [
        sessionStorageProvider.overrideWithValue(
          MemorySessionStorage('payload'),
        ),
        openCloudGatewayProvider.overrideWithValue(
          FakeOpenCloudGateway(
            session: _session(),
            undoneAssignmentsResponse: const FfiAssignmentListResponse(
              records: [
                FfiAssignmentSummary(
                  endTime: '2026-05-03 23:59:59',
                  id: 'work-1',
                  siteId: 'site-1',
                  siteName: '软件测试',
                  source: 'undone',
                  startTime: '',
                  status: FfiAssignmentStatus.pending,
                  title: '实验报告',
                ),
              ],
            ),
            assignmentDetailResponse: const FfiAssignmentDetailResponse(
              className: '',
              comment: '',
              content: '完成实验',
              endTime: '2026-05-03 23:59:59',
              id: 'work-1',
              isOvertimeCommit: false,
              siteId: 'site-1',
              siteName: '软件测试',
              startTime: '',
              status: FfiAssignmentStatus.pending,
              submittedAt: '',
              submittedAttachments: [],
              submittedContent: '',
              teacherResources: [],
              title: '实验报告',
            ),
            assignmentUploadResponse: const FfiAssignmentUploadResponse(
              assignmentId: 'work-1',
              fileName: 'draft.pdf',
              resourceId: 'draft-1',
              siteId: 'site-1',
              siteName: '软件测试',
            ),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const OpenCloudApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('作业'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('实验报告'));
    await tester.pumpAndSettle();

    await container
        .read(clientControllerProvider.notifier)
        .uploadAssignmentAttachment('/tmp/draft.pdf');
    await tester.pumpAndSettle();

    expect(find.text('draft.pdf'), findsOneWidget);
    expect(find.text('已提交附件'), findsNothing);
  });

  testWidgets('draft attachment preview offers open and copy actions', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [
        sessionStorageProvider.overrideWithValue(
          MemorySessionStorage('payload'),
        ),
        openCloudGatewayProvider.overrideWithValue(
          FakeOpenCloudGateway(
            session: _session(),
            undoneAssignmentsResponse: const FfiAssignmentListResponse(
              records: [
                FfiAssignmentSummary(
                  endTime: '2026-05-03 23:59:59',
                  id: 'work-1',
                  siteId: 'site-1',
                  siteName: '软件测试',
                  source: 'undone',
                  startTime: '',
                  status: FfiAssignmentStatus.pending,
                  title: '实验报告',
                ),
              ],
            ),
            assignmentDetailResponse: const FfiAssignmentDetailResponse(
              className: '',
              comment: '',
              content: '完成实验',
              endTime: '2026-05-03 23:59:59',
              id: 'work-1',
              isOvertimeCommit: false,
              siteId: 'site-1',
              siteName: '软件测试',
              startTime: '',
              status: FfiAssignmentStatus.pending,
              submittedAt: '',
              submittedAttachments: [],
              submittedContent: '',
              teacherResources: [],
              title: '实验报告',
            ),
            assignmentUploadResponse: const FfiAssignmentUploadResponse(
              assignmentId: 'work-1',
              fileName: 'draft.pdf',
              previewUrl: 'https://example.com/draft.pdf',
              resourceId: 'draft-1',
              siteId: 'site-1',
              siteName: '软件测试',
            ),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const OpenCloudApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('作业'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('实验报告'));
    await tester.pumpAndSettle();

    await container
        .read(clientControllerProvider.notifier)
        .uploadAssignmentAttachment('/tmp/draft.pdf');
    await tester.pumpAndSettle();

    expect(find.text('draft.pdf'), findsOneWidget);
    expect(find.byTooltip('打开链接'), findsOneWidget);
    expect(find.byTooltip('复制链接'), findsOneWidget);
  });

  testWidgets('narrow assignment detail shows operation feedback', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(640, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final container = ProviderContainer(
      overrides: [
        sessionStorageProvider.overrideWithValue(
          MemorySessionStorage('payload'),
        ),
        openCloudGatewayProvider.overrideWithValue(
          FakeOpenCloudGateway(
            session: _session(),
            undoneAssignmentsResponse: const FfiAssignmentListResponse(
              records: [
                FfiAssignmentSummary(
                  endTime: '2026-05-03 23:59:59',
                  id: 'work-1',
                  siteId: 'site-1',
                  siteName: '软件测试',
                  source: 'undone',
                  startTime: '',
                  status: FfiAssignmentStatus.pending,
                  title: '实验报告',
                ),
              ],
            ),
            assignmentDetailResponse: const FfiAssignmentDetailResponse(
              className: '',
              comment: '',
              content: '完成实验',
              endTime: '2026-05-03 23:59:59',
              id: 'work-1',
              isOvertimeCommit: false,
              siteId: 'site-1',
              siteName: '软件测试',
              startTime: '',
              status: FfiAssignmentStatus.pending,
              submittedAt: '',
              submittedAttachments: [],
              submittedContent: '',
              teacherResources: [],
              title: '实验报告',
            ),
            assignmentUploadResponse: const FfiAssignmentUploadResponse(
              assignmentId: 'work-1',
              fileName: 'draft.pdf',
              resourceId: 'draft-1',
              siteId: 'site-1',
              siteName: '软件测试',
            ),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const OpenCloudApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('作业'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('实验报告'));
    await tester.pumpAndSettle();
    await container
        .read(clientControllerProvider.notifier)
        .uploadAssignmentAttachment('/tmp/draft.pdf');
    await tester.pumpAndSettle();

    expect(find.text('返回作业列表'), findsOneWidget);
    expect(find.text('已上传附件 draft.pdf'), findsOneWidget);
  });

  testWidgets('desktop assignment feedback appears in the detail pane', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final container = ProviderContainer(
      overrides: [
        sessionStorageProvider.overrideWithValue(
          MemorySessionStorage('payload'),
        ),
        openCloudGatewayProvider.overrideWithValue(
          FakeOpenCloudGateway(
            session: _session(),
            undoneAssignmentsResponse: const FfiAssignmentListResponse(
              records: [
                FfiAssignmentSummary(
                  endTime: '2026-05-03 23:59:59',
                  id: 'work-1',
                  siteId: 'site-1',
                  siteName: '软件测试',
                  source: 'undone',
                  startTime: '',
                  status: FfiAssignmentStatus.pending,
                  title: '实验报告',
                ),
              ],
            ),
            assignmentDetailResponse: const FfiAssignmentDetailResponse(
              className: '',
              comment: '',
              content: '完成实验',
              endTime: '2026-05-03 23:59:59',
              id: 'work-1',
              isOvertimeCommit: false,
              siteId: 'site-1',
              siteName: '软件测试',
              startTime: '',
              status: FfiAssignmentStatus.pending,
              submittedAt: '',
              submittedAttachments: [],
              submittedContent: '',
              teacherResources: [],
              title: '实验报告',
            ),
            assignmentUploadResponse: const FfiAssignmentUploadResponse(
              assignmentId: 'work-1',
              fileName: 'draft.pdf',
              resourceId: 'draft-1',
              siteId: 'site-1',
              siteName: '软件测试',
            ),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const OpenCloudApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('作业'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('实验报告'));
    await tester.pumpAndSettle();
    await container
        .read(clientControllerProvider.notifier)
        .uploadAssignmentAttachment('/tmp/draft.pdf');
    await tester.pumpAndSettle();

    final feedback = find.text('已上传附件 draft.pdf');
    expect(feedback, findsOneWidget);
    expect(tester.getTopLeft(feedback).dx, greaterThan(500));
  });

  testWidgets('assignment detail falls back to list course name', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sessionStorageProvider.overrideWithValue(
            MemorySessionStorage('payload'),
          ),
          openCloudGatewayProvider.overrideWithValue(
            FakeOpenCloudGateway(
              session: _session(),
              undoneAssignmentsResponse: const FfiAssignmentListResponse(
                records: [
                  FfiAssignmentSummary(
                    endTime: '2026-06-28 23:59',
                    id: 'work-1',
                    siteId: 'site-1',
                    siteName: '大语言模型算法和实践',
                    source: 'undone',
                    startTime: '',
                    status: FfiAssignmentStatus.pending,
                    title: '大语言模型相关主题调研综述报告',
                  ),
                ],
              ),
              assignmentDetailResponse: const FfiAssignmentDetailResponse(
                className: '',
                comment: '',
                content: '完成调研综述报告',
                endTime: '2026-06-28 23:59',
                id: 'work-1',
                isOvertimeCommit: false,
                siteId: 'site-1',
                siteName: '',
                startTime: '',
                status: FfiAssignmentStatus.pending,
                submittedAt: '',
                submittedAttachments: [],
                submittedContent: '',
                teacherResources: [],
                title: '大语言模型相关主题调研综述报告',
              ),
            ),
          ),
        ],
        child: const OpenCloudApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('作业'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('大语言模型相关主题调研综述报告'));
    await tester.pumpAndSettle();

    expect(find.text('未知课程'), findsNothing);
    expect(find.text('大语言模型算法和实践'), findsWidgets);
  });

  testWidgets(
    'undone assignment detail falls back to loaded course by site id',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sessionStorageProvider.overrideWithValue(
              MemorySessionStorage('payload'),
            ),
            openCloudGatewayProvider.overrideWithValue(
              FakeOpenCloudGateway(
                session: _session(),
                courseResponse: const FfiCourseResponse(
                  records: [
                    FfiCourseSite(id: 'site-1', siteName: '大语言模型算法和实践'),
                  ],
                  goingSites: [],
                ),
                undoneAssignmentsResponse: const FfiAssignmentListResponse(
                  records: [
                    FfiAssignmentSummary(
                      endTime: '2026-06-28 23:59',
                      id: 'work-1',
                      siteId: 'site-1',
                      siteName: '',
                      source: 'undone',
                      startTime: '',
                      status: FfiAssignmentStatus.pending,
                      title: '大语言模型相关主题调研综述报告',
                    ),
                  ],
                ),
                assignmentDetailResponse: const FfiAssignmentDetailResponse(
                  className: '',
                  comment: '',
                  content: '完成调研综述报告',
                  endTime: '2026-06-28 23:59',
                  id: 'work-1',
                  isOvertimeCommit: false,
                  siteId: 'site-1',
                  siteName: '',
                  startTime: '',
                  status: FfiAssignmentStatus.pending,
                  submittedAt: '',
                  submittedAttachments: [],
                  submittedContent: '',
                  teacherResources: [],
                  title: '大语言模型相关主题调研综述报告',
                ),
              ),
            ),
          ],
          child: const OpenCloudApp(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('作业'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('大语言模型相关主题调研综述报告'));
      await tester.pumpAndSettle();

      expect(find.text('未知课程'), findsNothing);
      expect(find.text('大语言模型算法和实践'), findsOneWidget);
    },
  );

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

  testWidgets('resource course picker resets after course refresh fallback', (
    tester,
  ) async {
    final gateway = FakeOpenCloudGateway(
      session: _session(),
      courseResponses: const [
        FfiCourseResponse(
          records: [
            FfiCourseSite(id: 'site-old', siteName: '旧课程'),
            FfiCourseSite(id: 'site-other', siteName: '其他课程'),
          ],
          goingSites: [],
        ),
        FfiCourseResponse(
          records: [FfiCourseSite(id: 'site-new', siteName: '新课程')],
          goingSites: [],
        ),
      ],
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
    await tester.tap(find.text('其他课程').last);
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(OpenCloudApp)),
    );
    expect(
      container.read(clientControllerProvider).selectedResourceCourseId,
      'site-other',
    );

    await container.read(clientControllerProvider.notifier).refreshCourses();
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('新课程'), findsOneWidget);
    expect(
      container.read(clientControllerProvider).selectedResourceCourseId,
      'site-new',
    );
  });

  testWidgets('narrow resource course picker truncates long course names', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final gateway = FakeOpenCloudGateway(
      session: _session(),
      courseResponse: const FfiCourseResponse(
        records: [
          FfiCourseSite(id: 'site-1', siteName: '移动端非常非常长的课程名称用于覆盖下拉选择器宽度边界'),
        ],
        goingSites: [],
      ),
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

    expect(tester.takeException(), isNull);
  });

  testWidgets('narrow resource list shows batch download summary', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(640, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final gateway = FakeOpenCloudGateway(
      session: _session(),
      courseResponse: _twoCourseResponse(),
      resourcesResponse: const FfiCourseResourcesResponse(
        records: [
          FfiCourseResourceSummary(
            name: '课件.pdf',
            resourceId: 'resource-1',
            siteId: 'site-1',
            siteName: '软件测试',
            updatedAt: '2026-05-02 10:00:00',
          ),
        ],
      ),
      resourceDownloadResponse: const FfiCourseResourceDownloadResponse(
        records: [
          FfiCourseResourceDetail(
            name: '课件.pdf',
            resourceId: 'resource-1',
            siteId: 'site-1',
            siteName: '软件测试',
            updatedAt: '2026-05-02 10:00:00',
          ),
        ],
        writtenPaths: ['/tmp/课件.pdf'],
      ),
    );
    final container = ProviderContainer(
      overrides: [
        sessionStorageProvider.overrideWithValue(
          MemorySessionStorage('payload'),
        ),
        openCloudGatewayProvider.overrideWithValue(gateway),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const OpenCloudApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('资料'));
    await tester.pumpAndSettle();
    await container
        .read(clientControllerProvider.notifier)
        .downloadCourseResources('/tmp');
    await tester.pumpAndSettle();

    expect(find.text('已下载 1 个资料文件'), findsOneWidget);
    expect(find.text('已下载 1 个文件'), findsOneWidget);
    expect(find.text('/tmp/课件.pdf'), findsOneWidget);
    expect(find.text('返回资料列表'), findsNothing);
  });

  testWidgets('desktop resource list shows batch download summary', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final gateway = FakeOpenCloudGateway(
      session: _session(),
      courseResponse: _twoCourseResponse(),
      resourcesResponse: const FfiCourseResourcesResponse(
        records: [
          FfiCourseResourceSummary(
            name: '课件.pdf',
            resourceId: 'resource-1',
            siteId: 'site-1',
            siteName: '软件测试',
            updatedAt: '2026-05-02 10:00:00',
          ),
        ],
      ),
      resourceDownloadResponse: const FfiCourseResourceDownloadResponse(
        records: [
          FfiCourseResourceDetail(
            name: '课件.pdf',
            resourceId: 'resource-1',
            siteId: 'site-1',
            siteName: '软件测试',
            updatedAt: '2026-05-02 10:00:00',
          ),
        ],
        writtenPaths: ['/tmp/课件.pdf'],
      ),
    );
    final container = ProviderContainer(
      overrides: [
        sessionStorageProvider.overrideWithValue(
          MemorySessionStorage('payload'),
        ),
        openCloudGatewayProvider.overrideWithValue(gateway),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const OpenCloudApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('资料'));
    await tester.pumpAndSettle();
    await container
        .read(clientControllerProvider.notifier)
        .downloadCourseResources('/tmp');
    await tester.pumpAndSettle();

    expect(find.text('已下载 1 个资料文件'), findsOneWidget);
    expect(find.text('已下载 1 个文件'), findsOneWidget);
    expect(find.text('/tmp/课件.pdf'), findsOneWidget);
    expect(tester.getTopLeft(find.text('/tmp/课件.pdf')).dx, lessThan(500));
  });

  testWidgets('resource download progress does not rebuild the resource pane', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(640, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final firstStatus = Completer<FfiDownloadTaskStatus>();
    final secondStatus = Completer<FfiDownloadTaskStatus>();
    final gateway = FakeOpenCloudGateway(
      session: _session(),
      courseResponse: _twoCourseResponse(),
      resourcesResponse: const FfiCourseResourcesResponse(
        records: [
          FfiCourseResourceSummary(
            name: '课件.pdf',
            resourceId: 'resource-1',
            siteId: 'site-1',
            siteName: '软件测试',
            updatedAt: '2026-05-02 10:00:00',
          ),
        ],
      ),
      resourceDownloadResponse: const FfiCourseResourceDownloadResponse(
        records: [
          FfiCourseResourceDetail(
            name: '课件.pdf',
            resourceId: 'resource-1',
            siteId: 'site-1',
            siteName: '软件测试',
            updatedAt: '2026-05-02 10:00:00',
          ),
        ],
        writtenPaths: ['/tmp/课件.pdf'],
      ),
      downloadTaskStatusFutures: [firstStatus.future, secondStatus.future],
    );
    final container = ProviderContainer(
      overrides: [
        sessionStorageProvider.overrideWithValue(
          MemorySessionStorage('payload'),
        ),
        openCloudGatewayProvider.overrideWithValue(gateway),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const OpenCloudApp(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('资料'));
    await tester.pumpAndSettle();

    final task = container
        .read(clientControllerProvider.notifier)
        .downloadCourseResources('/tmp');
    await tester.pump();
    firstStatus.complete(
      FfiDownloadTaskStatus(
        taskId: 'task',
        state: FfiDownloadTaskState.running,
        current: 0,
        total: 1,
        bytesDownloaded: BigInt.from(1024),
        currentFileName: '课件.pdf',
        writtenPaths: const [],
        records: const [],
      ),
    );
    await task;
    await tester.pump();
    expect(find.textContaining('正在下载'), findsOneWidget);

    final previousDebugPrint = debugPrint;
    final previousRebuildDebug = debugPrintRebuildDirtyWidgets;
    final rebuildLogs = <String>[];
    debugPrint = (message, {wrapWidth}) {
      if (message != null) {
        rebuildLogs.add(message);
      }
    };
    debugPrintRebuildDirtyWidgets = true;
    try {
      secondStatus.complete(
        FfiDownloadTaskStatus(
          taskId: 'task',
          state: FfiDownloadTaskState.running,
          current: 0,
          total: 1,
          bytesDownloaded: BigInt.from(2048),
          currentFileName: '课件.pdf',
          writtenPaths: const [],
          records: const [],
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();
      expect(find.textContaining('2.0 KB'), findsOneWidget);
    } finally {
      debugPrint = previousDebugPrint;
      debugPrintRebuildDirtyWidgets = previousRebuildDebug;
    }
    await container
        .read(clientControllerProvider.notifier)
        .cancelActiveResourceDownload(context: OperationContext.resourceList);
    await tester.pump();

    expect(
      rebuildLogs.where((line) => line.contains('_ResourcesPane')),
      isEmpty,
    );
  });

  testWidgets('large download summaries defer path rendering until expanded', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(640, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final paths = List.generate(50, (index) => '/tmp/资料 ${index + 1}.pdf');
    final gateway = FakeOpenCloudGateway(
      session: _session(),
      courseResponse: _twoCourseResponse(),
      resourcesResponse: const FfiCourseResourcesResponse(
        records: [
          FfiCourseResourceSummary(
            name: '课件.pdf',
            resourceId: 'resource-1',
            siteId: 'site-1',
            siteName: '软件测试',
            updatedAt: '2026-05-02 10:00:00',
          ),
        ],
      ),
      resourceDownloadResponse: FfiCourseResourceDownloadResponse(
        records: [
          for (var index = 0; index < 50; index += 1)
            FfiCourseResourceDetail(
              name: '资料 ${index + 1}.pdf',
              resourceId: 'resource-${index + 1}',
              siteId: 'site-1',
              siteName: '软件测试',
              updatedAt: '2026-05-02 10:00:00',
            ),
        ],
        writtenPaths: paths,
      ),
    );
    final container = ProviderContainer(
      overrides: [
        sessionStorageProvider.overrideWithValue(
          MemorySessionStorage('payload'),
        ),
        openCloudGatewayProvider.overrideWithValue(gateway),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const OpenCloudApp(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('资料'));
    await tester.pumpAndSettle();
    await container
        .read(clientControllerProvider.notifier)
        .downloadCourseResources('/tmp');
    await tester.pumpAndSettle();

    expect(find.text('已下载 50 个文件'), findsOneWidget);
    expect(find.text('/tmp/资料 1.pdf'), findsNothing);
    expect(find.text('/tmp/资料 50.pdf'), findsNothing);
    expect(find.widgetWithText(TextButton, '显示文件路径'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, '显示文件路径'));
    await tester.pumpAndSettle();

    expect(find.text('/tmp/资料 1.pdf'), findsOneWidget);
  });

  testWidgets('resource list lazily scrolls to later files', (tester) async {
    tester.view.physicalSize = const Size(640, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final resources = List.generate(
      80,
      (index) => FfiCourseResourceSummary(
        ext: 'pdf',
        name: '资料 ${index + 1}.pdf',
        resourceId: 'resource-${index + 1}',
        siteId: 'site-1',
        siteName: '软件测试',
        updatedAt: '2026-05-02 10:00:00',
      ),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sessionStorageProvider.overrideWithValue(
            MemorySessionStorage('payload'),
          ),
          openCloudGatewayProvider.overrideWithValue(
            FakeOpenCloudGateway(
              session: _session(),
              courseResponse: _twoCourseResponse(),
              resourcesResponse: FfiCourseResourcesResponse(records: resources),
              resourceDetailResponse: const FfiCourseResourceDetailResponse(
                detail: FfiCourseResourceDetail(
                  description: '长列表资料详情',
                  ext: 'pdf',
                  name: '资料 80.pdf',
                  resourceId: 'resource-80',
                  siteId: 'site-1',
                  siteName: '软件测试',
                  updatedAt: '2026-05-02 10:00:00',
                ),
              ),
            ),
          ),
        ],
        child: const OpenCloudApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('资料'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('资料 80.pdf'),
      500,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('资料 80.pdf'));
    await tester.pumpAndSettle();

    expect(find.text('返回资料列表'), findsOneWidget);
    expect(find.text('资料 80.pdf'), findsOneWidget);
    expect(find.text('长列表资料详情'), findsOneWidget);
  });

  testWidgets('narrow resource detail shows metadata and returns to list', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(640, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sessionStorageProvider.overrideWithValue(
            MemorySessionStorage('payload'),
          ),
          openCloudGatewayProvider.overrideWithValue(
            FakeOpenCloudGateway(
              session: _session(),
              courseResponse: _twoCourseResponse(),
              resourcesResponse: FfiCourseResourcesResponse(
                records: [
                  FfiCourseResourceSummary(
                    ext: 'pdf',
                    name: '课件.pdf',
                    resourceId: 'resource-1',
                    siteId: 'site-1',
                    siteName: '软件测试',
                    sizeBytes: BigInt.from(1536),
                    updatedAt: '2026-05-02 10:00:00',
                  ),
                ],
              ),
              resourceDetailResponse: FfiCourseResourceDetailResponse(
                detail: FfiCourseResourceDetail(
                  description: '第一章课件',
                  downloadUrl: 'https://example.com/slides.pdf',
                  ext: 'pdf',
                  name: '课件.pdf',
                  resourceId: 'resource-1',
                  siteId: 'site-1',
                  siteName: '软件测试',
                  sizeBytes: BigInt.from(1536),
                  updatedAt: '2026-05-02 10:00:00',
                ),
              ),
            ),
          ),
        ],
        child: const OpenCloudApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('资料'));
    await tester.pumpAndSettle();

    expect(find.text('PDF · 1.5 KB · 2026-05-02 10:00:00'), findsOneWidget);

    await tester.tap(find.text('课件.pdf'));
    await tester.pumpAndSettle();

    expect(find.text('返回资料列表'), findsOneWidget);
    expect(find.text('PDF'), findsOneWidget);
    expect(find.text('1.5 KB'), findsOneWidget);
    expect(find.text('第一章课件'), findsOneWidget);
    expect(find.text('https://example.com/slides.pdf'), findsOneWidget);

    await tester.tap(find.text('返回资料列表'));
    await tester.pumpAndSettle();

    expect(find.text('课件.pdf'), findsOneWidget);
    expect(find.text('返回资料列表'), findsNothing);
  });

  testWidgets(
    'narrow resource detail keeps single download feedback in place',
    (tester) async {
      tester.view.physicalSize = const Size(640, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final download = Completer<FfiCourseResourceDownloadResponse>();
      final container = ProviderContainer(
        overrides: [
          sessionStorageProvider.overrideWithValue(
            MemorySessionStorage('payload'),
          ),
          openCloudGatewayProvider.overrideWithValue(
            FakeOpenCloudGateway(
              session: _session(),
              courseResponse: _twoCourseResponse(),
              resourcesResponse: const FfiCourseResourcesResponse(
                records: [
                  FfiCourseResourceSummary(
                    name: '课件.pdf',
                    resourceId: 'resource-1',
                    siteId: 'site-1',
                    siteName: '软件测试',
                    updatedAt: '',
                  ),
                ],
              ),
              resourceDetailResponse: const FfiCourseResourceDetailResponse(
                detail: FfiCourseResourceDetail(
                  name: '课件.pdf',
                  resourceId: 'resource-1',
                  siteId: 'site-1',
                  siteName: '软件测试',
                  updatedAt: '',
                ),
              ),
              resourceDownloadFuture: download.future,
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const OpenCloudApp(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('资料'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('课件.pdf'));
      await tester.pumpAndSettle();

      final task = container
          .read(clientControllerProvider.notifier)
          .downloadResource('/tmp/课件.pdf');
      await tester.pump();
      await tester.pump();

      expect(find.textContaining('正在下载'), findsOneWidget);
      expect(find.widgetWithText(TextButton, '取消'), findsOneWidget);
      expect(find.text('返回资料列表'), findsOneWidget);

      download.complete(
        const FfiCourseResourceDownloadResponse(
          records: [
            FfiCourseResourceDetail(
              name: '课件.pdf',
              resourceId: 'resource-1',
              siteId: 'site-1',
              siteName: '软件测试',
              updatedAt: '',
            ),
          ],
          writtenPaths: ['/tmp/课件.pdf'],
        ),
      );
      await task;
      await tester.pumpAndSettle();

      expect(find.text('已下载 1 个资料文件'), findsOneWidget);
      expect(find.text('已下载 1 个文件'), findsOneWidget);
      expect(find.text('/tmp/课件.pdf'), findsOneWidget);
      expect(find.text('返回资料列表'), findsOneWidget);
    },
  );

  testWidgets('desktop resource download feedback appears in the detail pane', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final container = ProviderContainer(
      overrides: [
        sessionStorageProvider.overrideWithValue(
          MemorySessionStorage('payload'),
        ),
        openCloudGatewayProvider.overrideWithValue(
          FakeOpenCloudGateway(
            session: _session(),
            courseResponse: _twoCourseResponse(),
            resourcesResponse: const FfiCourseResourcesResponse(
              records: [
                FfiCourseResourceSummary(
                  name: '课件.pdf',
                  resourceId: 'resource-1',
                  siteId: 'site-1',
                  siteName: '软件测试',
                  updatedAt: '',
                ),
              ],
            ),
            resourceDetailResponse: const FfiCourseResourceDetailResponse(
              detail: FfiCourseResourceDetail(
                name: '课件.pdf',
                resourceId: 'resource-1',
                siteId: 'site-1',
                siteName: '软件测试',
                updatedAt: '',
              ),
            ),
            resourceDownloadResponse: const FfiCourseResourceDownloadResponse(
              records: [
                FfiCourseResourceDetail(
                  name: '课件.pdf',
                  resourceId: 'resource-1',
                  siteId: 'site-1',
                  siteName: '软件测试',
                  updatedAt: '',
                ),
              ],
              writtenPaths: ['/tmp/课件.pdf'],
            ),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const OpenCloudApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('资料'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('课件.pdf'));
    await tester.pumpAndSettle();
    await container
        .read(clientControllerProvider.notifier)
        .downloadResource('/tmp/课件.pdf');
    await tester.pumpAndSettle();

    final feedback = find.text('已下载 1 个资料文件');
    expect(feedback, findsOneWidget);
    expect(tester.getTopLeft(feedback).dx, greaterThan(500));
    expect(find.text('/tmp/课件.pdf'), findsOneWidget);
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
