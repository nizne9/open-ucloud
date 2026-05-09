import 'package:flutter/material.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

class AssignmentContentView extends StatelessWidget {
  const AssignmentContentView({super.key, required this.content});

  final String content;

  @override
  Widget build(BuildContext context) {
    final blocks = _parseAssignmentContent(content);
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
    final style = switch (block.kind) {
      _AssignmentContentKind.heading => theme.titleMedium,
      _AssignmentContentKind.listItem => theme.bodyMedium,
      _AssignmentContentKind.paragraph => theme.bodyMedium,
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

enum _AssignmentContentKind { heading, paragraph, listItem }

class _AssignmentContentBlock {
  const _AssignmentContentBlock({
    required this.kind,
    required this.text,
    this.listMarker,
  });

  final _AssignmentContentKind kind;
  final String text;
  final String? listMarker;

  String get displayText {
    final marker = listMarker;
    return marker == null ? text : '$marker $text';
  }
}

List<_AssignmentContentBlock> _parseAssignmentContent(String content) {
  final html = content.trim();
  if (html.isEmpty) {
    return const [];
  }
  final blocks = <_AssignmentContentBlock>[];
  final fragment = html_parser.parseFragment(html);
  for (final node in fragment.nodes) {
    _collectAssignmentBlocks(node, blocks);
  }
  if (blocks.isEmpty) {
    final text = _normalizeAssignmentText(fragment.text ?? html);
    if (text.isNotEmpty) {
      return [
        _AssignmentContentBlock(
          kind: _AssignmentContentKind.paragraph,
          text: text,
        ),
      ];
    }
  }
  return blocks;
}

void _collectAssignmentBlocks(
  dom.Node node,
  List<_AssignmentContentBlock> blocks,
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
  if (tag == 'p') {
    _addTextBlock(blocks, _AssignmentContentKind.paragraph, _elementText(node));
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
    _addTextBlock(blocks, _AssignmentContentKind.paragraph, node.text);
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
  List<_AssignmentContentBlock> blocks, {
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

void _addTextBlock(
  List<_AssignmentContentBlock> blocks,
  _AssignmentContentKind kind,
  String text, {
  String? marker,
}) {
  final normalized = _normalizeAssignmentText(text);
  if (normalized.isEmpty) {
    return;
  }
  blocks.add(
    _AssignmentContentBlock(kind: kind, text: normalized, listMarker: marker),
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
    buffer.write('\n');
    return;
  }
  for (final child in node.nodes) {
    _writeElementText(child, buffer);
  }
  if (tag == 'a') {
    final href = node.attributes['href']?.trim();
    if (href != null && href.isNotEmpty && !buffer.toString().contains(href)) {
      buffer.write(' ($href)');
    }
  }
}

String _normalizeAssignmentText(String value) {
  return value
      .replaceAll('\u00a0', ' ')
      .replaceAll(RegExp(r'[ \t\r\f]+'), ' ')
      .trim();
}
