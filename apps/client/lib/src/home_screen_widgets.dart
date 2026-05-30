part of 'home_screen.dart';
class _DetailPlaceholder extends StatelessWidget {
  const _DetailPlaceholder({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 42, color: colorScheme.outline),
            const SizedBox(height: 12),
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

const _downloadSummaryInlinePathLimit = 5;

class _DownloadSummary extends StatefulWidget {
  const _DownloadSummary({required this.paths});

  final List<String> paths;

  @override
  State<_DownloadSummary> createState() => _DownloadSummaryState();
}

class _DownloadSummaryState extends State<_DownloadSummary> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final paths = widget.paths;
    final longList = paths.length > _downloadSummaryInlinePathLimit;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  Icons.check_circle_outline,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  '已下载 ${paths.length} 个文件',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ],
            ),
            if (longList) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () {
                    setState(() {
                      _expanded = !_expanded;
                    });
                  },
                  icon: Icon(_expanded ? Icons.expand_less : Icons.expand_more),
                  label: Text(_expanded ? '隐藏文件路径' : '显示文件路径'),
                ),
              ),
            ],
            if (!longList) ...[
              const SizedBox(height: 12),
              for (final path in paths)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: SelectableText(path),
                ),
            ] else if (_expanded) ...[
              const SizedBox(height: 8),
              SizedBox(
                height: 220,
                child: ListView.separated(
                  primary: false,
                  itemCount: paths.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 6),
                  itemBuilder: (context, index) => SelectableText(paths[index]),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _FeedbackBanners extends StatelessWidget {
  const _FeedbackBanners.values({
    required this.errorMessage,
    required this.operationMessage,
    required this.activeOperationContext,
    this.operationContext,
  });

  final String? errorMessage;
  final String? operationMessage;
  final OperationContext? activeOperationContext;
  final OperationContext? operationContext;

  @override
  Widget build(BuildContext context) {
    final visibleOperationMessage = activeOperationContext == operationContext
        ? operationMessage
        : null;
    if (errorMessage == null && visibleOperationMessage == null) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (errorMessage != null) ...[
          _ErrorBanner(message: errorMessage!),
          const SizedBox(height: 12),
        ],
        if (visibleOperationMessage != null) ...[
          _InfoBanner(message: visibleOperationMessage),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.label,
    this.action,
    this.compact = false,
  });

  final IconData icon;
  final String label;
  final Widget? action;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final iconSize = compact ? 36.0 : 48.0;
    final spacing = compact ? 8.0 : 12.0;
    final textStyle = compact ? null : Theme.of(context).textTheme.titleMedium;
    final actionSpacing = compact ? 12.0 : 16.0;
    final child = Column(
      children: [
        Icon(icon, size: iconSize, color: Theme.of(context).colorScheme.outline),
        SizedBox(height: spacing),
        Text(label, textAlign: TextAlign.center, style: textStyle),
        if (action != null) ...[
          SizedBox(height: actionSpacing),
          action!,
        ],
      ],
    );
    if (compact) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: child,
      );
    }
    return child;
  }
}

Future<bool> _confirm(
  BuildContext context, {
  required String title,
  required String content,
  String confirmLabel = '确认',
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
              child: Text(confirmLabel),
            ),
          ],
        ),
      ) ??
      false;
}

Future<void> _openExternalLink(BuildContext context, String value) async {
  final uri = Uri.tryParse(value.trim());
  if (uri == null || !uri.hasScheme) {
    _showSnackBar(context, '链接格式无效');
    return;
  }
  final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
  if (!opened && context.mounted) {
    _showSnackBar(context, '无法打开链接');
  }
}

Future<void> _copyText(BuildContext context, String value) async {
  await Clipboard.setData(ClipboardData(text: value));
  if (context.mounted) {
    _showSnackBar(context, '已复制链接');
  }
}

void _showSnackBar(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
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

class _InfoBanner extends StatelessWidget {
  const _InfoBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.check_circle_outline,
              color: colorScheme.onPrimaryContainer,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: TextStyle(color: colorScheme.onPrimaryContainer),
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
      return const Text('验证码图片加载失败', textAlign: TextAlign.center);
    }
    return Center(
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: Theme.of(context).colorScheme.outline),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Image.memory(
            bytes,
            height: 72,
            fit: BoxFit.contain,
            semanticLabel: '验证码图片',
          ),
        ),
      ),
    );
  }

  typed_data.Uint8List? _decodeDataUri(String? dataUri) {
    if (dataUri == null) {
      return null;
    }
    final comma = dataUri.indexOf(',');
    if (comma == -1) {
      return null;
    }
    try {
      return base64Decode(dataUri.substring(comma + 1));
    } on FormatException {
      return null;
    }
  }
}
