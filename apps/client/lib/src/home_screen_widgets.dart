part of 'home_screen.dart';
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
  const _FeedbackBanners({
    required this.errorMessage,
    required this.operationMessage,
    required this.activeOperationContext,
    this.operationContext,
    this.bottomSpacing = 12,
  });

  final String? errorMessage;
  final String? operationMessage;
  final OperationContext? activeOperationContext;
  final OperationContext? operationContext;
  final double bottomSpacing;

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
          _StatusBanner(kind: _BannerKind.error, message: errorMessage!),
          const SizedBox(height: 12),
        ],
        if (visibleOperationMessage != null) ...[
          _StatusBanner(kind: _BannerKind.info, message: visibleOperationMessage),
          SizedBox(height: bottomSpacing),
        ],
      ],
    );
  }
}

BoxDecoration _outlinedBoxDecoration(ColorScheme colorScheme) {
  return BoxDecoration(
    border: Border.all(color: colorScheme.outlineVariant),
    borderRadius: BorderRadius.circular(8),
  );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.label,
    this.subtitle,
    this.action,
    this.compact = false,
    this.bordered = false,
  });

  final IconData icon;
  final String label;
  final String? subtitle;
  final Widget? action;
  final bool compact;
  final bool bordered;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    final iconSize = compact ? 36.0 : (bordered ? 42.0 : 48.0);
    final topSpacing = compact ? 8.0 : 12.0;
    final labelStyle = compact ? null : theme.textTheme.titleMedium;
    final child = Column(
      children: [
        Icon(icon, size: iconSize, color: colorScheme.outline),
        SizedBox(height: topSpacing),
        Text(label, textAlign: TextAlign.center, style: labelStyle),
        if (subtitle != null) ...[
          SizedBox(height: bordered ? 6.0 : 0.0),
          Text(
            subtitle!,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        if (action != null) ...[
          SizedBox(height: compact ? 12.0 : 16.0),
          action!,
        ],
      ],
    );
    if (bordered) {
      return DecoratedBox(
        decoration: _outlinedBoxDecoration(colorScheme),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
          child: child,
        ),
      );
    }
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

Key _courseDropdownKey(
  String scope,
  List<CourseItem> courses,
  String? selectedCourseId,
) {
  final courseIds = courses.map((course) => course.id).join('|');
  return ValueKey<String>('$scope:$selectedCourseId:$courseIds');
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

enum _BannerKind { error, info }

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({
    required this.message,
    required this.kind,
  });

  final String message;
  final _BannerKind kind;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final (backgroundColor, foregroundColor, iconData) = switch (kind) {
      _BannerKind.error => (
          colorScheme.errorContainer,
          colorScheme.onErrorContainer,
          Icons.error_outline,
        ),
      _BannerKind.info => (
          colorScheme.primaryContainer,
          colorScheme.onPrimaryContainer,
          Icons.check_circle_outline,
        ),
    };
    return DecoratedBox(
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(iconData, color: foregroundColor),
            const SizedBox(width: 8),
            Expanded(child: Text(message, style: TextStyle(color: foregroundColor))),
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
