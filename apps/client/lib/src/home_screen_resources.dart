part of 'home_screen.dart';

String _resourceSummaryText(FfiCourseResourceSummary resource) {
  final parts = [
    if (resource.ext != null && resource.ext!.trim().isNotEmpty)
      resource.ext!.trim().toUpperCase(),
    if (resource.sizeBytes != null) _formatBytes(resource.sizeBytes!),
    if (resource.updatedAt.trim().isNotEmpty) resource.updatedAt.trim(),
  ];
  return parts.isEmpty ? '暂无文件信息' : parts.join(' · ');
}

String _selectedResourceCourseName(_ResourcesPaneState state) {
  final selected = state.selectedResourceCourseId;
  if (selected != null) {
    for (final course in state.courses) {
      if (course.id == selected && course.name.trim().isNotEmpty) {
        return course.name.trim();
      }
    }
  }
  if (state.resources.isNotEmpty && state.resources.first.siteName.isNotEmpty) {
    return state.resources.first.siteName;
  }
  return '当前课程';
}

String _formatBytes(BigInt bytes) {
  final value = bytes.toDouble();
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var size = value;
  var unitIndex = 0;
  while (size >= 1024 && unitIndex < units.length - 1) {
    size /= 1024;
    unitIndex += 1;
  }
  final text = unitIndex == 0 || size >= 10
      ? size.toStringAsFixed(0)
      : size.toStringAsFixed(1);
  return '$text ${units[unitIndex]}';
}

class _ResourcesPane extends ConsumerWidget {
  const _ResourcesPane();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(
      clientControllerProvider.select(_selectResourcesPaneState),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final useSplit = constraints.maxWidth >= 900;
        final detailOpen =
            state.resourceDetail != null || state.resourceDetailLoading;
        if (!useSplit) {
          final showDetail = detailOpen || state.selectedResourceId != null;
          return PopScope(
            canPop: !showDetail,
            onPopInvokedWithResult: (didPop, result) {
              if (!didPop) {
                unawaited(_exitResourceDetail(context, ref));
              }
            },
            child: showDetail
                ? ListView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                    children: [
                      _FeedbackBanners(errorMessage: state.errorMessage),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: () =>
                              unawaited(_exitResourceDetail(context, ref)),
                          icon: const Icon(Icons.arrow_back),
                          label: const Text('返回资料列表'),
                        ),
                      ),
                      const SizedBox(height: 8),
                      _ResourceDetailCard(state: state),
                    ],
                  )
                : _listView(context, ref, state),
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: constraints.maxWidth >= 1120 ? 440 : 380,
              child: _listView(context, ref, state, showError: !detailOpen),
            ),
            const VerticalDivider(width: 1),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 16, 24, 24),
                children: [
                  if (state.resourceDetail == null &&
                      !state.resourceDetailLoading)
                    const _EmptyState(
                      icon: Icons.insert_drive_file_outlined,
                      label: '选择一个资料',
                      subtitle: '资料说明和单文件下载入口会显示在这里。',
                      bordered: true,
                    )
                  else ...[
                    _FeedbackBanners(errorMessage: state.errorMessage),
                    _ResourceDetailCard(state: state),
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
    _ResourcesPaneState state, {
    bool showError = true,
  }) {
    return RefreshIndicator(
      onRefresh: () => _refreshResources(context, ref),
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: _listSlivers(context, ref, state, showError: showError),
      ),
    );
  }

  List<Widget> _listSlivers(
    BuildContext context,
    WidgetRef ref,
    _ResourcesPaneState state, {
    bool showError = true,
  }) {
    final headerChildren = _listHeaderChildren(
      context,
      ref,
      state,
      showError: showError,
    );
    return [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        sliver: SliverList(delegate: SliverChildListDelegate(headerChildren)),
      ),
      if (state.resourcesLoading)
        const SliverPadding(
          padding: EdgeInsets.fromLTRB(16, 12, 16, 24),
          sliver: SliverToBoxAdapter(child: _LoadingPane(label: '正在加载资料')),
        )
      else if (state.resources.isEmpty)
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 48, 16, 24),
          sliver: SliverToBoxAdapter(
            child: _EmptyState(
              icon: Icons.folder_off_outlined,
              label: '当前课程暂无资料',
              action: state.courses.length > 1
                  ? OutlinedButton.icon(
                      onPressed: () {
                        final nextCourse = state.courses.firstWhere(
                          (c) => c.id != state.selectedResourceCourseId,
                          orElse: () => state.courses.first,
                        );
                        unawaited(
                          _loadResourcesForCourseGuarded(
                            context,
                            ref,
                            nextCourse.id,
                          ),
                        );
                      },
                      icon: const Icon(Icons.swap_horiz),
                      label: const Text('切换课程'),
                    )
                  : null,
            ),
          ),
        )
      else
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          sliver: SliverList.builder(
            itemCount: state.resources.length,
            itemBuilder: (context, index) =>
                _resourceListItem(context, ref, state, state.resources[index]),
          ),
        ),
    ];
  }

  List<Widget> _listHeaderChildren(
    BuildContext context,
    WidgetRef ref,
    _ResourcesPaneState state, {
    bool showError = true,
  }) {
    final controller = ref.read(clientControllerProvider.notifier);
    final selectedCourseId =
        state.selectedResourceCourseId ??
        (state.courses.isEmpty ? null : state.courses.first.id);
    final activeCourseTaskId = ref.watch(
      clientControllerProvider.select(
        (state) =>
            _activeCourseDownloadTaskId(state.downloadTasks, selectedCourseId),
      ),
    );
    return [
      _FeedbackBanners(errorMessage: showError ? state.errorMessage : null),
      Row(
        children: [
          Expanded(
            child: DropdownButtonFormField<String>(
              key: _courseDropdownKey(
                'resource',
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
                if (value != null && value != state.selectedResourceCourseId) {
                  unawaited(
                    _loadResourcesForCourseGuarded(context, ref, value),
                  );
                }
              },
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: '刷新资料',
            onPressed: state.resourcesLoading || state.courses.isEmpty
                ? null
                : () {
                    unawaited(_refreshResources(context, ref));
                  },
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: '下载全部',
            onPressed: state.resources.isEmpty || activeCourseTaskId != null
                ? null
                : () async {
                    final ok = await _confirm(
                      context,
                      title: '下载全部资料',
                      content:
                          '课程：${_selectedResourceCourseName(state)}\n'
                          '文件：${state.resources.length} 个\n'
                          '选择目录后将下载当前列表中的全部资料。',
                    );
                    if (!ok || !context.mounted) {
                      return;
                    }
                    final directory = await getDirectoryPath();
                    if (directory != null && context.mounted) {
                      await controller.downloadCourseResources(directory);
                    }
                  },
            icon: const Icon(Icons.download_for_offline_outlined),
          ),
        ],
      ),
      if (activeCourseTaskId != null) ...[
        const SizedBox(height: 12),
        _ResourceDownloadProgress(itemId: activeCourseTaskId),
      ],
    ];
  }

  Widget _resourceListItem(
    BuildContext context,
    WidgetRef ref,
    _ResourcesPaneState state,
    FfiCourseResourceSummary resource,
  ) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        selected: state.selectedResourceId == resource.resourceId,
        leading: const Icon(Icons.insert_drive_file_outlined),
        title: Text(resource.name),
        subtitle: Text(_resourceSummaryText(resource)),
        onTap: () {
          unawaited(_selectResourceGuarded(context, ref, resource));
        },
      ),
    );
  }

  Future<void> _exitResourceDetail(BuildContext context, WidgetRef ref) async {
    ref.read(clientControllerProvider.notifier).clearResourceSelection();
  }

  Future<void> _loadResourcesForCourseGuarded(
    BuildContext context,
    WidgetRef ref,
    String siteId,
  ) async {
    ref.read(clientControllerProvider.notifier).loadResourcesForCourse(siteId);
  }

  Future<void> _selectResourceGuarded(
    BuildContext context,
    WidgetRef ref,
    FfiCourseResourceSummary resource,
  ) async {
    final state = ref.read(clientControllerProvider);
    if (state.selectedResourceId == resource.resourceId) {
      return;
    }
    await ref.read(clientControllerProvider.notifier).selectResource(resource);
  }
}

Future<void> _refreshResources(BuildContext context, WidgetRef ref) async {
  final state = ref.read(clientControllerProvider);
  final siteId =
      state.selectedResourceCourseId ??
      (state.courses.isEmpty ? null : state.courses.first.id);
  if (siteId != null) {
    await ref
        .read(clientControllerProvider.notifier)
        .loadResourcesForCourse(siteId);
  }
}

class _ResourceDownloadProgress extends ConsumerWidget {
  const _ResourceDownloadProgress({required this.itemId});

  final String itemId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress = ref.watch(
      clientControllerProvider.select((state) {
        for (final item in state.downloadTasks) {
          if (item.id == itemId) {
            final status = item.status;
            return (
              queued: item.isQueued,
              current: status?.current ?? 0,
              total: status?.total ?? 0,
              bytes: status?.bytesDownloaded ?? BigInt.zero,
              fileName: status?.currentFileName,
            );
          }
        }
        return (
          queued: false,
          current: 0,
          total: 0,
          bytes: BigInt.zero,
          fileName: null,
        );
      }),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                progress.queued
                    ? '排队等待下载'
                    : _downloadTaskProgressText(
                        current: progress.current,
                        total: progress.total,
                        bytes: progress.bytes,
                        fileName: progress.fileName,
                      ),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            TextButton.icon(
              onPressed: () => unawaited(
                ref
                    .read(clientControllerProvider.notifier)
                    .cancelDownloadTask(itemId),
              ),
              icon: const Icon(Icons.close),
              label: const Text('取消'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (!progress.queued)
          LinearProgressIndicator(
            value: progress.total == 0
                ? null
                : progress.current / progress.total,
          ),
      ],
    );
  }
}

class _ResourceDetailCard extends ConsumerWidget {
  const _ResourceDetailCard({required this.state});

  final _ResourcesPaneState state;

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
    final activeTaskId = ref.watch(
      clientControllerProvider.select(
        (state) => _activeResourceDownloadTaskId(
          state.downloadTasks,
          detail.resourceId,
        ),
      ),
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(detail.name, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (detail.siteName.trim().isNotEmpty)
                  _MetaChip(
                    icon: Icons.class_outlined,
                    label: detail.siteName.trim(),
                  ),
                if (detail.ext != null && detail.ext!.trim().isNotEmpty)
                  _MetaChip(
                    icon: Icons.insert_drive_file_outlined,
                    label: detail.ext!.trim().toUpperCase(),
                  ),
                if (detail.sizeBytes != null)
                  _MetaChip(
                    icon: Icons.data_usage_outlined,
                    label: _formatBytes(detail.sizeBytes!),
                  ),
                if (detail.updatedAt.trim().isNotEmpty)
                  _MetaChip(
                    icon: Icons.schedule_outlined,
                    label: detail.updatedAt.trim(),
                  ),
              ],
            ),
            if (detail.description != null &&
                detail.description!.isNotEmpty) ...[
              const SizedBox(height: 8),
              SelectableText(detail.description!.trim()),
            ],
            if (detail.downloadUrl != null &&
                detail.downloadUrl!.trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              _LinkValue(url: detail.downloadUrl!.trim()),
            ],
            if (activeTaskId != null) ...[
              const SizedBox(height: 12),
              _ResourceDownloadProgress(itemId: activeTaskId),
            ],
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: activeTaskId != null
                    ? null
                    : () async {
                        final location = await getSaveLocation(
                          suggestedName: detail.name,
                        );
                        if (location != null && context.mounted) {
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
