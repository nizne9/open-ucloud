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
                _ErrorBanner(message: state.attendanceQrInputError!),
              ],
              if (parsed != null) ...[
                const SizedBox(height: 16),
                _QrPayloadField(label: '签到 ID', value: parsed.attendanceId),
                _QrPayloadField(label: '课程 ID', value: parsed.siteId),
                _QrPayloadField(label: '创建时间', value: parsed.createTime),
                _QrPayloadField(label: '课节 ID', value: parsed.classLessonId),
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

