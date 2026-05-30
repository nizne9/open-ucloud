part of 'home_screen.dart';
class _AssignmentsPane extends ConsumerWidget {
  const _AssignmentsPane();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(
      clientControllerProvider.select(_selectAssignmentsPaneState),
    );
    final controller = ref.read(clientControllerProvider.notifier);
    return LayoutBuilder(
      builder: (context, constraints) {
        final useSplit = constraints.maxWidth >= 900;
        if (!useSplit) {
          final showDetail =
              state.selectedAssignmentId != null ||
              state.assignmentDetail != null ||
              state.assignmentDetailLoading;
          if (showDetail) {
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                _FeedbackBanners(
                  errorMessage: state.errorMessage,
                  operationMessage: state.operationMessage,
                  activeOperationContext: state.operationContext,
                  operationContext: OperationContext.assignmentDetail,
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed:
                        state.assignmentUploading || state.assignmentSubmitting
                        ? null
                        : () async {
                            if (!await _prepareForAssignmentContextChange(
                              context,
                              ref,
                            )) {
                              return;
                            }
                            controller.clearAssignmentSelection();
                          },
                    icon: const Icon(Icons.arrow_back),
                    label: const Text('返回作业列表'),
                  ),
                ),
                const SizedBox(height: 8),
                const _AssignmentDetailCard(),
              ],
            );
          }
          return _listView(context, ref, state);
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: constraints.maxWidth >= 1120 ? 440 : 380,
              child: _listView(context, ref, state),
            ),
            const VerticalDivider(width: 1),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 16, 24, 24),
                children: [
                  if (state.assignmentDetail == null &&
                      !state.assignmentDetailLoading)
                    const _DetailPlaceholder(
                      icon: Icons.assignment_outlined,
                      title: '选择一个作业',
                      subtitle: '作业要求、附件和提交入口会显示在这里。',
                    )
                  else ...[
                    _FeedbackBanners(
                      errorMessage: state.errorMessage,
                      operationMessage: state.operationMessage,
                      activeOperationContext: state.operationContext,
                      operationContext: OperationContext.assignmentDetail,
                    ),
                    if (state.errorMessage != null ||
                        state.operationMessage != null)
                      const SizedBox(height: 12),
                    const _AssignmentDetailCard(),
                  ],
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _listView(
    BuildContext context,
    WidgetRef ref,
    _AssignmentsPaneState state,
  ) {
    return CustomScrollView(slivers: _listSlivers(context, ref, state));
  }

  List<Widget> _listSlivers(
    BuildContext context,
    WidgetRef ref,
    _AssignmentsPaneState state,
  ) {
    final headerChildren = _listHeaderChildren(context, ref, state);
    return [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        sliver: SliverList(delegate: SliverChildListDelegate(headerChildren)),
      ),
      if (state.assignmentsLoading)
        const SliverPadding(
          padding: EdgeInsets.fromLTRB(16, 12, 16, 24),
          sliver: SliverToBoxAdapter(child: _LoadingPane(label: '正在加载作业')),
        )
      else if (state.assignments.isEmpty)
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 48, 16, 24),
          sliver: SliverToBoxAdapter(
            child: _EmptyState(
              icon: Icons.assignment_late_outlined,
              label: state.assignmentView == AssignmentView.undone
                  ? '当前没有待提交作业'
                  : '当前课程暂无作业',
              action: state.assignmentView == AssignmentView.course &&
                      state.courses.length > 1
                  ? OutlinedButton.icon(
                      onPressed: () {
                        unawaited(_changeAssignmentView(
                          context,
                          ref,
                          AssignmentView.undone,
                        ));
                      },
                      icon: const Icon(Icons.pending_actions_outlined),
                      label: const Text('查看待提交'),
                    )
                  : null,
            ),
          ),
        )
      else
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          sliver: SliverList.builder(
            itemCount: state.assignments.length,
            itemBuilder: (context, index) => _assignmentListItem(
              context,
              ref,
              state,
              state.assignments[index],
            ),
          ),
        ),
    ];
  }

  List<Widget> _listHeaderChildren(
    BuildContext context,
    WidgetRef ref,
    _AssignmentsPaneState state,
  ) {
    final selectedCourseId =
        state.selectedAssignmentCourseId ??
        (state.courses.isEmpty ? null : state.courses.first.id);
    return [
      _FeedbackBanners(
        errorMessage: state.errorMessage,
        operationMessage: state.operationMessage,
        activeOperationContext: state.operationContext,
        operationContext: OperationContext.assignmentList,
      ),
      Row(
        children: [
          Expanded(
            child: SegmentedButton<AssignmentView>(
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
                if (next == state.assignmentView) {
                  return;
                }
                unawaited(_changeAssignmentView(context, ref, next));
              },
            ),
          ),
          IconButton(
            tooltip: '刷新作业',
            onPressed: state.assignmentsLoading
                ? null
                : () {
                    unawaited(_refreshAssignments(context, ref));
                  },
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      if (state.assignmentView == AssignmentView.course) ...[
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          key: _courseDropdownKey(
            'assignment',
            state.courses,
            selectedCourseId,
          ),
          isExpanded: true,
          initialValue: selectedCourseId,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            labelText: '课程',
          ),
          items: [
            for (final course in state.courses)
              DropdownMenuItem(
                value: course.id,
                child: Text(
                  course.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: (value) {
            if (value != null && value != state.selectedAssignmentCourseId) {
              unawaited(_loadCourseAssignmentsGuarded(context, ref, value));
            }
          },
        ),
      ],
    ];
  }

  Future<void> _changeAssignmentView(
    BuildContext context,
    WidgetRef ref,
    AssignmentView next,
  ) async {
    if (!await _prepareForAssignmentContextChange(context, ref)) {
      return;
    }
    final controller = ref.read(clientControllerProvider.notifier);
    final state = ref.read(clientControllerProvider);
    if (next == AssignmentView.undone) {
      controller.loadUndoneAssignments();
    } else if (state.courses.isNotEmpty) {
      controller.loadCourseAssignments(state.courses.first.id);
    }
  }

  Future<void> _refreshAssignments(BuildContext context, WidgetRef ref) async {
    if (!await _prepareForAssignmentContextChange(context, ref)) {
      return;
    }
    final controller = ref.read(clientControllerProvider.notifier);
    final currentState = ref.read(clientControllerProvider);
    if (currentState.assignmentView == AssignmentView.undone) {
      controller.loadUndoneAssignments();
    } else {
      final siteId =
          currentState.selectedAssignmentCourseId ??
          (currentState.courses.isEmpty ? null : currentState.courses.first.id);
      if (siteId != null) {
        controller.loadCourseAssignments(siteId);
      }
    }
  }

  Future<void> _loadCourseAssignmentsGuarded(
    BuildContext context,
    WidgetRef ref,
    String siteId,
  ) async {
    if (!await _prepareForAssignmentContextChange(context, ref)) {
      return;
    }
    ref.read(clientControllerProvider.notifier).loadCourseAssignments(siteId);
  }

  Future<void> _selectAssignmentGuarded(
    BuildContext context,
    WidgetRef ref,
    FfiAssignmentSummary assignment,
  ) async {
    final state = ref.read(clientControllerProvider);
    if (state.selectedAssignmentId == assignment.id) {
      return;
    }
    if (!await _prepareForAssignmentContextChange(context, ref)) {
      return;
    }
    await ref
        .read(clientControllerProvider.notifier)
        .selectAssignment(assignment);
  }

  Widget _assignmentListItem(
    BuildContext context,
    WidgetRef ref,
    _AssignmentsPaneState state,
    FfiAssignmentSummary assignment,
  ) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        selected: state.selectedAssignmentId == assignment.id,
        leading: Icon(_assignmentIcon(assignment.status)),
        title: Text(assignment.title),
        subtitle: Text('${assignment.siteName}\n截止：${assignment.endTime}'),
        isThreeLine: true,
        trailing: Text(_assignmentStatusText(assignment.status)),
        onTap: () {
          unawaited(_selectAssignmentGuarded(context, ref, assignment));
        },
      ),
    );
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
  const _AssignmentDetailCard();

  @override
  ConsumerState<_AssignmentDetailCard> createState() =>
      _AssignmentDetailCardState();
}

class _AssignmentDetailCardState extends ConsumerState<_AssignmentDetailCard> {
  late final TextEditingController _draftController;
  String? _editingAssignmentId;
  String _syncedDraftText = '';
  bool _draftDirty = false;

  @override
  void initState() {
    super.initState();
    _draftController = TextEditingController();
  }

  @override
  void dispose() {
    _draftController.dispose();
    super.dispose();
  }

  void _syncDraftController(
    FfiAssignmentDetailResponse? detail,
    String draftText,
  ) {
    final nextAssignmentId = detail?.id;
    final nextText = draftText;
    final assignmentChanged = _editingAssignmentId != nextAssignmentId;
    final draftChanged = _syncedDraftText != nextText;
    if (!assignmentChanged && (!draftChanged || _draftDirty)) {
      return;
    }
    _editingAssignmentId = nextAssignmentId;
    _syncedDraftText = nextText;
    _draftDirty = false;
    final oldSelection = _draftController.selection;
    _draftController.text = nextText;
    final offset = oldSelection.baseOffset.clamp(0, nextText.length);
    _draftController.selection = TextSelection.collapsed(offset: offset);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(
      clientControllerProvider.select(_selectAssignmentDetailState),
    );
    _syncDraftController(
      state.assignmentDetail,
      ref.read(clientControllerProvider).assignmentDraft,
    );
    final detail = state.assignmentDetail;
    final controller = ref.read(clientControllerProvider.notifier);
    if (state.assignmentDetailLoading) {
      return const _LoadingPane(label: '正在加载作业详情');
    }
    if (detail == null) {
      return const SizedBox.shrink();
    }
    final expired = detail.status == FfiAssignmentStatus.expired;
    final readOnly = expired;
    final resubmitting = detail.status == FfiAssignmentStatus.submitted;
    final submitLabel = resubmitting ? '重新提交' : '提交';
    final courseName = _assignmentCourseName(
      courses: state.courses,
      assignments: state.assignments,
      detail: detail,
    );
    final submittedAttachments = detail.submittedAttachments;
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
                if (detail.className.trim().isNotEmpty)
                  _AssignmentMetaChip(
                    icon: Icons.groups_outlined,
                    label: detail.className.trim(),
                  ),
                if (detail.startTime.trim().isNotEmpty)
                  _AssignmentMetaChip(
                    icon: Icons.play_circle_outline,
                    label: '开始 ${detail.startTime.trim()}',
                  ),
                if (detail.submittedAt.trim().isNotEmpty)
                  _AssignmentMetaChip(
                    icon: Icons.task_alt,
                    label: '提交 ${detail.submittedAt.trim()}',
                  ),
                if (detail.score != null)
                  _AssignmentMetaChip(
                    icon: Icons.grade_outlined,
                    label: '成绩 ${detail.score}',
                  ),
                if (detail.isOvertimeCommit)
                  const _AssignmentMetaChip(
                    icon: Icons.more_time_outlined,
                    label: '允许超时提交',
                  ),
              ],
            ),
            if (detail.comment.trim().isNotEmpty) ...[
              const SizedBox(height: 16),
              _AssignmentSection(
                title: '教师批语',
                child: SelectableText(detail.comment.trim()),
              ),
            ],
            if (detail.content.isNotEmpty) ...[
              const SizedBox(height: 16),
              _AssignmentSection(
                title: '作业要求',
                child: AssignmentContentView(content: detail.content),
              ),
            ],
            if (detail.teacherResources.isNotEmpty) ...[
              const SizedBox(height: 16),
              _AssignmentSection(
                title: '教师附件',
                child: _AssignmentResourceList(
                  resources: detail.teacherResources,
                ),
              ),
            ],
            if (submittedAttachments.isNotEmpty) ...[
              const SizedBox(height: 16),
              _AssignmentSection(
                title: '已提交附件',
                child: _AssignmentResourceList(resources: submittedAttachments),
              ),
            ],
            const SizedBox(height: 12),
            TextField(
              minLines: 4,
              maxLines: 8,
              enabled:
                  !readOnly &&
                  !state.assignmentSubmitting &&
                  !state.assignmentUploading,
              controller: _draftController,
              onChanged: (value) {
                _draftDirty = true;
                controller.updateAssignmentDraft(value);
              },
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                labelText: readOnly ? '提交内容（只读）' : '提交内容',
              ),
            ),
            const SizedBox(height: 12),
            if (state.assignmentUploading) ...[
              const LinearProgressIndicator(),
              const SizedBox(height: 8),
              Text('正在上传附件', style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 12),
            ],
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final attachment in state.assignmentAttachments)
                  _DraftAttachmentChip(
                    attachment: attachment,
                    onDeleted: readOnly || state.assignmentSubmitting
                        ? null
                        : () => controller.removeAssignmentAttachment(
                            attachment.resourceId,
                          ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed:
                      readOnly ||
                          state.assignmentUploading ||
                          state.assignmentSubmitting
                      ? null
                      : () async {
                          final files = await openFiles();
                          if (!mounted) {
                            return;
                          }
                          for (final file in files) {
                            await controller.uploadAssignmentAttachment(
                              file.path,
                            );
                          }
                        },
                  icon: const Icon(Icons.attach_file),
                  label: Text(state.assignmentUploading ? '上传中' : '添加附件'),
                ),
                const Spacer(),
                FilledButton.icon(
                  onPressed:
                      readOnly ||
                          state.assignmentSubmitting ||
                          state.assignmentUploading
                      ? null
                      : () async {
                          final ok = await _confirm(
                            context,
                            title: submitLabel,
                            content: resubmitting
                                ? '将覆盖/更新「${detail.title}」当前已提交的内容。\n'
                                      '课程：$courseName\n'
                                      '附件：${state.assignmentAttachments.length} 个'
                                : '将提交「${detail.title}」\n'
                                      '课程：$courseName\n'
                                      '附件：${state.assignmentAttachments.length} 个',
                            confirmLabel: submitLabel,
                          );
                          if (!mounted) {
                            return;
                          }
                          if (ok) {
                            await controller.submitAssignmentDraft(
                              _draftController.text,
                            );
                          }
                        },
                  icon: const Icon(Icons.send_outlined),
                  label: Text(state.assignmentSubmitting ? '提交中' : submitLabel),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DraftAttachmentChip extends StatelessWidget {
  const _DraftAttachmentChip({
    required this.attachment,
    required this.onDeleted,
  });

  final AssignmentAttachmentState attachment;
  final VoidCallback? onDeleted;

  @override
  Widget build(BuildContext context) {
    final previewUrl = attachment.previewUrl?.trim();
    if (previewUrl == null || previewUrl.isEmpty) {
      return InputChip(
        avatar: const Icon(Icons.attach_file, size: 18),
        label: Text(attachment.name),
        onDeleted: onDeleted,
      );
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.only(left: 4, right: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            InputChip(
              avatar: const Icon(Icons.attach_file, size: 18),
              label: Text(attachment.name),
              onDeleted: onDeleted,
              side: BorderSide.none,
            ),
            _LinkActions(url: previewUrl),
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

class _AssignmentResourceList extends StatelessWidget {
  const _AssignmentResourceList({required this.resources});

  final List<FfiAssignmentResource> resources;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          for (final resource in resources)
            ListTile(
              dense: true,
              leading: const Icon(Icons.attach_file),
              title: Text(resource.name),
              subtitle: resource.previewUrl == null
                  ? null
                  : SelectableText(resource.previewUrl!),
              trailing:
                  resource.previewUrl == null || resource.previewUrl!.isEmpty
                  ? null
                  : _LinkActions(url: resource.previewUrl!),
            ),
        ],
      ),
    );
  }
}

class _LinkActions extends StatelessWidget {
  const _LinkActions({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: '打开链接',
          onPressed: () => _openExternalLink(context, url),
          icon: const Icon(Icons.open_in_new_outlined),
        ),
        IconButton(
          tooltip: '复制链接',
          onPressed: () => _copyText(context, url),
          icon: const Icon(Icons.copy_outlined),
        ),
      ],
    );
  }
}

class _LinkValue extends StatelessWidget {
  const _LinkValue({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Expanded(child: SelectableText(url)),
            _LinkActions(url: url),
          ],
        ),
      ),
    );
  }
}

String _assignmentCourseName({
  required List<CourseItem> courses,
  required List<FfiAssignmentSummary> assignments,
  required FfiAssignmentDetailResponse detail,
}) {
  final detailName = detail.siteName.trim();
  if (detailName.isNotEmpty) {
    return detailName;
  }
  final detailSiteId = detail.siteId.trim();
  if (detailSiteId.isNotEmpty) {
    for (final course in courses) {
      if (course.id == detailSiteId && course.name.trim().isNotEmpty) {
        return course.name;
      }
    }
  }
  for (final assignment in assignments) {
    if (assignment.id == detail.id && assignment.siteName.trim().isNotEmpty) {
      return assignment.siteName;
    }
    if (assignment.id == detail.id && assignment.siteId.trim().isNotEmpty) {
      for (final course in courses) {
        if (course.id == assignment.siteId && course.name.trim().isNotEmpty) {
          return course.name;
        }
      }
    }
  }
  return '未知课程';
}
