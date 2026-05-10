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
    expect(find.text('课程、待交作业、资料更新和会话健康集中到一个桌面视图。'), findsOneWidget);
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
    expect(find.text('实验报告'), findsWidgets);
    expect(find.text('Alice'), findsOneWidget);
    expect(find.text('会话已恢复 · 本机安全存储'), findsOneWidget);
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
    },
  );

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

  testWidgets('account page exposes session actions and QR parser capability', (
    tester,
  ) async {
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

    await tester.tap(find.byIcon(Icons.person_outline));
    await tester.pumpAndSettle();

    expect(find.text('账户状态'), findsOneWidget);
    expect(find.text('安全存储'), findsOneWidget);
    expect(find.text('退出登录会清理本机凭据，并回到登录表单。'), findsOneWidget);
    expect(find.text('解析二维码'), findsOneWidget);
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
    expect(find.byType(NavigationBar), findsOneWidget);
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
    expect(find.byTooltip('打开链接'), findsNWidgets(2));
    expect(find.byTooltip('复制链接'), findsNWidgets(2));
    expect(find.widgetWithText(TextField, '提交内容'), findsOneWidget);
    expect(find.widgetWithText(TextField, '提交内容（只读）'), findsNothing);
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
