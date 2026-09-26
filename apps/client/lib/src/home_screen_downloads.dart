part of 'home_screen.dart';

String? _activeCourseDownloadTaskId(
  List<DownloadTaskItem> tasks,
  String? siteId,
) {
  if (siteId == null) {
    return null;
  }
  return tasks
      .where(
        (task) =>
            task.isCourseDownload && task.siteId == siteId && !task.isTerminal,
      )
      .firstOrNull
      ?.id;
}

String? _activeResourceDownloadTaskId(
  List<DownloadTaskItem> tasks,
  String? resourceId,
) {
  if (resourceId == null) {
    return null;
  }
  return tasks
      .where(
        (task) =>
            !task.isCourseDownload &&
            task.resourceId == resourceId &&
            !task.isTerminal,
      )
      .firstOrNull
      ?.id;
}

String _downloadTaskProgressText({
  required int current,
  required int total,
  required BigInt bytes,
  String? fileName,
}) {
  final progressText = total == 0 ? '正在准备下载' : '正在下载 $current / $total 个文件';
  final trimmedName = fileName?.trim();
  final bytesText = bytes <= BigInt.zero ? null : _formatBytes(bytes);
  final details = [
    ?(trimmedName == null || trimmedName.isEmpty ? null : trimmedName),
    ?bytesText,
  ];
  return details.isEmpty
      ? progressText
      : '$progressText · ${details.join(' · ')}';
}

String _downloadTaskStatusText(DownloadTaskItem task) {
  if (task.isQueued) {
    return '排队等待下载';
  }
  final status = task.status;
  if (status == null) {
    return '正在准备下载';
  }
  return switch (status.state) {
    FfiDownloadTaskState.queued => '排队等待下载',
    FfiDownloadTaskState.running => _downloadTaskProgressText(
      current: status.current,
      total: status.total,
      bytes: status.bytesDownloaded,
      fileName: status.currentFileName,
    ),
    FfiDownloadTaskState.succeeded =>
      '下载完成 · ${status.writtenPaths.length} 个文件',
    FfiDownloadTaskState.failed => status.errorMessage ?? '下载失败。',
    FfiDownloadTaskState.cancelled => '下载已取消',
  };
}

IconData _downloadTaskIcon(DownloadTaskItem task) {
  if (task.isQueued) {
    return Icons.schedule_outlined;
  }
  return switch (task.status?.state) {
    FfiDownloadTaskState.succeeded => Icons.check_circle_outline,
    FfiDownloadTaskState.failed => Icons.error_outline,
    FfiDownloadTaskState.cancelled => Icons.cancel_outlined,
    _ => Icons.downloading_outlined,
  };
}

class _DownloadCenterButton extends ConsumerWidget {
  const _DownloadCenterButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeCount = ref.watch(
      clientControllerProvider.select(
        (state) => state.downloadTasks.where((task) => !task.isTerminal).length,
      ),
    );
    return IconButton(
      tooltip: '下载中心',
      onPressed: () => _openDownloadCenter(context),
      icon: Badge.count(
        count: activeCount,
        isLabelVisible: activeCount > 0,
        child: const Icon(Icons.download_outlined),
      ),
    );
  }
}

void _openDownloadCenter(BuildContext context) {
  showDialog<void>(
    context: context,
    builder: (_) => const _DownloadCenterDialog(),
  );
}

class _DownloadCenterDialog extends ConsumerWidget {
  const _DownloadCenterDialog();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasks = ref.watch(
      clientControllerProvider.select((state) => state.downloadTasks),
    );
    final controller = ref.read(clientControllerProvider.notifier);
    final hasFinished = tasks.any((task) => task.isTerminal);
    return AlertDialog(
      title: const Text('下载中心'),
      content: SizedBox(
        width: 560,
        child: tasks.isEmpty
            ? const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Text('暂无下载任务', textAlign: TextAlign.center),
              )
            : ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 480),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: tasks.length,
                  itemBuilder: (context, index) =>
                      _DownloadTaskTile(task: tasks[index]),
                ),
              ),
      ),
      actions: [
        if (hasFinished)
          TextButton(
            onPressed: () {
              controller.clearFinishedDownloads();
            },
            child: const Text('清空已完成'),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('关闭'),
        ),
      ],
    );
  }
}

class _DownloadTaskTile extends ConsumerWidget {
  const _DownloadTaskTile({required this.task});

  final DownloadTaskItem task;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = task.status;
    final writtenPaths = status?.writtenPaths ?? const <String>[];
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(_downloadTaskIcon(task), size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _TooltipText(task.label),
                      const SizedBox(height: 2),
                      Text(
                        _downloadTaskStatusText(task),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                if (!task.isTerminal)
                  IconButton(
                    tooltip: '取消下载',
                    onPressed: () => unawaited(
                      ref
                          .read(clientControllerProvider.notifier)
                          .cancelDownloadTask(task.id),
                    ),
                    icon: const Icon(Icons.close),
                  ),
              ],
            ),
            if (task.isRunning) ...[
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: status!.total == 0
                    ? null
                    : status.current / status.total,
              ),
            ],
            if (task.isTerminal && writtenPaths.isNotEmpty) ...[
              const SizedBox(height: 8),
              _DownloadSummary(paths: writtenPaths),
            ],
          ],
        ),
      ),
    );
  }
}
