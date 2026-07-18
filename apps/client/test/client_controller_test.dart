import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_cloud_client/src/client_controller.dart';
import 'package:open_cloud_client/src/open_cloud_gateway.dart';
import 'package:open_cloud_ffi/open_cloud_ffi.dart';

import 'support/fakes.dart';

void main() {
  test('displayErrorText unwraps exception noise', () {
    expect(displayErrorText(Exception('network down')), 'network down');
    expect(displayErrorText('plain failure'), 'plain failure');
    expect(
      displayErrorText(
        const FfiAuthError(
          code: FfiAuthErrorCode.unknownAuthError,
          message: '账号或密码错误',
        ),
      ),
      '账号或密码错误',
    );
  });

  test('restores session and persists refreshed payload', () async {
    final storage = MemorySessionStorage('old-payload');
    final gateway = FakeOpenCloudGateway(
      capabilitiesResponse: const FfiClientCapabilities(
        selfAttendance: false,
        attendanceQrPayloadParsing: true,
      ),
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
    expect(state.capabilities.attendanceQrPayloadParsing, isTrue);
    expect(state.courses.single.going, isTrue);
    expect(storage.payload, 'new-payload');
  });

  test(
    'capability failures fall back to disabled flags and load courses',
    () async {
      final storage = MemorySessionStorage('payload');
      final gateway = FakeOpenCloudGateway(
        capabilitiesError: Exception('not available'),
        session: _session(),
        courseResponse: const FfiCourseResponse(
          records: [FfiCourseSite(id: 'site-1', siteName: '软件测试')],
          goingSites: [],
        ),
      );
      final container = _container(storage: storage, gateway: gateway);

      await container.read(clientControllerProvider.notifier).bootstrap();

      final state = container.read(clientControllerProvider);
      expect(state.phase, ClientPhase.authenticated);
      expect(state.capabilities.selfAttendance, isFalse);
      expect(state.capabilities.attendanceQrPayloadParsing, isFalse);
      expect(state.courses.single.name, '软件测试');
    },
  );

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

  test(
    'refreshCourses preserves current tab, assignment draft, attachments, and resource detail',
    () async {
      final storage = MemorySessionStorage('payload');
      final gateway = FakeOpenCloudGateway(
        session: _session(),
        courseResponse: const FfiCourseResponse(
          records: [FfiCourseSite(id: 'site-1', siteName: '软件测试')],
          goingSites: [],
          updatedSessionPayload: 'refreshed-payload',
        ),
        courseAssignmentsResponse: const FfiAssignmentListResponse(
          records: [
            FfiAssignmentSummary(
              endTime: '',
              id: 'work-1',
              siteId: 'site-1',
              siteName: '软件测试',
              source: 'course',
              startTime: '',
              status: FfiAssignmentStatus.pending,
              title: '实验报告',
            ),
          ],
        ),
        assignmentDetailResponse: const FfiAssignmentDetailResponse(
          className: '',
          comment: '',
          content: '',
          endTime: '',
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
      );
      final container = _container(storage: storage, gateway: gateway);
      final controller = container.read(clientControllerProvider.notifier);

      await controller.bootstrap();
      await controller.loadCourseAssignments('site-1');
      await controller.selectAssignment(
        container.read(clientControllerProvider).assignments.single,
      );
      controller.updateAssignmentDraft('未提交草稿');
      await controller.uploadAssignmentAttachment('/tmp/draft.pdf');
      await controller.loadResourcesForCourse('site-1');
      await controller.selectResource(
        container.read(clientControllerProvider).resources.single,
      );

      await controller.refreshCourses();

      final state = container.read(clientControllerProvider);
      expect(state.selectedTab, ClientTab.resources);
      expect(state.selectedAssignmentId, 'work-1');
      expect(state.assignmentDraft, '未提交草稿');
      expect(state.assignmentAttachments.single.previewUrl, contains('draft'));
      expect(state.selectedResourceId, 'resource-1');
      expect(state.resourceDetail?.name, '课件.pdf');
      expect(storage.payload, 'refreshed-payload');
    },
  );

  test(
    'refreshCourses falls back when selected assignment and resource course disappears',
    () async {
      final storage = MemorySessionStorage('payload');
      final gateway = FakeOpenCloudGateway(
        session: _session(),
        courseResponse: const FfiCourseResponse(
          records: [FfiCourseSite(id: 'site-new', siteName: '新课程')],
          goingSites: [],
        ),
        courseAssignmentsResponse: const FfiAssignmentListResponse(
          records: [
            FfiAssignmentSummary(
              endTime: '',
              id: 'work-old',
              siteId: 'site-old',
              siteName: '旧课程',
              source: 'course',
              startTime: '',
              status: FfiAssignmentStatus.pending,
              title: '旧作业',
            ),
          ],
        ),
        resourcesResponse: const FfiCourseResourcesResponse(
          records: [
            FfiCourseResourceSummary(
              name: '旧课件.pdf',
              resourceId: 'resource-old',
              siteId: 'site-old',
              siteName: '旧课程',
              updatedAt: '',
            ),
          ],
        ),
      );
      final container = _container(storage: storage, gateway: gateway);
      final controller = container.read(clientControllerProvider.notifier);

      await controller.bootstrap();
      await controller.loadCourseAssignments('site-old');
      await controller.loadResourcesForCourse('site-old');

      await controller.refreshCourses();

      final state = container.read(clientControllerProvider);
      expect(state.assignmentView, AssignmentView.course);
      expect(state.selectedAssignmentCourseId, 'site-new');
      expect(state.assignments, isEmpty);
      expect(state.selectedAssignmentId, isNull);
      expect(state.selectedResourceCourseId, 'site-new');
      expect(state.resources, isEmpty);
      expect(state.selectedResourceId, isNull);
    },
  );

  test('refreshCourses keeps a starting course download running', () async {
    final storage = MemorySessionStorage('payload');
    final download = Completer<FfiCourseResourceDownloadResponse>();
    final gateway = FakeOpenCloudGateway(
      session: _session(),
      courseResponse: const FfiCourseResponse(
        records: [FfiCourseSite(id: 'site-new', siteName: '新课程')],
        goingSites: [],
      ),
      resourcesResponse: const FfiCourseResourcesResponse(
        records: [
          FfiCourseResourceSummary(
            name: '旧课件.pdf',
            resourceId: 'resource-old',
            siteId: 'site-old',
            siteName: '旧课程',
            updatedAt: '',
          ),
        ],
      ),
      resourceDownloadCourseFuture: download.future,
    );
    final container = _container(storage: storage, gateway: gateway);
    final controller = container.read(clientControllerProvider.notifier);

    await controller.bootstrap();
    await controller.loadResourcesForCourse('site-old');
    await controller.downloadCourseResources('/tmp/downloads');
    await Future<void>.delayed(Duration.zero);

    expect(
      container
          .read(clientControllerProvider)
          .downloadTasks
          .any((task) => !task.isTerminal),
      isTrue,
    );

    await controller.refreshCourses();
    download.complete(
      const FfiCourseResourceDownloadResponse(
        records: [
          FfiCourseResourceDetail(
            name: '旧课件.pdf',
            resourceId: 'resource-old',
            siteId: 'site-old',
            siteName: '旧课程',
            updatedAt: '',
          ),
        ],
        writtenPaths: ['/tmp/downloads/旧课件.pdf'],
      ),
    );
    await _settleDownloads(container);

    final state = container.read(clientControllerProvider);
    expect(state.selectedResourceCourseId, 'site-new');
    expect(state.downloadTasks.any((task) => !task.isTerminal), isFalse);
    expect(state.downloadTasks.single.status?.writtenPaths, [
      '/tmp/downloads/旧课件.pdf',
    ]);
    expect(gateway.cancelledDownloadTaskIds, isEmpty);
  });

  test(
    'refreshCourses preserves undone assignments when a stale course selection disappears',
    () async {
      final storage = MemorySessionStorage('payload');
      final gateway = FakeOpenCloudGateway(
        session: _session(),
        courseResponse: const FfiCourseResponse(
          records: [FfiCourseSite(id: 'site-new', siteName: '新课程')],
          goingSites: [],
        ),
        courseAssignmentsResponse: const FfiAssignmentListResponse(
          records: [
            FfiAssignmentSummary(
              endTime: '',
              id: 'course-work',
              siteId: 'site-old',
              siteName: '旧课程',
              source: 'course',
              startTime: '',
              status: FfiAssignmentStatus.pending,
              title: '旧课程作业',
            ),
          ],
        ),
        undoneAssignmentsResponse: const FfiAssignmentListResponse(
          records: [
            FfiAssignmentSummary(
              endTime: '',
              id: 'undone-work',
              siteId: 'site-new',
              siteName: '新课程',
              source: 'undone',
              startTime: '',
              status: FfiAssignmentStatus.pending,
              title: '待办作业',
            ),
          ],
        ),
      );
      final container = _container(storage: storage, gateway: gateway);
      final controller = container.read(clientControllerProvider.notifier);

      await controller.bootstrap();
      await controller.loadCourseAssignments('site-old');
      await controller.loadUndoneAssignments();

      await controller.refreshCourses();

      final state = container.read(clientControllerProvider);
      expect(state.assignmentView, AssignmentView.undone);
      expect(state.selectedAssignmentCourseId, isNull);
      expect(state.assignments.single.id, 'undone-work');
      expect(state.assignmentsLoaded, isTrue);
    },
  );

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

  test('logout cancels pending assignment payload persistence', () async {
    final storage = MemorySessionStorage('payload');
    final pendingAssignments = Completer<FfiAssignmentListResponse>();
    final container = _container(
      storage: storage,
      gateway: FakeOpenCloudGateway(
        session: _session(),
        undoneAssignmentsFuture: pendingAssignments.future,
      ),
    );
    final controller = container.read(clientControllerProvider.notifier);

    final load = controller.loadUndoneAssignments(
      selectedTab: ClientTab.dashboard,
    );
    await Future<void>.delayed(Duration.zero);

    await controller.logout();

    expect(storage.payload, isNull);
    expect(
      container.read(clientControllerProvider).phase,
      ClientPhase.unauthenticated,
    );

    pendingAssignments.complete(
      const FfiAssignmentListResponse(
        records: [],
        updatedSessionPayload: 'late-payload',
      ),
    );
    await load;

    expect(storage.payload, isNull);
    expect(
      container.read(clientControllerProvider).phase,
      ClientPhase.unauthenticated,
    );
  });

  test('stale pending assignment session expiry keeps new login', () async {
    final storage = MemorySessionStorage('old-payload');
    final pendingAssignments = Completer<FfiAssignmentListResponse>();
    final container = _container(
      storage: storage,
      gateway: FakeOpenCloudGateway(
        session: _session(),
        undoneAssignmentsFuture: pendingAssignments.future,
      ),
    );
    final controller = container.read(clientControllerProvider.notifier);

    final load = controller.loadUndoneAssignments(
      selectedTab: ClientTab.dashboard,
    );
    await Future<void>.delayed(Duration.zero);

    await controller.logout();
    await controller.startLogin(username: 'alice', password: 'secret');

    expect(storage.payload, 'session-payload');
    expect(
      container.read(clientControllerProvider).phase,
      ClientPhase.authenticated,
    );

    pendingAssignments.completeError(
      const FfiAuthError(
        code: FfiAuthErrorCode.sessionExpired,
        message: 'old session expired',
      ),
    );
    await load;

    expect(storage.payload, 'session-payload');
    final state = container.read(clientControllerProvider);
    expect(state.phase, ClientPhase.authenticated);
    expect(state.errorMessage, isNull);
  });

  test('stale course assignment session expiry keeps new login', () async {
    final storage = MemorySessionStorage('old-payload');
    final courseAssignments = Completer<FfiAssignmentListResponse>();
    final container = _container(
      storage: storage,
      gateway: FakeOpenCloudGateway(
        session: _session(),
        courseAssignmentsFuture: courseAssignments.future,
      ),
    );
    final controller = container.read(clientControllerProvider.notifier);

    final load = controller.loadCourseAssignments('site-1');
    await Future<void>.delayed(Duration.zero);

    await controller.logout();
    await controller.startLogin(username: 'alice', password: 'secret');

    expect(storage.payload, 'session-payload');
    expect(
      container.read(clientControllerProvider).phase,
      ClientPhase.authenticated,
    );

    courseAssignments.completeError(
      const FfiAuthError(
        code: FfiAuthErrorCode.sessionExpired,
        message: 'old course session expired',
      ),
    );
    await load;

    expect(storage.payload, 'session-payload');
    final state = container.read(clientControllerProvider);
    expect(state.phase, ClientPhase.authenticated);
    expect(state.errorMessage, isNull);
  });

  test('parses attendance QR payload and preserves plus signs', () async {
    final storage = MemorySessionStorage('payload');
    final gateway = FakeOpenCloudGateway(
      session: _session(),
      courseResponse: const FfiCourseResponse(
        records: [FfiCourseSite(id: 'site-1', siteName: '软件测试')],
        goingSites: [],
      ),
      parseAttendanceQrPayloadResponse: const FfiAttendanceQrPayload(
        attendanceId: 'attendance-1',
        siteId: 'site-1',
        createTime: '2026-05-09 10:00:00+08:00',
        classLessonId: 'lesson-1',
      ),
    );
    final container = _container(storage: storage, gateway: gateway);
    await container.read(clientControllerProvider.notifier).bootstrap();

    await container
        .read(clientControllerProvider.notifier)
        .parseAttendanceQrPayloadText(
          'checkwork|id=attendance-1&siteId=site-1&createTime=2026-05-09 10:00:00+08:00&classLessonId=lesson-1',
        );

    final state = container.read(clientControllerProvider);
    expect(state.parsedAttendanceQrPayload?.attendanceId, 'attendance-1');
    expect(
      state.parsedAttendanceQrPayload?.createTime,
      '2026-05-09 10:00:00+08:00',
    );
    expect(state.attendanceQrInputError, isNull);
  });

  test('parse attendance QR failures keep courses visible', () async {
    final storage = MemorySessionStorage('payload');
    final gateway = FakeOpenCloudGateway(
      session: _session(),
      courseResponse: const FfiCourseResponse(
        records: [FfiCourseSite(id: 'site-1', siteName: '软件测试')],
        goingSites: [],
      ),
      parseAttendanceQrPayloadError: const FfiAuthError(
        code: FfiAuthErrorCode.unknownAuthError,
        message: 'invalid checkwork payload',
      ),
    );
    final container = _container(storage: storage, gateway: gateway);
    await container.read(clientControllerProvider.notifier).bootstrap();

    await container
        .read(clientControllerProvider.notifier)
        .parseAttendanceQrPayloadText('not a payload');

    final state = container.read(clientControllerProvider);
    expect(state.attendanceQrInputError, 'invalid checkwork payload');
    expect(state.parsedAttendanceQrPayload, isNull);
    expect(state.courses.single.name, '软件测试');
  });

  test('failed pending assignment loads remain retryable', () async {
    final storage = MemorySessionStorage('payload');
    final gateway = FakeOpenCloudGateway(
      session: _session(),
      undoneAssignmentsError: Exception('network down'),
    );
    final container = _container(storage: storage, gateway: gateway);

    await container
        .read(clientControllerProvider.notifier)
        .loadUndoneAssignments(selectedTab: ClientTab.dashboard);

    final state = container.read(clientControllerProvider);
    expect(state.selectedTab, ClientTab.dashboard);
    expect(state.assignmentView, AssignmentView.undone);
    expect(state.assignments, isEmpty);
    expect(state.assignmentsLoaded, isFalse);
    expect(state.assignmentsLoading, isFalse);
    expect(state.errorMessage, contains('未完成作业加载失败'));
    expect(state.pendingAssignmentsErrorMessage, contains('未完成作业加载失败'));
  });

  test(
    'loads assignment detail, uploads attachment, and submits draft',
    () async {
      final storage = MemorySessionStorage('payload');
      final gateway = FakeOpenCloudGateway(
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
          fileName: 'report.pdf',
          resourceId: 'res-1',
          siteId: 'site-1',
          siteName: '软件测试',
          updatedSessionPayload: 'upload-payload',
        ),
        assignmentSubmitResponse: const FfiAssignmentSubmitResponse(
          ok: true,
          updatedSessionPayload: 'submit-payload',
        ),
      );
      final container = _container(storage: storage, gateway: gateway);

      await container
          .read(clientControllerProvider.notifier)
          .loadUndoneAssignments();
      await container
          .read(clientControllerProvider.notifier)
          .selectAssignment(
            container.read(clientControllerProvider).assignments.single,
          );
      container
          .read(clientControllerProvider.notifier)
          .updateAssignmentDraft('答案');
      await container
          .read(clientControllerProvider.notifier)
          .uploadAssignmentAttachment('/tmp/report.pdf');
      await container
          .read(clientControllerProvider.notifier)
          .submitAssignmentDraft();

      final state = container.read(clientControllerProvider);
      expect(state.assignmentDetail?.status, FfiAssignmentStatus.submitted);
      expect(state.assignmentAttachments.single.resourceId, 'res-1');
      expect(state.assignmentUploading, isFalse);
      expect(state.operationMessage, '作业已提交');
      expect(gateway.submittedAttachmentIds, ['res-1']);
      expect(storage.payload, 'submit-payload');

      await container
          .read(clientControllerProvider.notifier)
          .loadUndoneAssignments();

      expect(container.read(clientControllerProvider).operationMessage, isNull);
    },
  );

  test('removes uploaded attachment from pending submission', () async {
    final storage = MemorySessionStorage('payload');
    final gateway = FakeOpenCloudGateway(
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
      assignmentUploadResponse: const FfiAssignmentUploadResponse(
        assignmentId: 'work-1',
        fileName: 'report.pdf',
        resourceId: 'res-1',
        siteId: 'site-1',
        siteName: '软件测试',
      ),
    );
    final container = _container(storage: storage, gateway: gateway);

    await container
        .read(clientControllerProvider.notifier)
        .loadUndoneAssignments();
    await container
        .read(clientControllerProvider.notifier)
        .selectAssignment(
          container.read(clientControllerProvider).assignments.single,
        );
    await container
        .read(clientControllerProvider.notifier)
        .uploadAssignmentAttachment('/tmp/report.pdf');
    container
        .read(clientControllerProvider.notifier)
        .removeAssignmentAttachment('res-1');

    final state = container.read(clientControllerProvider);
    expect(state.assignmentAttachments, isEmpty);
    expect(state.operationMessage, '已移除附件 report.pdf');
  });

  test('assignment selection cannot be cleared while uploading', () async {
    final storage = MemorySessionStorage('payload');
    final upload = Completer<FfiAssignmentUploadResponse>();
    final gateway = FakeOpenCloudGateway(
      session: _session(),
      assignmentUploadFuture: upload.future,
    );
    final container = _container(storage: storage, gateway: gateway);
    final controller = container.read(clientControllerProvider.notifier);

    await controller.selectAssignment(
      const FfiAssignmentSummary(
        endTime: '',
        id: 'work-uploading',
        siteId: 'site-1',
        siteName: '软件测试',
        source: 'undone',
        startTime: '',
        status: FfiAssignmentStatus.pending,
        title: '上传中作业',
      ),
    );

    final uploadTask = controller.uploadAssignmentAttachment('/tmp/report.pdf');
    await Future<void>.delayed(Duration.zero);

    controller.clearAssignmentSelection();

    var state = container.read(clientControllerProvider);
    expect(state.selectedAssignmentId, 'work-uploading');
    expect(state.assignmentDetail?.id, 'work-uploading');
    expect(state.assignmentUploading, isTrue);

    upload.complete(
      const FfiAssignmentUploadResponse(
        assignmentId: 'work-uploading',
        fileName: 'report.pdf',
        resourceId: 'res-uploading',
        siteId: 'site-1',
        siteName: '软件测试',
      ),
    );
    await uploadTask;

    state = container.read(clientControllerProvider);
    expect(state.selectedAssignmentId, 'work-uploading');
    expect(state.assignmentUploading, isFalse);
    expect(state.assignmentAttachments.single.resourceId, 'res-uploading');
  });

  test('assignment selection cannot be cleared while submitting', () async {
    final storage = MemorySessionStorage('payload');
    final submit = Completer<FfiAssignmentSubmitResponse>();
    final gateway = FakeOpenCloudGateway(
      session: _session(),
      assignmentSubmitFuture: submit.future,
    );
    final container = _container(storage: storage, gateway: gateway);
    final controller = container.read(clientControllerProvider.notifier);

    await controller.selectAssignment(
      const FfiAssignmentSummary(
        endTime: '',
        id: 'work-submitting',
        siteId: 'site-1',
        siteName: '软件测试',
        source: 'undone',
        startTime: '',
        status: FfiAssignmentStatus.pending,
        title: '提交中作业',
      ),
    );
    controller.updateAssignmentDraft('答案');

    final submitTask = controller.submitAssignmentDraft();
    await Future<void>.delayed(Duration.zero);

    controller.clearAssignmentSelection();

    var state = container.read(clientControllerProvider);
    expect(state.selectedAssignmentId, 'work-submitting');
    expect(state.assignmentDetail?.id, 'work-submitting');
    expect(state.assignmentSubmitting, isTrue);

    submit.complete(const FfiAssignmentSubmitResponse(ok: true));
    await submitTask;

    state = container.read(clientControllerProvider);
    expect(state.selectedAssignmentId, 'work-submitting');
    expect(state.assignmentSubmitting, isFalse);
    expect(state.assignmentDetail?.status, FfiAssignmentStatus.submitted);
    expect(state.assignmentDetail?.submittedContent, '答案');
  });

  test('downloads all resources and persists refreshed payload', () async {
    final storage = MemorySessionStorage('payload');
    final gateway = FakeOpenCloudGateway(
      session: _session(),
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
        updatedSessionPayload: 'download-payload',
      ),
    );
    final container = _container(storage: storage, gateway: gateway);
    await container.read(clientControllerProvider.notifier).bootstrap();

    await container
        .read(clientControllerProvider.notifier)
        .loadResourcesForCourse('site-1');
    await container
        .read(clientControllerProvider.notifier)
        .downloadCourseResources('/tmp/downloads');
    await _settleDownloads(container);

    final state = container.read(clientControllerProvider);
    expect(state.downloadTasks.single.status?.writtenPaths, ['/tmp/课件.pdf']);
    expect(state.downloadTasks.single.status?.current, 1);
    expect(state.operationMessage, '已下载 1 个资料文件');
    expect(storage.payload, 'download-payload');
    expect(gateway.disposedDownloadTaskIds, hasLength(1));

    container
        .read(clientControllerProvider.notifier)
        .selectTab(ClientTab.assignments);

    expect(container.read(clientControllerProvider).operationMessage, isNull);
  });

  test('resource list ignores stale course loads', () async {
    final storage = MemorySessionStorage('payload');
    final firstLoad = Completer<FfiCourseResourcesResponse>();
    final secondLoad = Completer<FfiCourseResourcesResponse>();
    final gateway = FakeOpenCloudGateway(
      session: _session(),
      resourcesFutures: [firstLoad.future, secondLoad.future],
    );
    final container = _container(storage: storage, gateway: gateway);
    addTearDown(container.dispose);
    final controller = container.read(clientControllerProvider.notifier);

    final firstTask = controller.loadResourcesForCourse('site-old');
    await Future<void>.delayed(Duration.zero);
    final secondTask = controller.loadResourcesForCourse('site-new');
    await Future<void>.delayed(Duration.zero);

    secondLoad.complete(
      const FfiCourseResourcesResponse(
        records: [
          FfiCourseResourceSummary(
            name: '新课件.pdf',
            resourceId: 'resource-new',
            siteId: 'site-new',
            siteName: '新课程',
            updatedAt: '',
          ),
        ],
        updatedSessionPayload: 'new-resource-payload',
      ),
    );
    await secondTask;

    firstLoad.complete(
      const FfiCourseResourcesResponse(
        records: [
          FfiCourseResourceSummary(
            name: '旧课件.pdf',
            resourceId: 'resource-old',
            siteId: 'site-old',
            siteName: '旧课程',
            updatedAt: '',
          ),
        ],
        updatedSessionPayload: 'old-resource-payload',
      ),
    );
    await firstTask;

    final state = container.read(clientControllerProvider);
    expect(state.selectedResourceCourseId, 'site-new');
    expect(state.resources.single.resourceId, 'resource-new');
    expect(storage.payload, 'new-resource-payload');
  });

  test('does not overlap slow download status polls', () async {
    final storage = MemorySessionStorage('payload');
    final firstStatus = Completer<FfiDownloadTaskStatus>();
    final gateway = FakeOpenCloudGateway(
      session: _session(),
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
      downloadTaskStatusFutures: [firstStatus.future],
    );
    final container = _container(storage: storage, gateway: gateway);
    final controller = container.read(clientControllerProvider.notifier);
    controller.selectTab(ClientTab.resources);

    await controller.selectResource(
      const FfiCourseResourceSummary(
        name: '课件.pdf',
        resourceId: 'resource-1',
        siteId: 'site-1',
        siteName: '软件测试',
        updatedAt: '',
      ),
    );
    final task = controller.downloadResource('/tmp/课件.pdf');
    await Future<void>.delayed(const Duration(milliseconds: 650));

    expect(gateway.downloadTaskStatusCalls, 1);

    firstStatus.complete(
      FfiDownloadTaskStatus(
        taskId: 'task',
        state: FfiDownloadTaskState.succeeded,
        current: 1,
        total: 1,
        bytesDownloaded: BigInt.zero,
        writtenPaths: ['/tmp/课件.pdf'],
        records: [
          FfiCourseResourceDetail(
            name: '课件.pdf',
            resourceId: 'resource-1',
            siteId: 'site-1',
            siteName: '软件测试',
            updatedAt: '',
          ),
        ],
      ),
    );
    await task;
    await _settleDownloads(container);

    final state = container.read(clientControllerProvider);
    expect(state.downloadTasks.any((task) => !task.isTerminal), isFalse);
    expect(state.downloadTasks.single.status?.writtenPaths, ['/tmp/课件.pdf']);
    expect(state.errorMessage, isNull);
  });

  test(
    'skips repeated download progress state with no visible change',
    () async {
      final storage = MemorySessionStorage('payload');
      final gateway = FakeOpenCloudGateway(
        session: _session(),
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
        downloadTaskStatuses: [
          FfiDownloadTaskStatus(
            taskId: 'task',
            state: FfiDownloadTaskState.running,
            current: 0,
            total: 1,
            bytesDownloaded: BigInt.zero,
            writtenPaths: const [],
            records: const [],
          ),
          FfiDownloadTaskStatus(
            taskId: 'task',
            state: FfiDownloadTaskState.running,
            current: 1,
            total: 1,
            bytesDownloaded: BigInt.from(2048),
            writtenPaths: const [],
            records: const [],
            currentFileName: '课件.pdf',
          ),
        ],
      );
      final container = _container(storage: storage, gateway: gateway);
      addTearDown(container.dispose);
      final controller = container.read(clientControllerProvider.notifier);
      controller.selectTab(ClientTab.resources);

      await controller.selectResource(
        const FfiCourseResourceSummary(
          name: '课件.pdf',
          resourceId: 'resource-1',
          siteId: 'site-1',
          siteName: '软件测试',
          updatedAt: '',
        ),
      );

      var notifications = 0;
      final subscription = container.listen<ClientState>(
        clientControllerProvider,
        (_, _) => notifications += 1,
      );
      addTearDown(subscription.close);

      await controller.downloadResource('/tmp/课件.pdf');
      await Future<void>.delayed(Duration.zero);

      expect(gateway.downloadTaskStatusCalls, 1);
      expect(notifications, 2);
      expect(
        container
            .read(clientControllerProvider)
            .downloadTasks
            .any((task) => !task.isTerminal),
        isTrue,
      );

      await Future<void>.delayed(const Duration(milliseconds: 350));

      var state = container.read(clientControllerProvider);
      expect(gateway.downloadTaskStatusCalls, 2);
      expect(notifications, 3);
      expect(state.downloadTasks.single.status?.current, 1);
      expect(
        state.downloadTasks.single.status?.bytesDownloaded,
        BigInt.from(2048),
      );

      await Future<void>.delayed(const Duration(milliseconds: 350));

      state = container.read(clientControllerProvider);
      expect(gateway.downloadTaskStatusCalls, 3);
      expect(state.downloadTasks.any((task) => !task.isTerminal), isFalse);
      expect(state.downloadTasks.single.status?.writtenPaths, ['/tmp/课件.pdf']);
      expect(state.operationMessage, '已下载 1 个资料文件');
    },
  );

  test('single resource download survives selection change', () async {
    final storage = MemorySessionStorage('payload');
    final download = Completer<FfiCourseResourceDownloadResponse>();
    final gateway = FakeOpenCloudGateway(
      session: _session(),
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
    );
    final container = _container(storage: storage, gateway: gateway);
    final controller = container.read(clientControllerProvider.notifier);
    controller.selectTab(ClientTab.resources);

    await controller.selectResource(
      const FfiCourseResourceSummary(
        name: '课件.pdf',
        resourceId: 'resource-1',
        siteId: 'site-1',
        siteName: '软件测试',
        updatedAt: '',
      ),
    );
    await controller.downloadResource('/tmp/课件.pdf');
    await Future<void>.delayed(Duration.zero);

    controller.clearResourceSelection();
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
        updatedSessionPayload: 'stale-download-payload',
      ),
    );
    await _settleDownloads(container);

    final state = container.read(clientControllerProvider);
    expect(state.downloadTasks.any((task) => !task.isTerminal), isFalse);
    expect(state.downloadTasks.single.status?.writtenPaths, ['/tmp/课件.pdf']);
    expect(state.operationMessage, '已下载 1 个资料文件');
    expect(storage.payload, 'stale-download-payload');
    expect(gateway.cancelledDownloadTaskIds, isEmpty);
  });

  test(
    'download status poll failure marks task failed and advances queue',
    () async {
      final storage = MemorySessionStorage('payload');
      final gateway = FakeOpenCloudGateway(
        session: _session(),
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
        downloadTaskStatusError: Exception('network down'),
      );
      final container = _container(storage: storage, gateway: gateway);
      final controller = container.read(clientControllerProvider.notifier);
      controller.selectTab(ClientTab.resources);

      await controller.selectResource(
        const FfiCourseResourceSummary(
          name: '课件.pdf',
          resourceId: 'resource-1',
          siteId: 'site-1',
          siteName: '软件测试',
          updatedAt: '',
        ),
      );
      await controller.downloadResource('/tmp/课件.pdf');
      await controller.loadResourcesForCourse('site-1');
      await controller.downloadCourseResources('/tmp/course');
      await _settleDownloads(container);

      final state = container.read(clientControllerProvider);
      expect(state.downloadTasks, hasLength(2));
      expect(state.downloadTasks.map((task) => task.status?.state), [
        FfiDownloadTaskState.failed,
        FfiDownloadTaskState.failed,
      ]);
      expect(state.errorMessage, contains('下载状态更新失败'));
      expect(gateway.cancelledDownloadTaskIds, hasLength(2));
      expect(gateway.disposedDownloadTaskIds, gateway.cancelledDownloadTaskIds);
    },
  );

  test('cancelling a starting queued item advances to the next one', () async {
    final storage = MemorySessionStorage('payload');
    final firstDownload = Completer<FfiCourseResourceDownloadResponse>();
    final secondDownload = Completer<FfiCourseResourceDownloadResponse>();
    final gateway = FakeOpenCloudGateway(
      session: _session(),
      resourceDetailFutures: [
        Future.value(
          const FfiCourseResourceDetailResponse(
            detail: FfiCourseResourceDetail(
              name: '旧课件.pdf',
              resourceId: 'resource-old',
              siteId: 'site-1',
              siteName: '软件测试',
              updatedAt: '',
            ),
          ),
        ),
        Future.value(
          const FfiCourseResourceDetailResponse(
            detail: FfiCourseResourceDetail(
              name: '新课件.pdf',
              resourceId: 'resource-new',
              siteId: 'site-1',
              siteName: '软件测试',
              updatedAt: '',
            ),
          ),
        ),
      ],
      resourceDownloadFutures: [firstDownload.future, secondDownload.future],
    );
    final container = _container(storage: storage, gateway: gateway);
    final controller = container.read(clientControllerProvider.notifier);
    controller.selectTab(ClientTab.resources);

    await controller.selectResource(
      const FfiCourseResourceSummary(
        name: '旧课件.pdf',
        resourceId: 'resource-old',
        siteId: 'site-1',
        siteName: '软件测试',
        updatedAt: '',
      ),
    );
    await controller.downloadResource('/tmp/old.pdf');
    await Future<void>.delayed(Duration.zero);
    await controller.selectResource(
      const FfiCourseResourceSummary(
        name: '新课件.pdf',
        resourceId: 'resource-new',
        siteId: 'site-1',
        siteName: '软件测试',
        updatedAt: '',
      ),
    );
    await controller.downloadResource('/tmp/new.pdf');
    await Future<void>.delayed(Duration.zero);

    final startingId = container
        .read(clientControllerProvider)
        .downloadTasks
        .first
        .id;
    await controller.cancelDownloadTask(startingId);

    firstDownload.complete(
      const FfiCourseResourceDownloadResponse(
        records: [
          FfiCourseResourceDetail(
            name: '旧课件.pdf',
            resourceId: 'resource-old',
            siteId: 'site-1',
            siteName: '软件测试',
            updatedAt: '',
          ),
        ],
        writtenPaths: ['/tmp/old.pdf'],
      ),
    );
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    secondDownload.complete(
      const FfiCourseResourceDownloadResponse(
        records: [
          FfiCourseResourceDetail(
            name: '新课件.pdf',
            resourceId: 'resource-new',
            siteId: 'site-1',
            siteName: '软件测试',
            updatedAt: '',
          ),
        ],
        writtenPaths: ['/tmp/new.pdf'],
      ),
    );
    await _settleDownloads(container);

    final state = container.read(clientControllerProvider);
    expect(state.downloadTasks.single.status?.writtenPaths, ['/tmp/new.pdf']);
    expect(gateway.cancelledDownloadTaskIds, hasLength(1));
    expect(gateway.disposedDownloadTaskIds, hasLength(2));
  });

  test(
    'logout during an in-flight download start leaks no task or timer',
    () async {
      final storage = MemorySessionStorage('payload');
      final download = Completer<FfiCourseResourceDownloadResponse>();
      final gateway = FakeOpenCloudGateway(
        session: _session(),
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
      );
      final container = _container(storage: storage, gateway: gateway);
      final controller = container.read(clientControllerProvider.notifier);
      controller.selectTab(ClientTab.resources);

      await controller.selectResource(
        const FfiCourseResourceSummary(
          name: '课件.pdf',
          resourceId: 'resource-1',
          siteId: 'site-1',
          siteName: '软件测试',
          updatedAt: '',
        ),
      );
      await controller.downloadResource('/tmp/课件.pdf');
      await Future<void>.delayed(Duration.zero);

      await controller.logout();
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
      await Future<void>.delayed(const Duration(milliseconds: 400));

      expect(gateway.cancelledDownloadTaskIds, hasLength(1));
      expect(gateway.disposedDownloadTaskIds, hasLength(1));
      expect(gateway.downloadTaskStatusCalls, 0);
    },
  );

  test('single resource downloads run in queue order', () async {
    final storage = MemorySessionStorage('payload');
    final firstDownload = Completer<FfiCourseResourceDownloadResponse>();
    final secondDownload = Completer<FfiCourseResourceDownloadResponse>();
    final gateway = FakeOpenCloudGateway(
      session: _session(),
      resourceDetailFutures: [
        Future.value(
          const FfiCourseResourceDetailResponse(
            detail: FfiCourseResourceDetail(
              name: '旧课件.pdf',
              resourceId: 'resource-old',
              siteId: 'site-1',
              siteName: '软件测试',
              updatedAt: '',
            ),
          ),
        ),
        Future.value(
          const FfiCourseResourceDetailResponse(
            detail: FfiCourseResourceDetail(
              name: '新课件.pdf',
              resourceId: 'resource-new',
              siteId: 'site-1',
              siteName: '软件测试',
              updatedAt: '',
            ),
          ),
        ),
      ],
      resourceDownloadFutures: [firstDownload.future, secondDownload.future],
    );
    final container = _container(storage: storage, gateway: gateway);
    final controller = container.read(clientControllerProvider.notifier);
    controller.selectTab(ClientTab.resources);

    await controller.selectResource(
      const FfiCourseResourceSummary(
        name: '旧课件.pdf',
        resourceId: 'resource-old',
        siteId: 'site-1',
        siteName: '软件测试',
        updatedAt: '',
      ),
    );
    await controller.downloadResource('/tmp/old.pdf');
    await Future<void>.delayed(Duration.zero);
    await controller.selectResource(
      const FfiCourseResourceSummary(
        name: '新课件.pdf',
        resourceId: 'resource-new',
        siteId: 'site-1',
        siteName: '软件测试',
        updatedAt: '',
      ),
    );
    await controller.downloadResource('/tmp/new.pdf');
    await Future<void>.delayed(Duration.zero);

    // The second download stays queued while the first has not started yet.
    expect(
      container.read(clientControllerProvider).downloadTasks,
      hasLength(2),
    );
    expect(
      container
          .read(clientControllerProvider)
          .downloadTasks
          .every((task) => task.isQueued),
      isTrue,
    );

    firstDownload.complete(
      const FfiCourseResourceDownloadResponse(
        records: [
          FfiCourseResourceDetail(
            name: '旧课件.pdf',
            resourceId: 'resource-old',
            siteId: 'site-1',
            siteName: '软件测试',
            updatedAt: '',
          ),
        ],
        writtenPaths: ['/tmp/old.pdf'],
      ),
    );
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    var state = container.read(clientControllerProvider);
    expect(state.selectedResourceId, 'resource-new');
    expect(state.downloadTasks.any((task) => !task.isTerminal), isTrue);
    expect(state.downloadTasks.first.status?.writtenPaths, ['/tmp/old.pdf']);
    expect(state.downloadTasks.last.isQueued, isTrue);

    secondDownload.complete(
      const FfiCourseResourceDownloadResponse(
        records: [
          FfiCourseResourceDetail(
            name: '新课件.pdf',
            resourceId: 'resource-new',
            siteId: 'site-1',
            siteName: '软件测试',
            updatedAt: '',
          ),
        ],
        writtenPaths: ['/tmp/new.pdf'],
      ),
    );
    await _settleDownloads(container);

    state = container.read(clientControllerProvider);
    expect(state.downloadTasks.any((task) => !task.isTerminal), isFalse);
    expect(state.downloadTasks.map((task) => task.status?.writtenPaths), [
      ['/tmp/old.pdf'],
      ['/tmp/new.pdf'],
    ]);
    expect(gateway.disposedDownloadTaskIds, hasLength(2));
  });

  test('duplicate downloads of the same resource are not enqueued', () async {
    final storage = MemorySessionStorage('payload');
    final gateway = FakeOpenCloudGateway(
      session: _session(),
      resourceDetailResponse: const FfiCourseResourceDetailResponse(
        detail: FfiCourseResourceDetail(
          name: '课件.pdf',
          resourceId: 'resource-1',
          siteId: 'site-1',
          siteName: '软件测试',
          updatedAt: '',
        ),
      ),
      resourceDownloadFuture:
          Completer<FfiCourseResourceDownloadResponse>().future,
    );
    final container = _container(storage: storage, gateway: gateway);
    final controller = container.read(clientControllerProvider.notifier);
    controller.selectTab(ClientTab.resources);

    await controller.selectResource(
      const FfiCourseResourceSummary(
        name: '课件.pdf',
        resourceId: 'resource-1',
        siteId: 'site-1',
        siteName: '软件测试',
        updatedAt: '',
      ),
    );
    await controller.downloadResource('/tmp/课件.pdf');
    await controller.downloadResource('/tmp/课件(副本).pdf');

    final state = container.read(clientControllerProvider);
    expect(state.downloadTasks, hasLength(1));
    expect(state.operationMessage, contains('已在下载队列中'));
  });

  test(
    'course download falls back to the resource count for a zero total',
    () async {
      final storage = MemorySessionStorage('payload');
      final gateway = FakeOpenCloudGateway(
        session: _session(),
        resourcesResponse: const FfiCourseResourcesResponse(
          records: [
            FfiCourseResourceSummary(
              name: '课件.pdf',
              resourceId: 'resource-1',
              siteId: 'site-1',
              siteName: '软件测试',
              updatedAt: '',
            ),
            FfiCourseResourceSummary(
              name: '讲义.pdf',
              resourceId: 'resource-2',
              siteId: 'site-1',
              siteName: '软件测试',
              updatedAt: '',
            ),
          ],
        ),
        downloadTaskStatusFutures: [Completer<FfiDownloadTaskStatus>().future],
      );
      final container = _container(storage: storage, gateway: gateway);
      final controller = container.read(clientControllerProvider.notifier);

      await controller.loadResourcesForCourse('site-1');
      await controller.downloadCourseResources('/tmp/downloads');
      await Future<void>.delayed(Duration.zero);

      expect(
        container
            .read(clientControllerProvider)
            .downloadTasks
            .single
            .status
            ?.total,
        2,
      );
    },
  );

  test('course download survives course switch', () async {
    final storage = MemorySessionStorage('payload');
    final download = Completer<FfiCourseResourceDownloadResponse>();
    final gateway = FakeOpenCloudGateway(
      session: _session(),
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
      resourceDownloadCourseFuture: download.future,
    );
    final container = _container(storage: storage, gateway: gateway);
    final controller = container.read(clientControllerProvider.notifier);

    await controller.loadResourcesForCourse('site-1');
    await controller.downloadCourseResources('/tmp/downloads');
    await Future<void>.delayed(Duration.zero);

    await controller.loadResourcesForCourse('site-2');
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
        writtenPaths: ['/tmp/downloads/课件.pdf'],
        updatedSessionPayload: 'stale-course-download-payload',
      ),
    );
    await _settleDownloads(container);

    final state = container.read(clientControllerProvider);
    expect(state.selectedResourceCourseId, 'site-2');
    expect(state.downloadTasks.any((task) => !task.isTerminal), isFalse);
    expect(state.downloadTasks.single.status?.writtenPaths, [
      '/tmp/downloads/课件.pdf',
    ]);
    expect(state.operationMessage, '已下载 1 个资料文件');
    expect(storage.payload, 'stale-course-download-payload');
    expect(gateway.cancelledDownloadTaskIds, isEmpty);
  });

  test('course downloads run in queue order', () async {
    final storage = MemorySessionStorage('payload');
    final firstDownload = Completer<FfiCourseResourceDownloadResponse>();
    final secondDownload = Completer<FfiCourseResourceDownloadResponse>();
    final gateway = FakeOpenCloudGateway(
      session: _session(),
      resourcesResponses: const [
        FfiCourseResourcesResponse(
          records: [
            FfiCourseResourceSummary(
              name: '旧课件.pdf',
              resourceId: 'resource-old',
              siteId: 'site-1',
              siteName: '软件测试',
              updatedAt: '',
            ),
          ],
        ),
        FfiCourseResourcesResponse(
          records: [
            FfiCourseResourceSummary(
              name: '新课件.pdf',
              resourceId: 'resource-new',
              siteId: 'site-2',
              siteName: '计算机网络',
              updatedAt: '',
            ),
          ],
        ),
      ],
      resourceDownloadCourseFutures: [
        firstDownload.future,
        secondDownload.future,
      ],
    );
    final container = _container(storage: storage, gateway: gateway);
    final controller = container.read(clientControllerProvider.notifier);

    await controller.loadResourcesForCourse('site-1');
    await controller.downloadCourseResources('/tmp/old');
    await Future<void>.delayed(Duration.zero);
    await controller.loadResourcesForCourse('site-2');
    await controller.downloadCourseResources('/tmp/new');
    await Future<void>.delayed(Duration.zero);

    firstDownload.complete(
      const FfiCourseResourceDownloadResponse(
        records: [
          FfiCourseResourceDetail(
            name: '旧课件.pdf',
            resourceId: 'resource-old',
            siteId: 'site-1',
            siteName: '软件测试',
            updatedAt: '',
          ),
        ],
        writtenPaths: ['/tmp/old/旧课件.pdf'],
      ),
    );
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    var state = container.read(clientControllerProvider);
    expect(state.selectedResourceCourseId, 'site-2');
    expect(state.downloadTasks.any((task) => !task.isTerminal), isTrue);
    expect(state.downloadTasks.first.status?.writtenPaths, [
      '/tmp/old/旧课件.pdf',
    ]);
    expect(state.downloadTasks.last.isQueued, isTrue);

    secondDownload.complete(
      const FfiCourseResourceDownloadResponse(
        records: [
          FfiCourseResourceDetail(
            name: '新课件.pdf',
            resourceId: 'resource-new',
            siteId: 'site-2',
            siteName: '计算机网络',
            updatedAt: '',
          ),
        ],
        writtenPaths: ['/tmp/new/新课件.pdf'],
      ),
    );
    await _settleDownloads(container);

    state = container.read(clientControllerProvider);
    expect(state.downloadTasks.any((task) => !task.isTerminal), isFalse);
    expect(state.downloadTasks.map((task) => task.status?.writtenPaths), [
      ['/tmp/old/旧课件.pdf'],
      ['/tmp/new/新课件.pdf'],
    ]);
    expect(gateway.disposedDownloadTaskIds, hasLength(2));
  });

  test(
    'clears success message when selecting another assignment detail',
    () async {
      final storage = MemorySessionStorage('payload');
      final gateway = FakeOpenCloudGateway(
        session: _session(),
        assignmentDetailResponse: const FfiAssignmentDetailResponse(
          className: '',
          comment: '',
          content: '',
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
        assignmentSubmitResponse: const FfiAssignmentSubmitResponse(ok: true),
      );
      final container = _container(storage: storage, gateway: gateway);

      await container
          .read(clientControllerProvider.notifier)
          .selectAssignment(
            const FfiAssignmentSummary(
              endTime: '2026-05-03 23:59:59',
              id: 'work-1',
              siteId: 'site-1',
              siteName: '软件测试',
              source: 'undone',
              startTime: '',
              status: FfiAssignmentStatus.pending,
              title: '实验报告',
            ),
          );
      container
          .read(clientControllerProvider.notifier)
          .updateAssignmentDraft('答案');
      await container
          .read(clientControllerProvider.notifier)
          .submitAssignmentDraft();

      expect(
        container.read(clientControllerProvider).operationMessage,
        '作业已提交',
      );

      await container
          .read(clientControllerProvider.notifier)
          .selectAssignment(
            const FfiAssignmentSummary(
              endTime: '2026-05-04 23:59:59',
              id: 'work-2',
              siteId: 'site-1',
              siteName: '软件测试',
              source: 'undone',
              startTime: '',
              status: FfiAssignmentStatus.pending,
              title: '下一份实验报告',
            ),
          );

      expect(container.read(clientControllerProvider).operationMessage, isNull);
    },
  );

  test('clears assignment loading state when session read fails', () async {
    final storage = MemorySessionStorage('payload', Exception('locked'));
    final container = _container(
      storage: storage,
      gateway: FakeOpenCloudGateway(session: _session()),
    );

    await container
        .read(clientControllerProvider.notifier)
        .loadUndoneAssignments();

    final state = container.read(clientControllerProvider);
    expect(state.assignmentsLoading, isFalse);
    expect(state.errorMessage, contains('无法读取安全存储'));
  });

  test('clears resource loading state when session read fails', () async {
    final storage = MemorySessionStorage('payload', Exception('locked'));
    final container = _container(
      storage: storage,
      gateway: FakeOpenCloudGateway(session: _session()),
    );

    await container
        .read(clientControllerProvider.notifier)
        .loadResourcesForCourse('site-1');

    final state = container.read(clientControllerProvider);
    expect(state.resourcesLoading, isFalse);
    expect(state.errorMessage, contains('无法读取安全存储'));
  });

  test('clears detail loading state when session read fails', () async {
    final storage = MemorySessionStorage('payload', Exception('locked'));
    final container = _container(
      storage: storage,
      gateway: FakeOpenCloudGateway(session: _session()),
    );

    await container
        .read(clientControllerProvider.notifier)
        .selectResource(
          const FfiCourseResourceSummary(
            name: '课件.pdf',
            resourceId: 'resource-1',
            siteId: 'site-1',
            siteName: '软件测试',
            updatedAt: '',
          ),
        );

    final state = container.read(clientControllerProvider);
    expect(state.resourceDetailLoading, isFalse);
    expect(state.errorMessage, contains('无法读取安全存储'));
  });

  test(
    'clears stale assignments when switching lists and session read fails',
    () async {
      final storage = MemorySessionStorage('payload');
      final gateway = FakeOpenCloudGateway(
        session: _session(),
        undoneAssignmentsResponse: const FfiAssignmentListResponse(
          records: [
            FfiAssignmentSummary(
              endTime: '',
              id: 'work-old',
              siteId: 'site-1',
              siteName: '软件测试',
              source: 'undone',
              startTime: '',
              status: FfiAssignmentStatus.pending,
              title: '旧作业',
            ),
          ],
        ),
      );
      final container = _container(storage: storage, gateway: gateway);
      await container
          .read(clientControllerProvider.notifier)
          .loadUndoneAssignments();
      storage.readError = Exception('locked');

      await container
          .read(clientControllerProvider.notifier)
          .loadCourseAssignments('site-2');

      final state = container.read(clientControllerProvider);
      expect(state.assignmentView, AssignmentView.course);
      expect(state.selectedAssignmentCourseId, 'site-2');
      expect(state.assignments, isEmpty);
      expect(state.assignmentsLoading, isFalse);
    },
  );

  test(
    'stale pending assignment responses keep the current course list',
    () async {
      final storage = MemorySessionStorage('payload');
      final pendingAssignments = Completer<FfiAssignmentListResponse>();
      final gateway = FakeOpenCloudGateway(
        session: _session(),
        undoneAssignmentsFuture: pendingAssignments.future,
        courseAssignmentsResponse: const FfiAssignmentListResponse(
          records: [
            FfiAssignmentSummary(
              endTime: '',
              id: 'course-work',
              siteId: 'site-2',
              siteName: '计算机网络',
              source: 'course',
              startTime: '',
              status: FfiAssignmentStatus.submitted,
              title: '课程作业',
            ),
          ],
          updatedSessionPayload: 'course-payload',
        ),
      );
      final container = _container(storage: storage, gateway: gateway);
      final controller = container.read(clientControllerProvider.notifier);

      final pendingLoad = controller.loadUndoneAssignments(
        selectedTab: ClientTab.dashboard,
      );
      await Future<void>.delayed(Duration.zero);

      await controller.loadCourseAssignments('site-2');

      var state = container.read(clientControllerProvider);
      expect(state.assignmentView, AssignmentView.course);
      expect(state.selectedAssignmentCourseId, 'site-2');
      expect(state.assignments.single.id, 'course-work');
      expect(storage.payload, 'course-payload');

      pendingAssignments.complete(
        const FfiAssignmentListResponse(
          records: [
            FfiAssignmentSummary(
              endTime: '',
              id: 'pending-work',
              siteId: 'site-1',
              siteName: '软件测试',
              source: 'undone',
              startTime: '',
              status: FfiAssignmentStatus.pending,
              title: '晚到待办',
            ),
          ],
          updatedSessionPayload: 'stale-payload',
        ),
      );
      await pendingLoad;

      state = container.read(clientControllerProvider);
      expect(state.assignmentView, AssignmentView.course);
      expect(state.selectedAssignmentCourseId, 'site-2');
      expect(state.assignments.single.id, 'course-work');
      expect(state.assignmentsLoading, isFalse);
      expect(storage.payload, 'course-payload');
    },
  );

  test(
    'clears stale assignment detail when selecting another assignment fails',
    () async {
      final storage = MemorySessionStorage('payload');
      final gateway = FakeOpenCloudGateway(
        session: _session(),
        assignmentDetailResponse: const FfiAssignmentDetailResponse(
          className: '',
          comment: '',
          content: '',
          endTime: '',
          id: 'work-old',
          isOvertimeCommit: false,
          siteId: 'site-1',
          siteName: '软件测试',
          startTime: '',
          status: FfiAssignmentStatus.pending,
          submittedAt: '',
          submittedAttachments: [],
          submittedContent: '旧答案',
          teacherResources: [],
          title: '旧作业',
        ),
      );
      final container = _container(storage: storage, gateway: gateway);
      await container
          .read(clientControllerProvider.notifier)
          .selectAssignment(
            const FfiAssignmentSummary(
              endTime: '',
              id: 'work-old',
              siteId: 'site-1',
              siteName: '软件测试',
              source: 'undone',
              startTime: '',
              status: FfiAssignmentStatus.pending,
              title: '旧作业',
            ),
          );
      storage.readError = Exception('locked');

      await container
          .read(clientControllerProvider.notifier)
          .selectAssignment(
            const FfiAssignmentSummary(
              endTime: '',
              id: 'work-new',
              siteId: 'site-2',
              siteName: '计算机网络',
              source: 'course',
              startTime: '',
              status: FfiAssignmentStatus.pending,
              title: '新作业',
            ),
          );

      final state = container.read(clientControllerProvider);
      expect(state.selectedAssignmentId, 'work-new');
      expect(state.assignmentDetail, isNull);
      expect(state.assignmentDraft, isEmpty);
      expect(state.assignmentAttachments, isEmpty);
      expect(state.assignmentDetailLoading, isFalse);
    },
  );

  test('clearing assignment selection ignores late detail responses', () async {
    final storage = MemorySessionStorage('payload');
    final completer = Completer<FfiAssignmentDetailResponse>();
    final gateway = FakeOpenCloudGateway(
      session: _session(),
      assignmentDetailFuture: completer.future,
    );
    final container = _container(storage: storage, gateway: gateway);
    final controller = container.read(clientControllerProvider.notifier);

    final load = controller.selectAssignment(
      const FfiAssignmentSummary(
        endTime: '',
        id: 'work-late',
        siteId: 'site-1',
        siteName: '软件测试',
        source: 'undone',
        startTime: '',
        status: FfiAssignmentStatus.pending,
        title: '晚到作业',
      ),
    );
    await Future<void>.delayed(Duration.zero);

    expect(
      container.read(clientControllerProvider).assignmentDetailLoading,
      isTrue,
    );

    controller.clearAssignmentSelection();

    expect(
      container.read(clientControllerProvider).selectedAssignmentId,
      isNull,
    );
    expect(
      container.read(clientControllerProvider).assignmentDetailLoading,
      isFalse,
    );

    completer.complete(
      const FfiAssignmentDetailResponse(
        className: '',
        comment: '',
        content: '',
        endTime: '',
        id: 'work-late',
        isOvertimeCommit: false,
        siteId: 'site-1',
        siteName: '软件测试',
        startTime: '',
        status: FfiAssignmentStatus.pending,
        submittedAt: '',
        submittedAttachments: [],
        submittedContent: 'late',
        teacherResources: [],
        title: '晚到作业',
        updatedSessionPayload: 'stale-assignment-payload',
      ),
    );
    await load;

    final state = container.read(clientControllerProvider);
    expect(state.selectedAssignmentId, isNull);
    expect(state.assignmentDetail, isNull);
    expect(state.assignmentDraft, isEmpty);
    expect(storage.payload, 'payload');
  });

  test('assignment refresh clears stale detail loading', () async {
    final storage = MemorySessionStorage('payload');
    final completer = Completer<FfiAssignmentDetailResponse>();
    final gateway = FakeOpenCloudGateway(
      session: _session(),
      assignmentDetailFuture: completer.future,
    );
    final container = _container(storage: storage, gateway: gateway);
    final controller = container.read(clientControllerProvider.notifier);

    final load = controller.selectAssignment(
      const FfiAssignmentSummary(
        endTime: '',
        id: 'work-refresh',
        siteId: 'site-1',
        siteName: '软件测试',
        source: 'undone',
        startTime: '',
        status: FfiAssignmentStatus.pending,
        title: '刷新作业',
      ),
    );
    await Future<void>.delayed(Duration.zero);

    await controller.loadUndoneAssignments();

    var state = container.read(clientControllerProvider);
    expect(state.selectedAssignmentId, isNull);
    expect(state.assignmentDetailLoading, isFalse);

    completer.complete(
      const FfiAssignmentDetailResponse(
        className: '',
        comment: '',
        content: '',
        endTime: '',
        id: 'work-refresh',
        isOvertimeCommit: false,
        siteId: 'site-1',
        siteName: '软件测试',
        startTime: '',
        status: FfiAssignmentStatus.pending,
        submittedAt: '',
        submittedAttachments: [],
        submittedContent: 'stale',
        teacherResources: [],
        title: '刷新作业',
      ),
    );
    await load;

    state = container.read(clientControllerProvider);
    expect(state.selectedAssignmentId, isNull);
    expect(state.assignmentDetailLoading, isFalse);
    expect(state.assignmentDetail, isNull);
    expect(state.assignmentDraft, isEmpty);
  });

  test('stale assignment session expiry clears persisted session', () async {
    final storage = MemorySessionStorage('payload');
    final completer = Completer<FfiAssignmentDetailResponse>();
    final gateway = FakeOpenCloudGateway(
      session: _session(),
      assignmentDetailFuture: completer.future,
    );
    final container = _container(storage: storage, gateway: gateway);
    final controller = container.read(clientControllerProvider.notifier);

    final load = controller.selectAssignment(
      const FfiAssignmentSummary(
        endTime: '',
        id: 'work-expired',
        siteId: 'site-1',
        siteName: '软件测试',
        source: 'undone',
        startTime: '',
        status: FfiAssignmentStatus.pending,
        title: '过期作业',
      ),
    );
    await Future<void>.delayed(Duration.zero);

    controller.clearAssignmentSelection();
    completer.completeError(
      const FfiAuthError(
        code: FfiAuthErrorCode.sessionExpired,
        message: 'expired',
      ),
    );
    await load;

    final state = container.read(clientControllerProvider);
    expect(state.phase, ClientPhase.unauthenticated);
    expect(state.errorMessage, 'expired');
    expect(storage.payload, isNull);
  });

  test(
    'assignment detail failures clear selection and preserve error',
    () async {
      final storage = MemorySessionStorage('payload');
      final gateway = FakeOpenCloudGateway(
        session: _session(),
        assignmentDetailFuture: Future<FfiAssignmentDetailResponse>.delayed(
          Duration.zero,
          () => throw Exception('detail failed'),
        ),
      );
      final container = _container(storage: storage, gateway: gateway);

      await container
          .read(clientControllerProvider.notifier)
          .selectAssignment(
            const FfiAssignmentSummary(
              endTime: '',
              id: 'work-fail',
              siteId: 'site-1',
              siteName: '软件测试',
              source: 'undone',
              startTime: '',
              status: FfiAssignmentStatus.pending,
              title: '失败作业',
            ),
          );

      final state = container.read(clientControllerProvider);
      expect(state.selectedAssignmentId, isNull);
      expect(state.assignmentDetailLoading, isFalse);
      expect(state.assignmentDetail, isNull);
      expect(state.errorMessage, contains('作业详情加载失败'));
      expect(state.errorMessage, contains('detail failed'));
    },
  );

  test('stale assignment detail failures keep newer selection', () async {
    final storage = MemorySessionStorage('payload');
    final first = Completer<FfiAssignmentDetailResponse>();
    final second = Completer<FfiAssignmentDetailResponse>();
    final gateway = FakeOpenCloudGateway(
      session: _session(),
      assignmentDetailFutures: [first.future, second.future],
    );
    final container = _container(storage: storage, gateway: gateway);
    final controller = container.read(clientControllerProvider.notifier);

    final firstLoad = controller.selectAssignment(
      const FfiAssignmentSummary(
        endTime: '',
        id: 'work-old',
        siteId: 'site-1',
        siteName: '软件测试',
        source: 'undone',
        startTime: '',
        status: FfiAssignmentStatus.pending,
        title: '旧作业',
      ),
    );
    await Future<void>.delayed(Duration.zero);
    final secondLoad = controller.selectAssignment(
      const FfiAssignmentSummary(
        endTime: '',
        id: 'work-new',
        siteId: 'site-1',
        siteName: '软件测试',
        source: 'undone',
        startTime: '',
        status: FfiAssignmentStatus.pending,
        title: '新作业',
      ),
    );
    await Future<void>.delayed(Duration.zero);

    first.completeError(Exception('old failed'));
    await firstLoad;

    var state = container.read(clientControllerProvider);
    expect(state.selectedAssignmentId, 'work-new');
    expect(state.assignmentDetailLoading, isTrue);
    expect(state.errorMessage, isNull);

    second.complete(
      const FfiAssignmentDetailResponse(
        className: '',
        comment: '',
        content: '',
        endTime: '',
        id: 'work-new',
        isOvertimeCommit: false,
        siteId: 'site-1',
        siteName: '软件测试',
        startTime: '',
        status: FfiAssignmentStatus.pending,
        submittedAt: '',
        submittedAttachments: [],
        submittedContent: 'new',
        teacherResources: [],
        title: '新作业',
      ),
    );
    await secondLoad;

    state = container.read(clientControllerProvider);
    expect(state.selectedAssignmentId, 'work-new');
    expect(state.assignmentDetail?.id, 'work-new');
    expect(state.assignmentDraft, 'new');
  });

  test(
    'clears stale resources when switching courses and session read fails',
    () async {
      final storage = MemorySessionStorage('payload');
      final gateway = FakeOpenCloudGateway(
        session: _session(),
        resourcesResponse: const FfiCourseResourcesResponse(
          records: [
            FfiCourseResourceSummary(
              name: '旧课件.pdf',
              resourceId: 'resource-old',
              siteId: 'site-1',
              siteName: '软件测试',
              updatedAt: '',
            ),
          ],
        ),
      );
      final container = _container(storage: storage, gateway: gateway);
      await container
          .read(clientControllerProvider.notifier)
          .loadResourcesForCourse('site-1');
      storage.readError = Exception('locked');

      await container
          .read(clientControllerProvider.notifier)
          .loadResourcesForCourse('site-2');

      final state = container.read(clientControllerProvider);
      expect(state.selectedResourceCourseId, 'site-2');
      expect(state.resources, isEmpty);
      expect(state.resourcesLoading, isFalse);
    },
  );

  test(
    'clears stale resource detail when selecting another resource fails',
    () async {
      final storage = MemorySessionStorage('payload');
      final gateway = FakeOpenCloudGateway(
        session: _session(),
        resourceDetailResponse: const FfiCourseResourceDetailResponse(
          detail: FfiCourseResourceDetail(
            name: '旧课件.pdf',
            resourceId: 'resource-old',
            siteId: 'site-1',
            siteName: '软件测试',
            updatedAt: '',
          ),
        ),
      );
      final container = _container(storage: storage, gateway: gateway);
      await container
          .read(clientControllerProvider.notifier)
          .selectResource(
            const FfiCourseResourceSummary(
              name: '旧课件.pdf',
              resourceId: 'resource-old',
              siteId: 'site-1',
              siteName: '软件测试',
              updatedAt: '',
            ),
          );
      storage.readError = Exception('locked');

      await container
          .read(clientControllerProvider.notifier)
          .selectResource(
            const FfiCourseResourceSummary(
              name: '新课件.pdf',
              resourceId: 'resource-new',
              siteId: 'site-2',
              siteName: '计算机网络',
              updatedAt: '',
            ),
          );

      final state = container.read(clientControllerProvider);
      expect(state.selectedResourceId, 'resource-new');
      expect(state.resourceDetail, isNull);
      expect(state.resourceDetailLoading, isFalse);
    },
  );

  test('clearing resource selection ignores late detail responses', () async {
    final storage = MemorySessionStorage('payload');
    final completer = Completer<FfiCourseResourceDetailResponse>();
    final gateway = FakeOpenCloudGateway(
      session: _session(),
      resourceDetailFuture: completer.future,
    );
    final container = _container(storage: storage, gateway: gateway);
    final controller = container.read(clientControllerProvider.notifier);

    final load = controller.selectResource(
      const FfiCourseResourceSummary(
        name: '晚到课件.pdf',
        resourceId: 'resource-late',
        siteId: 'site-1',
        siteName: '软件测试',
        updatedAt: '',
      ),
    );
    await Future<void>.delayed(Duration.zero);

    expect(
      container.read(clientControllerProvider).resourceDetailLoading,
      isTrue,
    );

    controller.clearResourceSelection();

    expect(container.read(clientControllerProvider).selectedResourceId, isNull);
    expect(
      container.read(clientControllerProvider).resourceDetailLoading,
      isFalse,
    );

    completer.complete(
      const FfiCourseResourceDetailResponse(
        detail: FfiCourseResourceDetail(
          name: '晚到课件.pdf',
          resourceId: 'resource-late',
          siteId: 'site-1',
          siteName: '软件测试',
          updatedAt: '',
        ),
        updatedSessionPayload: 'stale-resource-payload',
      ),
    );
    await load;

    final state = container.read(clientControllerProvider);
    expect(state.selectedResourceId, isNull);
    expect(state.resourceDetail, isNull);
    expect(storage.payload, 'payload');
  });

  test('resource refresh clears stale detail loading', () async {
    final storage = MemorySessionStorage('payload');
    final completer = Completer<FfiCourseResourceDetailResponse>();
    final gateway = FakeOpenCloudGateway(
      session: _session(),
      resourceDetailFuture: completer.future,
    );
    final container = _container(storage: storage, gateway: gateway);
    final controller = container.read(clientControllerProvider.notifier);

    final load = controller.selectResource(
      const FfiCourseResourceSummary(
        name: '刷新课件.pdf',
        resourceId: 'resource-refresh',
        siteId: 'site-1',
        siteName: '软件测试',
        updatedAt: '',
      ),
    );
    await Future<void>.delayed(Duration.zero);

    await controller.loadResourcesForCourse('site-2');

    var state = container.read(clientControllerProvider);
    expect(state.selectedResourceId, isNull);
    expect(state.resourceDetailLoading, isFalse);

    completer.complete(
      const FfiCourseResourceDetailResponse(
        detail: FfiCourseResourceDetail(
          name: '刷新课件.pdf',
          resourceId: 'resource-refresh',
          siteId: 'site-1',
          siteName: '软件测试',
          updatedAt: '',
        ),
      ),
    );
    await load;

    state = container.read(clientControllerProvider);
    expect(state.selectedResourceId, isNull);
    expect(state.resourceDetailLoading, isFalse);
    expect(state.resourceDetail, isNull);
  });

  test('stale resource session expiry clears persisted session', () async {
    final storage = MemorySessionStorage('payload');
    final completer = Completer<FfiCourseResourceDetailResponse>();
    final gateway = FakeOpenCloudGateway(
      session: _session(),
      resourceDetailFuture: completer.future,
    );
    final container = _container(storage: storage, gateway: gateway);
    final controller = container.read(clientControllerProvider.notifier);

    final load = controller.selectResource(
      const FfiCourseResourceSummary(
        name: '过期课件.pdf',
        resourceId: 'resource-expired',
        siteId: 'site-1',
        siteName: '软件测试',
        updatedAt: '',
      ),
    );
    await Future<void>.delayed(Duration.zero);

    controller.clearResourceSelection();
    completer.completeError(
      const FfiAuthError(
        code: FfiAuthErrorCode.sessionExpired,
        message: 'expired',
      ),
    );
    await load;

    final state = container.read(clientControllerProvider);
    expect(state.phase, ClientPhase.unauthenticated);
    expect(state.errorMessage, 'expired');
    expect(storage.payload, isNull);
  });

  test('resource detail failures clear selection and preserve error', () async {
    final storage = MemorySessionStorage('payload');
    final gateway = FakeOpenCloudGateway(
      session: _session(),
      resourceDetailFuture: Future<FfiCourseResourceDetailResponse>.delayed(
        Duration.zero,
        () => throw Exception('detail failed'),
      ),
    );
    final container = _container(storage: storage, gateway: gateway);

    await container
        .read(clientControllerProvider.notifier)
        .selectResource(
          const FfiCourseResourceSummary(
            name: '失败资料.pdf',
            resourceId: 'resource-fail',
            siteId: 'site-1',
            siteName: '软件测试',
            updatedAt: '',
          ),
        );

    final state = container.read(clientControllerProvider);
    expect(state.selectedResourceId, isNull);
    expect(state.resourceDetailLoading, isFalse);
    expect(state.resourceDetail, isNull);
    expect(state.errorMessage, contains('资料详情加载失败'));
    expect(state.errorMessage, contains('detail failed'));
  });

  test('stale resource detail failures keep newer selection', () async {
    final storage = MemorySessionStorage('payload');
    final first = Completer<FfiCourseResourceDetailResponse>();
    final second = Completer<FfiCourseResourceDetailResponse>();
    final gateway = FakeOpenCloudGateway(
      session: _session(),
      resourceDetailFutures: [first.future, second.future],
    );
    final container = _container(storage: storage, gateway: gateway);
    final controller = container.read(clientControllerProvider.notifier);

    final firstLoad = controller.selectResource(
      const FfiCourseResourceSummary(
        name: '旧课件.pdf',
        resourceId: 'resource-old',
        siteId: 'site-1',
        siteName: '软件测试',
        updatedAt: '',
      ),
    );
    await Future<void>.delayed(Duration.zero);
    final secondLoad = controller.selectResource(
      const FfiCourseResourceSummary(
        name: '新课件.pdf',
        resourceId: 'resource-new',
        siteId: 'site-1',
        siteName: '软件测试',
        updatedAt: '',
      ),
    );
    await Future<void>.delayed(Duration.zero);

    first.completeError(Exception('old failed'));
    await firstLoad;

    var state = container.read(clientControllerProvider);
    expect(state.selectedResourceId, 'resource-new');
    expect(state.resourceDetailLoading, isTrue);
    expect(state.errorMessage, isNull);

    second.complete(
      const FfiCourseResourceDetailResponse(
        detail: FfiCourseResourceDetail(
          name: '新课件.pdf',
          resourceId: 'resource-new',
          siteId: 'site-1',
          siteName: '软件测试',
          updatedAt: '',
        ),
      ),
    );
    await secondLoad;

    state = container.read(clientControllerProvider);
    expect(state.selectedResourceId, 'resource-new');
    expect(state.resourceDetail?.resourceId, 'resource-new');
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

/// Flushes the download queue pump and polling microtasks until no active
/// download tasks remain.
Future<void> _settleDownloads(ProviderContainer container) async {
  for (var attempt = 0; attempt < 20; attempt += 1) {
    await Future<void>.delayed(Duration.zero);
    final active = container
        .read(clientControllerProvider)
        .downloadTasks
        .any((task) => !task.isTerminal);
    if (!active) {
      return;
    }
  }
  fail('download tasks did not settle');
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
