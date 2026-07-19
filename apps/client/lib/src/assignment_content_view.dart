import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:url_launcher/url_launcher.dart';

const _assignmentLineBreakMarker = '\u{E000}';
const _assignmentContentCacheLimit = 12;
final _assignmentContentBlockCache = <String, List<_AssignmentContentBlock>>{};

class AssignmentContentView extends StatefulWidget {
  const AssignmentContentView({super.key, required this.content});

  final String content;

  @override
  State<AssignmentContentView> createState() => _AssignmentContentViewState();
}

class _AssignmentContentViewState extends State<AssignmentContentView> {
  List<_AssignmentContentBlock>? _blocks;
  Future<List<_AssignmentContentBlock>>? _blocksFuture;

  @override
  void initState() {
    super.initState();
    _loadBlocks();
  }

  @override
  void didUpdateWidget(covariant AssignmentContentView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.content != widget.content) {
      _loadBlocks();
    }
  }

  void _loadBlocks() {
    final cached = _takeCachedAssignmentContent(widget.content);
    if (cached != null) {
      _blocks = cached;
      _blocksFuture = null;
      return;
    }
    _blocks = null;
    _blocksFuture = _parseAssignmentContentCachedAsync(widget.content);
  }

  @override
  Widget build(BuildContext context) {
    final blocks = _blocks;
    if (blocks != null) {
      return _buildBlocks(context, blocks);
    }
    final blocksFuture = _blocksFuture;
    if (blocksFuture == null) {
      return const SizedBox.shrink();
    }
    return FutureBuilder<List<_AssignmentContentBlock>>(
      future: blocksFuture,
      builder: (context, snapshot) {
        final blocks = snapshot.data;
        if (blocks == null) {
          return const SizedBox.shrink();
        }
        return _buildBlocks(context, blocks);
      },
    );
  }

  Widget _buildBlocks(
    BuildContext context,
    List<_AssignmentContentBlock> blocks,
  ) {
    if (blocks.isEmpty) {
      return const SizedBox.shrink();
    }
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 920),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerLowest,
          border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final block in blocks) _AssignmentContentBlockView(block),
            ],
          ),
        ),
      ),
    );
  }
}

class _AssignmentContentBlockView extends StatelessWidget {
  const _AssignmentContentBlockView(this.block);

  final _AssignmentContentBlock block;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    switch (block.kind) {
      case _AssignmentContentKind.image:
        return _AssignmentImageView(alt: block.text, src: block.src ?? '');
      case _AssignmentContentKind.table:
        return _AssignmentTableView(rows: block.rows ?? const []);
      case _AssignmentContentKind.heading:
      case _AssignmentContentKind.listItem:
      case _AssignmentContentKind.paragraph:
        final style = switch (block.kind) {
          _AssignmentContentKind.heading => theme.titleMedium,
          _ => theme.bodyMedium,
        };
        return Padding(
          padding: EdgeInsets.only(
            bottom: block.kind == _AssignmentContentKind.heading ? 10 : 8,
          ),
          child: SelectableText(
            block.displayText,
            style: style?.copyWith(height: 1.45),
          ),
        );
    }
  }
}

/// Images cannot be rendered inline: upstream image URLs usually require the
/// Rust-held session, so we surface a visible placeholder with link actions
/// instead of silently dropping them.
class _AssignmentImageView extends StatelessWidget {
  const _AssignmentImageView({required this.alt, required this.src});

  final String alt;
  final String src;

  String get _label {
    if (alt.trim().isNotEmpty) {
      return alt.trim();
    }
    final fileName = Uri.tryParse(src)?.pathSegments.lastWhere(
      (segment) => segment.isNotEmpty,
      orElse: () => '',
    );
    return fileName == null || fileName.isEmpty ? '图片' : fileName;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: colorScheme.outlineVariant),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            const SizedBox(width: 12),
            Icon(Icons.image_outlined, color: colorScheme.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(_label, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
            IconButton(
              tooltip: '打开图片',
              onPressed: () => _openImage(context),
              icon: const Icon(Icons.open_in_new_outlined),
            ),
            IconButton(
              tooltip: '复制图片链接',
              onPressed: () => _copyImageLink(context),
              icon: const Icon(Icons.copy_outlined),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openImage(BuildContext context) async {
    final uri = Uri.tryParse(src.trim());
    final opened =
        uri != null &&
        uri.hasScheme &&
        await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && context.mounted) {
      _showImageSnackBar(context, '无法打开图片链接');
    }
  }

  Future<void> _copyImageLink(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: src));
    if (context.mounted) {
      _showImageSnackBar(context, '已复制图片链接');
    }
  }

  void _showImageSnackBar(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

class _AssignmentTableView extends StatelessWidget {
  const _AssignmentTableView({required this.rows});

  final List<List<String>> rows;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return const SizedBox.shrink();
    }
    final columnCount = rows.fold<int>(
      0,
      (max, row) => row.length > max ? row.length : max,
    );
    if (columnCount == 0) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Table(
        border: TableBorder.all(
          color: Theme.of(context).colorScheme.outlineVariant,
          borderRadius: BorderRadius.circular(8),
        ),
        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
        children: [
          for (final row in rows)
            TableRow(
              children: [
                for (var index = 0; index < columnCount; index += 1)
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: SelectableText(
                      index < row.length ? row[index] : '',
                      style: Theme.of(
                        context,
                      ).textTheme.bodyMedium?.copyWith(height: 1.45),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

enum _AssignmentContentKind { heading, paragraph, listItem, image, table }

class _AssignmentContentBlock {
  const _AssignmentContentBlock({
    required this.kind,
    required this.text,
    this.listMarker,
    this.src,
    this.rows,
  });

  final _AssignmentContentKind kind;
  final String text;
  final String? listMarker;
  final String? src;
  final List<List<String>>? rows;

  String get displayText {
    final marker = listMarker;
    return marker == null ? text : '$marker $text';
  }
}

typedef _AssignmentContentBlockPayload = Map<String, Object?>;

List<_AssignmentContentBlockPayload> _parseAssignmentContent(String content) {
  final html = content.trim();
  if (html.isEmpty) {
    return const [];
  }
  final blocks = <_AssignmentContentBlockPayload>[];
  final fragment = html_parser.parseFragment(html);
  for (final node in fragment.nodes) {
    _collectAssignmentBlocks(node, blocks);
  }
  if (blocks.isEmpty) {
    final text = _normalizeAssignmentText(fragment.text ?? html);
    if (text.isNotEmpty) {
      return [
        _assignmentContentBlockPayload(
          kind: _AssignmentContentKind.paragraph,
          text: text,
        ),
      ];
    }
  }
  return blocks;
}

List<_AssignmentContentBlock>? _takeCachedAssignmentContent(String content) {
  final cached = _assignmentContentBlockCache.remove(content);
  if (cached != null) {
    _assignmentContentBlockCache[content] = cached;
  }
  return cached;
}

Future<List<_AssignmentContentBlock>> _parseAssignmentContentCachedAsync(
  String content,
) async {
  final cached = _takeCachedAssignmentContent(content);
  if (cached != null) {
    return cached;
  }
  final payloads = await compute(
    _parseAssignmentContent,
    content,
    debugLabel: 'parse assignment content',
  );
  final blocks = List<_AssignmentContentBlock>.unmodifiable(
    payloads.map(_assignmentContentBlockFromPayload),
  );
  _assignmentContentBlockCache[content] = blocks;
  if (_assignmentContentBlockCache.length > _assignmentContentCacheLimit) {
    _assignmentContentBlockCache.remove(
      _assignmentContentBlockCache.keys.first,
    );
  }
  return blocks;
}

void _collectAssignmentBlocks(
  dom.Node node,
  List<_AssignmentContentBlockPayload> blocks,
) {
  if (node is! dom.Element) {
    return;
  }
  final tag = node.localName?.toLowerCase();
  if (tag == null) {
    return;
  }
  if (tag.startsWith('h') && tag.length == 2) {
    _addTextBlock(blocks, _AssignmentContentKind.heading, _elementText(node));
    return;
  }
  if (tag == 'img') {
    _addImageBlock(node, blocks);
    return;
  }
  if (tag == 'table') {
    _addTableBlock(node, blocks);
    return;
  }
  if (tag == 'p') {
    _addTextBlock(blocks, _AssignmentContentKind.paragraph, _elementText(node));
    for (final image in node.querySelectorAll('img')) {
      _addImageBlock(image, blocks);
    }
    return;
  }
  if (tag == 'div' || tag == 'blockquote') {
    final blockCount = blocks.length;
    for (final child in node.nodes) {
      _collectAssignmentBlocks(child, blocks);
    }
    if (blocks.length == blockCount) {
      _addTextBlock(
        blocks,
        _AssignmentContentKind.paragraph,
        _elementText(node),
      );
    }
    return;
  }
  if (tag == 'pre') {
    _addTextBlock(
      blocks,
      _AssignmentContentKind.paragraph,
      node.text,
      preserveLineBreaks: true,
    );
    return;
  }
  if (tag == 'ul' || tag == 'ol') {
    _collectListItems(node, blocks, ordered: tag == 'ol');
    return;
  }
  if (tag == 'li') {
    _addTextBlock(
      blocks,
      _AssignmentContentKind.listItem,
      _elementText(node),
      marker: '-',
    );
    return;
  }
  for (final child in node.nodes) {
    _collectAssignmentBlocks(child, blocks);
  }
}

void _collectListItems(
  dom.Element list,
  List<_AssignmentContentBlockPayload> blocks, {
  required bool ordered,
}) {
  var index = 0;
  for (final item in list.children.where((child) => child.localName == 'li')) {
    index += 1;
    _addTextBlock(
      blocks,
      _AssignmentContentKind.listItem,
      _elementText(item),
      marker: ordered ? '$index.' : '-',
    );
  }
}

void _addImageBlock(
  dom.Element image,
  List<_AssignmentContentBlockPayload> blocks,
) {
  final src = image.attributes['src']?.trim() ?? '';
  if (src.isEmpty) {
    return;
  }
  blocks.add(
    _assignmentContentBlockPayload(
      kind: _AssignmentContentKind.image,
      text: _normalizeAssignmentText(image.attributes['alt']?.trim() ?? ''),
      src: src,
    ),
  );
}

void _addTableBlock(
  dom.Element table,
  List<_AssignmentContentBlockPayload> blocks,
) {
  final rows = <List<String>>[];
  for (final row in table.querySelectorAll('tr')) {
    final cells = [
      for (final cell in row.querySelectorAll('th, td'))
        _normalizeAssignmentText(_elementText(cell)),
    ];
    if (cells.any((cell) => cell.isNotEmpty)) {
      rows.add(cells);
    }
  }
  if (rows.isEmpty) {
    _addTextBlock(
      blocks,
      _AssignmentContentKind.paragraph,
      _elementText(table),
    );
    return;
  }
  blocks.add(
    _assignmentContentBlockPayload(
      kind: _AssignmentContentKind.table,
      text: '',
      rows: rows,
    ),
  );
}

void _addTextBlock(
  List<_AssignmentContentBlockPayload> blocks,
  _AssignmentContentKind kind,
  String text, {
  String? marker,
  bool preserveLineBreaks = false,
}) {
  final normalized = _normalizeAssignmentText(
    text,
    preserveLineBreaks: preserveLineBreaks,
  );
  if (normalized.isEmpty) {
    return;
  }
  blocks.add(
    _assignmentContentBlockPayload(
      kind: kind,
      text: normalized,
      listMarker: marker,
    ),
  );
}

_AssignmentContentBlockPayload _assignmentContentBlockPayload({
  required _AssignmentContentKind kind,
  required String text,
  String? listMarker,
  String? src,
  List<List<String>>? rows,
}) {
  return {
    'kind': kind.name,
    'text': text,
    ...?(listMarker == null ? null : {'listMarker': listMarker}),
    ...?(src == null ? null : {'src': src}),
    ...?(rows == null ? null : {'rows': rows}),
  };
}

_AssignmentContentBlock _assignmentContentBlockFromPayload(
  _AssignmentContentBlockPayload payload,
) {
  final kindName = payload['kind'] as String?;
  final kind = switch (kindName) {
    'heading' => _AssignmentContentKind.heading,
    'listItem' => _AssignmentContentKind.listItem,
    'image' => _AssignmentContentKind.image,
    'table' => _AssignmentContentKind.table,
    _ => _AssignmentContentKind.paragraph,
  };
  return _AssignmentContentBlock(
    kind: kind,
    text: payload['text'] as String? ?? '',
    listMarker: payload['listMarker'] as String?,
    src: payload['src'] as String?,
    rows: (payload['rows'] as List?)
        ?.map(
          (row) => (row as List).map((cell) => cell as String? ?? '').toList(),
        )
        .toList(),
  );
}

String _elementText(dom.Element element) {
  final buffer = StringBuffer();
  _writeElementText(element, buffer);
  return buffer.toString();
}

void _writeElementText(dom.Node node, StringBuffer buffer) {
  if (node is dom.Text) {
    buffer.write(node.text);
    return;
  }
  if (node is! dom.Element) {
    return;
  }
  final tag = node.localName?.toLowerCase();
  if (tag == 'br') {
    buffer.write(_assignmentLineBreakMarker);
    return;
  }
  final linkTextStart = buffer.length;
  for (final child in node.nodes) {
    _writeElementText(child, buffer);
  }
  if (tag == 'a') {
    final href = node.attributes['href']?.trim();
    // Append the href only when the link's own text does not already show it.
    final linkText = buffer.toString().substring(linkTextStart);
    if (href != null && href.isNotEmpty && !linkText.contains(href)) {
      buffer.write(' ($href)');
    }
  }
}

String _normalizeAssignmentText(
  String value, {
  bool preserveLineBreaks = false,
}) {
  var normalized = value.replaceAll('\u00a0', ' ');
  if (preserveLineBreaks) {
    normalized = normalized.replaceAll('\n', _assignmentLineBreakMarker);
  }
  return normalized
      .replaceAll(RegExp(r'\s+'), ' ')
      .replaceAll(_assignmentLineBreakMarker, '\n')
      .replaceAll(RegExp(r' *\n *'), '\n')
      .trim();
}
