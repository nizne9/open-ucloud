import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_cloud_client/src/app.dart';
import 'package:open_cloud_client/src/client_controller.dart';
import 'package:open_cloud_ffi/open_cloud_ffi.dart';

import 'support/fakes.dart';

void main() {
  testWidgets('uses rail navigation on desktop width', (tester) async {
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

    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
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
                    '<h3><strong>任务 1：基础 Transformer 编码器的文本分类</strong></h3>'
                    '<p>掌握&nbsp;<strong>Transformer</strong> 模型。</p>'
                    '<ol><li>实现从零构建基础 Transformer 编码器。</li>'
                    '<li>使用 <code>BERT</code> 进行微调。</li></ol>',
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
    expect(find.text('1. 实现从零构建基础 Transformer 编码器。'), findsOneWidget);
    expect(find.text('2. 使用 BERT 进行微调。'), findsOneWidget);
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
