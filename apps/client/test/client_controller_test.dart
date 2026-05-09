import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_cloud_client/src/client_controller.dart';
import 'package:open_cloud_client/src/open_cloud_gateway.dart';
import 'package:open_cloud_ffi/open_cloud_ffi.dart';

import 'support/fakes.dart';

void main() {
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

    final state = container.read(clientControllerProvider);
    expect(state.downloadedPaths, ['/tmp/课件.pdf']);
    expect(state.resourceDownloadProgressCurrent, 1);
    expect(state.resourceDownloadProgressTotal, 1);
    expect(state.operationMessage, '已下载 1 个资料文件');
    expect(storage.payload, 'download-payload');

    container
        .read(clientControllerProvider.notifier)
        .selectTab(ClientTab.assignments);

    expect(container.read(clientControllerProvider).operationMessage, isNull);
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
      ),
    );
    await load;

    final state = container.read(clientControllerProvider);
    expect(state.selectedAssignmentId, isNull);
    expect(state.assignmentDetail, isNull);
    expect(state.assignmentDraft, isEmpty);
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
      expect(state.downloadedPaths, isEmpty);
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
      ),
    );
    await load;

    final state = container.read(clientControllerProvider);
    expect(state.selectedResourceId, isNull);
    expect(state.resourceDetail, isNull);
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
