import 'dart:convert';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_cloud_ffi/open_cloud_ffi.dart';

import 'assignment_content_view.dart';
import 'client_controller.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  bool _bootstrapped = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_bootstrapped) {
      return;
    }
    _bootstrapped = true;
    Future.microtask(
      () => ref.read(clientControllerProvider.notifier).bootstrap(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(clientControllerProvider);
    final controller = ref.read(clientControllerProvider.notifier);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Open UCloud'),
        actions: [
          if (state.phase == ClientPhase.authenticated ||
              state.phase == ClientPhase.loadingCourses) ...[
            IconButton(
              tooltip: '刷新课程',
              onPressed: state.isBusy ? null : controller.refreshCourses,
              icon: const Icon(Icons.refresh),
            ),
            IconButton(
              tooltip: '退出登录',
              onPressed: state.isBusy ? null : controller.logout,
              icon: const Icon(Icons.logout),
            ),
          ],
        ],
      ),
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          child: switch (state.phase) {
            ClientPhase.bootstrapping => const _LoadingPane(label: '正在恢复会话'),
            ClientPhase.startingLogin => const _LoadingPane(label: '正在初始化登录'),
            ClientPhase.finishingLogin => const _LoadingPane(label: '正在登录'),
            ClientPhase.loadingCourses => _AuthenticatedPane(state: state),
            ClientPhase.authenticated => _AuthenticatedPane(state: state),
            ClientPhase.awaitingCaptcha => _LoginPane(state: state),
            ClientPhase.unauthenticated => _LoginPane(state: state),
          },
        ),
      ),
    );
  }
}

class _AuthenticatedPane extends ConsumerWidget {
  const _AuthenticatedPane({required this.state});

  final ClientState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(clientControllerProvider.notifier);
    return Column(
      children: [
        NavigationBar(
          selectedIndex: state.selectedTab.index,
          onDestinationSelected: (index) {
            final tab = ClientTab.values[index];
            controller.selectTab(tab);
            if (tab == ClientTab.assignments && state.assignments.isEmpty) {
              controller.loadUndoneAssignments();
            }
            if (tab == ClientTab.resources &&
                state.resources.isEmpty &&
                state.courses.isNotEmpty) {
              controller.loadResourcesForCourse(state.courses.first.id);
            }
          },
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.menu_book_outlined),
              label: '课程',
            ),
            NavigationDestination(
              icon: Icon(Icons.assignment_outlined),
              label: '作业',
            ),
            NavigationDestination(
              icon: Icon(Icons.folder_outlined),
              label: '资料',
            ),
          ],
        ),
        Expanded(
          child: switch (state.selectedTab) {
            ClientTab.courses => _CoursePane(state: state),
            ClientTab.assignments => _AssignmentsPane(state: state),
            ClientTab.resources => _ResourcesPane(state: state),
          },
        ),
      ],
    );
  }
}

class _LoginPane extends ConsumerStatefulWidget {
  const _LoginPane({required this.state});

  final ClientState state;

  @override
  ConsumerState<_LoginPane> createState() => _LoginPaneState();
}

class _LoginPaneState extends ConsumerState<_LoginPane> {
  late final TextEditingController _usernameController;
  late final TextEditingController _passwordController;
  late final TextEditingController _captchaController;

  @override
  void initState() {
    super.initState();
    _usernameController = TextEditingController(
      text: widget.state.pendingUsername ?? '',
    );
    _passwordController = TextEditingController(
      text: widget.state.pendingPassword ?? '',
    );
    _captchaController = TextEditingController();
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _captchaController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final controller = ref.read(clientControllerProvider.notifier);
    final awaitingCaptcha = state.phase == ClientPhase.awaitingCaptcha;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.all(24),
          children: [
            Icon(
              Icons.school_outlined,
              size: 48,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              '登录 Open UCloud',
              style: Theme.of(context).textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _usernameController,
              enabled: !awaitingCaptcha,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: '用户名',
                prefixIcon: Icon(Icons.person_outline),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _passwordController,
              enabled: !awaitingCaptcha,
              obscureText: true,
              onSubmitted: (_) => _submitPrimary(controller, awaitingCaptcha),
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: '密码',
                prefixIcon: Icon(Icons.lock_outline),
              ),
            ),
            if (awaitingCaptcha) ...[
              const SizedBox(height: 16),
              _CaptchaImage(dataUri: state.captchaImage),
              const SizedBox(height: 12),
              TextField(
                controller: _captchaController,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) =>
                    controller.finishLogin(captcha: _captchaController.text),
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: '验证码',
                  prefixIcon: Icon(Icons.verified_outlined),
                ),
              ),
            ],
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => _submitPrimary(controller, awaitingCaptcha),
              icon: Icon(awaitingCaptcha ? Icons.login : Icons.arrow_forward),
              label: Text(awaitingCaptcha ? '完成登录' : '继续'),
            ),
            if (awaitingCaptcha) ...[
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: () => controller.startLogin(
                  username: _usernameController.text,
                  password: _passwordController.text,
                ),
                icon: const Icon(Icons.restart_alt),
                label: const Text('重新获取验证码'),
              ),
            ],
            if (state.errorMessage != null) ...[
              const SizedBox(height: 16),
              _ErrorBanner(message: state.errorMessage!),
            ],
          ],
        ),
      ),
    );
  }

  void _submitPrimary(ClientController controller, bool awaitingCaptcha) {
    if (awaitingCaptcha) {
      controller.finishLogin(captcha: _captchaController.text);
      return;
    }
    controller.startLogin(
      username: _usernameController.text,
      password: _passwordController.text,
    );
  }
}

class _CoursePane extends ConsumerWidget {
  const _CoursePane({required this.state});

  final ClientState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = state.session;
    final controller = ref.read(clientControllerProvider.notifier);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        if (session != null)
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 4),
            leading: const CircleAvatar(child: Icon(Icons.person_outline)),
            title: Text(session.user.realName),
            subtitle: Text(_roleLabel(session.selectedRole)),
          ),
        if (state.errorMessage != null) ...[
          const SizedBox(height: 8),
          _ErrorBanner(message: state.errorMessage!),
        ],
        if (state.phase == ClientPhase.loadingCourses) ...[
          const SizedBox(height: 24),
          const _LoadingPane(label: '正在加载课程'),
        ] else if (state.courses.isEmpty) ...[
          const SizedBox(height: 48),
          Icon(
            Icons.inbox_outlined,
            size: 48,
            color: Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(height: 12),
          Text(
            '暂无课程',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ] else ...[
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  '课程',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              if (state.capabilities.attendanceQrPayloadParsing)
                OutlinedButton.icon(
                  onPressed: () {
                    ref
                        .read(clientControllerProvider.notifier)
                        .clearAttendanceQrPayloadParseState();
                    showDialog<void>(
                      context: context,
                      builder: (_) => const _AttendanceQrPayloadDialog(),
                    );
                  },
                  icon: const Icon(Icons.qr_code_scanner_outlined),
                  label: const Text('解析二维码'),
                ),
            ],
          ),
          const SizedBox(height: 8),
          for (final course in state.courses)
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                onTap: () {
                  controller.selectTab(ClientTab.resources);
                  controller.loadResourcesForCourse(course.id);
                },
                leading: Icon(
                  course.going
                      ? Icons.radio_button_checked
                      : Icons.menu_book_outlined,
                  color: course.going
                      ? Theme.of(context).colorScheme.primary
                      : null,
                ),
                title: Text(course.name),
                subtitle: Text(course.id),
                trailing: course.going
                    ? const Tooltip(
                        message: '正在进行',
                        child: Icon(Icons.notifications_active_outlined),
                      )
                    : null,
              ),
            ),
        ],
      ],
    );
  }

  String _roleLabel(FfiRoleName role) {
    return switch (role) {
      FfiRoleName.student => '学生',
      FfiRoleName.teacher => '教师',
      FfiRoleName.assistant => '助教',
    };
  }
}

class _AttendanceQrPayloadDialog extends ConsumerStatefulWidget {
  const _AttendanceQrPayloadDialog();

  @override
  ConsumerState<_AttendanceQrPayloadDialog> createState() =>
      _AttendanceQrPayloadDialogState();
}

class _AttendanceQrPayloadDialogState
    extends ConsumerState<_AttendanceQrPayloadDialog> {
  late final TextEditingController _payloadController;

  @override
  void initState() {
    super.initState();
    _payloadController = TextEditingController();
  }

  @override
  void dispose() {
    _payloadController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(clientControllerProvider);
    final parsed = state.parsedAttendanceQrPayload;
    final matchedCourse = parsed == null
        ? null
        : state.courses
              .where((course) => course.id == parsed.siteId)
              .firstOrNull;
    return AlertDialog(
      title: const Text('解析签到二维码内容'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _payloadController,
                minLines: 4,
                maxLines: 8,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: '二维码文本',
                ),
              ),
              if (state.attendanceQrInputError != null) ...[
                const SizedBox(height: 12),
                _ErrorBanner(message: state.attendanceQrInputError!),
              ],
              if (parsed != null) ...[
                const SizedBox(height: 16),
                _QrPayloadField(
                  label: 'attendanceId',
                  value: parsed.attendanceId,
                ),
                _QrPayloadField(label: 'siteId', value: parsed.siteId),
                _QrPayloadField(label: 'createTime', value: parsed.createTime),
                _QrPayloadField(
                  label: 'classLessonId',
                  value: parsed.classLessonId,
                ),
                if (matchedCourse != null)
                  _QrPayloadField(label: '课程', value: matchedCourse.name),
                if (matchedCourse?.going ?? false)
                  const _QrPayloadField(label: '状态', value: '正在进行'),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('关闭'),
        ),
        FilledButton.icon(
          onPressed: () => ref
              .read(clientControllerProvider.notifier)
              .parseAttendanceQrPayloadText(_payloadController.text),
          icon: const Icon(Icons.qr_code_scanner_outlined),
          label: const Text('解析'),
        ),
      ],
    );
  }
}

class _QrPayloadField extends StatelessWidget {
  const _QrPayloadField({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 112,
            child: Text(label, style: Theme.of(context).textTheme.labelLarge),
          ),
          Expanded(child: SelectableText(value)),
        ],
      ),
    );
  }
}

class _AssignmentsPane extends ConsumerWidget {
  const _AssignmentsPane({required this.state});

  final ClientState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(clientControllerProvider.notifier);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        if (state.errorMessage != null)
          _ErrorBanner(message: state.errorMessage!),
        Row(
          children: [
            SegmentedButton<AssignmentView>(
              segments: const [
                ButtonSegment(
                  value: AssignmentView.undone,
                  icon: Icon(Icons.pending_actions_outlined),
                  label: Text('待提交'),
                ),
                ButtonSegment(
                  value: AssignmentView.course,
                  icon: Icon(Icons.class_outlined),
                  label: Text('按课程'),
                ),
              ],
              selected: {state.assignmentView},
              onSelectionChanged: (selection) {
                final next = selection.single;
                if (next == AssignmentView.undone) {
                  controller.loadUndoneAssignments();
                } else if (state.courses.isNotEmpty) {
                  controller.loadCourseAssignments(state.courses.first.id);
                }
              },
            ),
            const Spacer(),
            IconButton(
              tooltip: '刷新作业',
              onPressed: state.assignmentsLoading
                  ? null
                  : () {
                      if (state.assignmentView == AssignmentView.undone) {
                        controller.loadUndoneAssignments();
                      } else {
                        final siteId =
                            state.selectedAssignmentCourseId ??
                            (state.courses.isEmpty
                                ? null
                                : state.courses.first.id);
                        if (siteId != null) {
                          controller.loadCourseAssignments(siteId);
                        }
                      }
                    },
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        if (state.assignmentView == AssignmentView.course) ...[
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue:
                state.selectedAssignmentCourseId ??
                (state.courses.isEmpty ? null : state.courses.first.id),
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: '课程',
            ),
            items: [
              for (final course in state.courses)
                DropdownMenuItem(value: course.id, child: Text(course.name)),
            ],
            onChanged: (value) {
              if (value != null) {
                controller.loadCourseAssignments(value);
              }
            },
          ),
        ],
        if (state.assignmentsLoading)
          const _LoadingPane(label: '正在加载作业')
        else if (state.assignments.isEmpty) ...[
          const SizedBox(height: 48),
          _EmptyText(
            icon: Icons.assignment_late_outlined,
            label: state.assignmentView == AssignmentView.undone
                ? '当前没有待提交作业'
                : '当前课程暂无作业',
          ),
        ] else ...[
          const SizedBox(height: 12),
          for (final assignment in state.assignments)
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                selected: state.selectedAssignmentId == assignment.id,
                leading: Icon(_assignmentIcon(assignment.status)),
                title: Text(assignment.title),
                subtitle: Text(
                  '${assignment.siteName}\n截止：${assignment.endTime}',
                ),
                isThreeLine: true,
                trailing: Text(_assignmentStatusLabel(assignment.status)),
                onTap: () => controller.selectAssignment(assignment),
              ),
            ),
        ],
        const SizedBox(height: 12),
        _AssignmentDetailCard(state: state),
      ],
    );
  }

  IconData _assignmentIcon(FfiAssignmentStatus status) {
    return switch (status) {
      FfiAssignmentStatus.pending => Icons.edit_note_outlined,
      FfiAssignmentStatus.submitted => Icons.task_alt,
      FfiAssignmentStatus.expired => Icons.event_busy_outlined,
    };
  }

  String _assignmentStatusLabel(FfiAssignmentStatus status) {
    return _assignmentStatusText(status);
  }
}

String _assignmentStatusText(FfiAssignmentStatus status) {
  return switch (status) {
    FfiAssignmentStatus.pending => '待提交',
    FfiAssignmentStatus.submitted => '已提交',
    FfiAssignmentStatus.expired => '已截止',
  };
}

class _AssignmentDetailCard extends ConsumerStatefulWidget {
  const _AssignmentDetailCard({required this.state});

  final ClientState state;

  @override
  ConsumerState<_AssignmentDetailCard> createState() =>
      _AssignmentDetailCardState();
}

class _AssignmentDetailCardState extends ConsumerState<_AssignmentDetailCard> {
  late final TextEditingController _draftController;
  String? _editingAssignmentId;

  @override
  void initState() {
    super.initState();
    _draftController = TextEditingController();
    _syncDraftController();
  }

  @override
  void didUpdateWidget(covariant _AssignmentDetailCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncDraftController();
  }

  @override
  void dispose() {
    _draftController.dispose();
    super.dispose();
  }

  void _syncDraftController() {
    final detail = widget.state.assignmentDetail;
    final nextAssignmentId = detail?.id;
    final nextText = widget.state.assignmentDraft;
    if (_editingAssignmentId == nextAssignmentId &&
        _draftController.text == nextText) {
      return;
    }
    _editingAssignmentId = nextAssignmentId;
    final oldSelection = _draftController.selection;
    _draftController.text = nextText;
    final offset = oldSelection.baseOffset.clamp(0, nextText.length);
    _draftController.selection = TextSelection.collapsed(offset: offset);
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final detail = state.assignmentDetail;
    final controller = ref.read(clientControllerProvider.notifier);
    if (state.assignmentDetailLoading) {
      return const _LoadingPane(label: '正在加载作业详情');
    }
    if (detail == null) {
      return const SizedBox.shrink();
    }
    final expired = detail.status == FfiAssignmentStatus.expired;
    final courseName = _assignmentCourseName(state, detail);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(detail.title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _AssignmentMetaChip(
                  icon: Icons.class_outlined,
                  label: courseName,
                ),
                if (detail.endTime.isNotEmpty)
                  _AssignmentMetaChip(
                    icon: Icons.event_outlined,
                    label: '截止 ${detail.endTime}',
                  ),
                _AssignmentMetaChip(
                  icon: expired
                      ? Icons.event_busy_outlined
                      : Icons.edit_note_outlined,
                  label: _assignmentStatusText(detail.status),
                ),
              ],
            ),
            if (detail.content.isNotEmpty) ...[
              const SizedBox(height: 16),
              _AssignmentSection(
                title: '作业要求',
                child: AssignmentContentView(content: detail.content),
              ),
            ],
            const SizedBox(height: 12),
            TextField(
              minLines: 4,
              maxLines: 8,
              enabled: !expired && !state.assignmentSubmitting,
              controller: _draftController,
              onChanged: controller.updateAssignmentDraft,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: '提交内容',
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final attachment in state.assignmentAttachments)
                  Chip(
                    avatar: const Icon(Icons.attach_file, size: 18),
                    label: Text(attachment.name),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: expired
                      ? null
                      : () async {
                          final files = await openFiles();
                          for (final file in files) {
                            await controller.uploadAssignmentAttachment(
                              file.path,
                            );
                          }
                        },
                  icon: const Icon(Icons.attach_file),
                  label: const Text('添加附件'),
                ),
                const Spacer(),
                FilledButton.icon(
                  onPressed: expired || state.assignmentSubmitting
                      ? null
                      : () async {
                          final ok = await _confirm(
                            context,
                            title: '提交作业',
                            content: '确认提交当前作业内容和附件？',
                          );
                          if (ok) {
                            await controller.submitAssignmentDraft();
                          }
                        },
                  icon: const Icon(Icons.send_outlined),
                  label: Text(state.assignmentSubmitting ? '提交中' : '提交'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _AssignmentSection extends StatelessWidget {
  const _AssignmentSection({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        child,
      ],
    );
  }
}

class _AssignmentMetaChip extends StatelessWidget {
  const _AssignmentMetaChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Chip(
      visualDensity: VisualDensity.compact,
      avatar: Icon(icon, size: 18),
      label: Text(label),
    );
  }
}

String _assignmentCourseName(
  ClientState state,
  FfiAssignmentDetailResponse detail,
) {
  final detailName = detail.siteName.trim();
  if (detailName.isNotEmpty) {
    return detailName;
  }
  final detailSiteId = detail.siteId.trim();
  if (detailSiteId.isNotEmpty) {
    for (final course in state.courses) {
      if (course.id == detailSiteId && course.name.trim().isNotEmpty) {
        return course.name;
      }
    }
  }
  for (final assignment in state.assignments) {
    if (assignment.id == detail.id && assignment.siteName.trim().isNotEmpty) {
      return assignment.siteName;
    }
    if (assignment.id == detail.id && assignment.siteId.trim().isNotEmpty) {
      for (final course in state.courses) {
        if (course.id == assignment.siteId && course.name.trim().isNotEmpty) {
          return course.name;
        }
      }
    }
  }
  return '未知课程';
}

class _ResourcesPane extends ConsumerWidget {
  const _ResourcesPane({required this.state});

  final ClientState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(clientControllerProvider.notifier);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        if (state.errorMessage != null)
          _ErrorBanner(message: state.errorMessage!),
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue:
                    state.selectedResourceCourseId ??
                    (state.courses.isEmpty ? null : state.courses.first.id),
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: '课程',
                ),
                items: [
                  for (final course in state.courses)
                    DropdownMenuItem(
                      value: course.id,
                      child: Text(course.name),
                    ),
                ],
                onChanged: (value) {
                  if (value != null) {
                    controller.loadResourcesForCourse(value);
                  }
                },
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: '刷新资料',
              onPressed: state.resourcesLoading || state.courses.isEmpty
                  ? null
                  : () => controller.loadResourcesForCourse(
                      state.selectedResourceCourseId ?? state.courses.first.id,
                    ),
              icon: const Icon(Icons.refresh),
            ),
            IconButton(
              tooltip: '下载全部',
              onPressed: state.resourceDownloading || state.resources.isEmpty
                  ? null
                  : () async {
                      final ok = await _confirm(
                        context,
                        title: '下载全部资料',
                        content: '选择目录后将下载当前列表中的所有资料。',
                      );
                      if (!ok) {
                        return;
                      }
                      final directory = await getDirectoryPath();
                      if (directory != null) {
                        await controller.downloadCourseResources(directory);
                      }
                    },
              icon: const Icon(Icons.download_for_offline_outlined),
            ),
          ],
        ),
        if (state.resourceDownloading) ...[
          const SizedBox(height: 12),
          LinearProgressIndicator(
            value: state.resourceDownloadProgressTotal == 0
                ? null
                : state.resourceDownloadProgressCurrent /
                      state.resourceDownloadProgressTotal,
          ),
        ],
        if (state.resourcesLoading)
          const _LoadingPane(label: '正在加载资料')
        else if (state.resources.isEmpty) ...[
          const SizedBox(height: 48),
          const _EmptyText(icon: Icons.folder_off_outlined, label: '当前课程暂无资料'),
        ] else ...[
          const SizedBox(height: 12),
          for (final resource in state.resources)
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                selected: state.selectedResourceId == resource.resourceId,
                leading: const Icon(Icons.insert_drive_file_outlined),
                title: Text(resource.name),
                subtitle: Text(resource.updatedAt),
                onTap: () => controller.selectResource(resource),
              ),
            ),
        ],
        const SizedBox(height: 12),
        _ResourceDetailCard(state: state),
        if (state.downloadedPaths.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text('已写入：${state.downloadedPaths.join(', ')}'),
        ],
      ],
    );
  }
}

class _ResourceDetailCard extends ConsumerWidget {
  const _ResourceDetailCard({required this.state});

  final ClientState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = state.resourceDetail;
    final controller = ref.read(clientControllerProvider.notifier);
    if (state.resourceDetailLoading) {
      return const _LoadingPane(label: '正在加载资料详情');
    }
    if (detail == null) {
      return const SizedBox.shrink();
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(detail.name, style: Theme.of(context).textTheme.titleMedium),
            if (detail.description != null &&
                detail.description!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(detail.description!),
            ],
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: state.resourceDownloading
                    ? null
                    : () async {
                        final location = await getSaveLocation(
                          suggestedName: detail.name,
                        );
                        if (location != null) {
                          await controller.downloadResource(location.path);
                        }
                      },
                icon: const Icon(Icons.download_outlined),
                label: const Text('下载'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyText extends StatelessWidget {
  const _EmptyText({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, size: 48, color: Theme.of(context).colorScheme.outline),
        const SizedBox(height: 12),
        Text(
          label,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium,
        ),
      ],
    );
  }
}

Future<bool> _confirm(
  BuildContext context, {
  required String title,
  required String content,
}) async {
  return await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(content),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('确认'),
            ),
          ],
        ),
      ) ??
      false;
}

class _LoadingPane extends StatelessWidget {
  const _LoadingPane({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(label),
          ],
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.error_outline,
              color: Theme.of(context).colorScheme.onErrorContainer,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onErrorContainer,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CaptchaImage extends StatelessWidget {
  const _CaptchaImage({required this.dataUri});

  final String? dataUri;

  @override
  Widget build(BuildContext context) {
    final bytes = _decodeDataUri(dataUri);
    if (bytes == null) {
      return const SizedBox.shrink();
    }
    return Center(
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: Theme.of(context).colorScheme.outline),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Image.memory(bytes, height: 72, fit: BoxFit.contain),
        ),
      ),
    );
  }

  Uint8List? _decodeDataUri(String? dataUri) {
    if (dataUri == null) {
      return null;
    }
    final comma = dataUri.indexOf(',');
    if (comma == -1) {
      return null;
    }
    return base64Decode(dataUri.substring(comma + 1));
  }
}
