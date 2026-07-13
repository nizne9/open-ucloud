part of 'home_screen.dart';

void _openAttendanceQrDialog(BuildContext context, WidgetRef ref) {
  ref
      .read(clientControllerProvider.notifier)
      .clearAttendanceQrPayloadParseState();
  showDialog<void>(
    context: context,
    builder: (_) => const _AttendanceQrPayloadDialog(),
  );
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
    final state = ref.watch(
      clientControllerProvider.select(
        (state) => (
          parsedAttendanceQrPayload: state.parsedAttendanceQrPayload,
          attendanceQrInputError: state.attendanceQrInputError,
          courses: state.courses,
        ),
      ),
    );
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
                _StatusBanner(
                  kind: _BannerKind.error,
                  message: state.attendanceQrInputError!,
                ),
              ],
              if (parsed != null) ...[
                const SizedBox(height: 16),
                _LabelValueRow(
                  label: '签到 ID',
                  value: parsed.attendanceId,
                  labelWidth: 112,
                  labelStyle: Theme.of(context).textTheme.labelLarge,
                  bottomPadding: 8,
                  selectable: true,
                ),
                _LabelValueRow(
                  label: '课程 ID',
                  value: parsed.siteId,
                  labelWidth: 112,
                  labelStyle: Theme.of(context).textTheme.labelLarge,
                  bottomPadding: 8,
                  selectable: true,
                ),
                _LabelValueRow(
                  label: '创建时间',
                  value: parsed.createTime,
                  labelWidth: 112,
                  labelStyle: Theme.of(context).textTheme.labelLarge,
                  bottomPadding: 8,
                  selectable: true,
                ),
                _LabelValueRow(
                  label: '课节 ID',
                  value: parsed.classLessonId,
                  labelWidth: 112,
                  labelStyle: Theme.of(context).textTheme.labelLarge,
                  bottomPadding: 8,
                  selectable: true,
                ),
                if (matchedCourse != null)
                  _LabelValueRow(
                    label: '课程',
                    value: matchedCourse.name,
                    labelWidth: 112,
                    labelStyle: Theme.of(context).textTheme.labelLarge,
                    bottomPadding: 8,
                    selectable: true,
                  ),
                if (matchedCourse?.going ?? false)
                  _LabelValueRow(
                    label: '状态',
                    value: '正在进行',
                    labelWidth: 112,
                    labelStyle: Theme.of(context).textTheme.labelLarge,
                    bottomPadding: 8,
                    selectable: true,
                  ),
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
