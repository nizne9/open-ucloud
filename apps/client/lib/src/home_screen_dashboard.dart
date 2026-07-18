part of 'home_screen.dart';

class _DashboardPane extends ConsumerWidget {
  const _DashboardPane();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(clientControllerProvider);
    if (state.phase == ClientPhase.authenticated &&
        state.pendingAssignmentsErrorMessage == null &&
        !state.undoneAssignmentsLoaded &&
        !state.assignmentsLoading &&
        state.selectedTab == ClientTab.dashboard) {
      Future.microtask(() {
        ref
            .read(clientControllerProvider.notifier)
            .loadUndoneAssignments(
              selectedTab: ClientTab.dashboard,
              clearGlobalError: false,
            );
      });
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 860;
        final dashboardError =
            state.errorMessage != null &&
                state.errorMessage != state.pendingAssignmentsErrorMessage
            ? state.errorMessage
            : null;
        final primary = [
          if (dashboardError != null)
            _StatusBanner(kind: _BannerKind.error, message: dashboardError),
          _DashboardStatsCard(state: state),
          _CourseContextCard(state: state),
          _PendingAssignmentsCard(state: state),
        ];
        final nextAction = _NextActionCard.maybe(state: state);
        final secondary = [?nextAction];
        if (wide && secondary.isNotEmpty) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                flex: 3,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 10, 24),
                  children: primary,
                ),
              ),
              Expanded(
                flex: 2,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(10, 16, 20, 24),
                  children: secondary,
                ),
              ),
            ],
          );
        }
        return RefreshIndicator(
          onRefresh: () => _refreshActiveTab(context, ref),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [...primary, ...secondary],
          ),
        );
      },
    );
  }
}

class _DashboardStatsCard extends ConsumerWidget {
  const _DashboardStatsCard({required this.state});

  final ClientState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = state.session;
    final displayName = session?.user.realName.trim();
    final accountName = displayName == null || displayName.isEmpty
        ? session?.user.userName.trim()
        : displayName;
    return _WorkbenchCard(
      title: '今天需要关注',
      subtitle: state.phase == ClientPhase.loadingCourses
          ? '正在同步课程'
          : state.coursesSyncedAt == null
          ? '课程尚未同步'
          : '上次同步 ${formatClientTimestamp(state.coursesSyncedAt!)}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (accountName != null && accountName.isNotEmpty) ...[
            Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  child: Text(accountName.substring(0, 1)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(accountName),
                      Text(
                        '已登录',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
          ],
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth < 520 ? 2 : 3;
              return GridView.count(
                crossAxisCount: columns,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                childAspectRatio: columns == 2 ? 1.2 : 1.75,
                children: [
                  _MetricTile(value: '${state.courses.length}', label: '本期课程'),
                  _MetricTile(
                    value: state.assignmentsLoading
                        ? '...'
                        : '${state.assignments.length}',
                    label: '待提交作业',
                  ),
                  _MetricTile(
                    value:
                        '${state.courses.where((course) => course.going).length}',
                    label: '签到进行中',
                  ),
                ],
              );
            },
          ),
          if (state.capabilities.attendanceQrPayloadParsing) ...[
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: () => _openAttendanceQrDialog(context, ref),
                icon: const Icon(Icons.qr_code_scanner_outlined),
                label: const Text('解析二维码'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: _outlinedBoxDecoration(colorScheme),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CourseContextCard extends ConsumerWidget {
  const _CourseContextCard({required this.state});

  final ClientState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(clientControllerProvider.notifier);
    return _WorkbenchCard(
      title: '课程上下文',
      subtitle: '选择课程后查看作业或资料。',
      child: state.courses.isEmpty
          ? _EmptyState(
              compact: true,
              icon: Icons.menu_book_outlined,
              label: '暂无课程',
              action: OutlinedButton.icon(
                onPressed: () {
                  unawaited(_refreshCoursesWithGuards(context, ref));
                },
                icon: const Icon(Icons.refresh),
                label: const Text('同步课程'),
              ),
            )
          : Column(
              children: [
                for (final course in state.courses)
                  _CourseContextRow(
                    course: course,
                    onAssignments: () =>
                        unawaited(controller.loadCourseAssignments(course.id)),
                    onResources: () =>
                        unawaited(controller.loadResourcesForCourse(course.id)),
                  ),
              ],
            ),
    );
  }
}

class _CourseContextRow extends StatelessWidget {
  const _CourseContextRow({
    required this.course,
    required this.onAssignments,
    required this.onResources,
  });

  final CourseItem course;
  final VoidCallback onAssignments;
  final VoidCallback onResources;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      clipBehavior: Clip.antiAlias,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final stackActions = constraints.maxWidth < 560;
          final summary = Row(
            children: [
              Icon(
                course.going
                    ? Icons.notifications_active_outlined
                    : Icons.menu_book_outlined,
                color: course.going ? colorScheme.primary : colorScheme.outline,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _TooltipText(
                      course.name,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      course.going ? '${course.id} · 活动进行中' : course.id,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
          final actions = Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: stackActions ? WrapAlignment.end : WrapAlignment.start,
            children: [
              OutlinedButton(
                onPressed: onAssignments,
                child: const Text('查看作业'),
              ),
              FilledButton.tonal(
                onPressed: onResources,
                child: const Text('查看资料'),
              ),
            ],
          );
          return Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
            child: stackActions
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [summary, const SizedBox(height: 10), actions],
                  )
                : Row(
                    children: [
                      Expanded(child: summary),
                      const SizedBox(width: 12),
                      actions,
                    ],
                  ),
          );
        },
      ),
    );
  }
}

class _PendingAssignmentsCard extends ConsumerWidget {
  const _PendingAssignmentsCard({required this.state});

  final ClientState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(clientControllerProvider.notifier);
    final loadError =
        !state.assignmentsLoaded &&
        state.pendingAssignmentsErrorMessage != null;
    return _WorkbenchCard(
      title: '待办队列',
      subtitle: '优先处理仍可提交的作业。',
      child: state.assignmentsLoading
          ? const _LoadingPane(label: '正在加载待提交作业')
          : loadError
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _StatusBanner(
                  kind: _BannerKind.error,
                  message: state.pendingAssignmentsErrorMessage!,
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: () => controller.loadUndoneAssignments(
                      selectedTab: ClientTab.dashboard,
                      refresh: true,
                    ),
                    icon: const Icon(Icons.refresh),
                    label: const Text('重试待办'),
                  ),
                ),
              ],
            )
          : state.assignments.isEmpty
          ? _EmptyState(
              compact: true,
              icon: Icons.assignment_late_outlined,
              label: '当前没有待提交作业',
              action: OutlinedButton.icon(
                onPressed: () {
                  unawaited(
                    _selectClientTab(ClientTab.assignments, ref, context),
                  );
                },
                icon: const Icon(Icons.assignment_outlined),
                label: const Text('查看作业'),
              ),
            )
          : Column(
              children: [
                for (final assignment in state.assignments)
                  Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: Icon(_assignmentIcon(assignment.status)),
                      title: _TooltipText(assignment.title),
                      subtitle: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text:
                                  '${assignment.siteName} · 截止 ${assignment.endTime}',
                            ),
                            if (assignment.status ==
                                FfiAssignmentStatus.pending)
                              ?_deadlineUrgencySpan(
                                context,
                                assignment.endTime,
                              ),
                          ],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: FilledButton.tonal(
                        onPressed: () async {
                          final selected = await _selectClientTab(
                            ClientTab.assignments,
                            ref,
                            context,
                          );
                          if (!selected || !context.mounted) {
                            return;
                          }
                          await controller.selectAssignment(assignment);
                        },
                        child: const Text('继续提交'),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}

class _NextActionCard extends ConsumerWidget {
  const _NextActionCard({required this.state});

  static Widget? maybe({required ClientState state}) {
    return state.assignments.isEmpty ? null : _NextActionCard(state: state);
  }

  final ClientState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(clientControllerProvider.notifier);
    final next = state.assignments.isEmpty ? null : state.assignments.first;
    return _WorkbenchCard(
      title: '下一步动作',
      subtitle: '从最近的待提交作业继续。',
      child: next == null
          ? const SizedBox.shrink()
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  next.title,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text('${next.siteName} · 截止 ${next.endTime}'),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _MetaChip(
                      icon: _assignmentIcon(next.status),
                      label: _assignmentStatusText(next.status),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () async {
                    final selected = await _selectClientTab(
                      ClientTab.assignments,
                      ref,
                      context,
                    );
                    if (!selected || !context.mounted) {
                      return;
                    }
                    await controller.selectAssignment(next);
                  },
                  icon: const Icon(Icons.arrow_forward),
                  label: const Text('进入提交'),
                ),
              ],
            ),
    );
  }
}

class _AccountPane extends ConsumerWidget {
  const _AccountPane();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(
      clientControllerProvider.select(_selectAccountPaneState),
    );
    final controller = ref.read(clientControllerProvider.notifier);
    final session = state.session;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      children: [
        _WorkbenchCard(
          title: '账户状态',
          subtitle: '当前登录账号。',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (session != null) ...[
                _AccountBadge(name: session.user.realName, subtitle: '已登录'),
                const SizedBox(height: 12),
                _LabelValueRow(
                  label: '角色',
                  value: _roleLabel(session.selectedRole),
                ),
                _LabelValueRow(label: '账号', value: session.user.account),
              ],
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: state.isBusy
                        ? null
                        : () {
                            unawaited(_refreshActiveTab(context, ref));
                          },
                    icon: const Icon(Icons.refresh),
                    label: const Text('刷新'),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: state.isBusy
                        ? null
                        : () => _logoutWithConfirmation(
                            context,
                            controller.logout,
                          ),
                    icon: const Icon(Icons.logout),
                    label: const Text('退出登录'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}
