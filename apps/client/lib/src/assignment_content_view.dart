import 'package:flutter/material.dart';

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

class _AssignmentListContext {
  _AssignmentListContext(this.ordered);

  final bool ordered;
  int index = 0;
}

List<_AssignmentContentBlock> _parseAssignmentContent(String content) {
  final html = content.trim();
  if (html.isEmpty) {
    return const [];
  }
  final blocks = <_AssignmentContentBlock>[];
  final stack = <_AssignmentListContext>[];
  final blockPattern = RegExp(
    r'<(h[1-6]|p|li)\b[^>]*>(.*?)</\1>',
    caseSensitive: false,
    dotAll: true,
  );
  var cursor = 0;

  for (final match in blockPattern.allMatches(html)) {
    _updateAssignmentListStack(html.substring(cursor, match.start), stack);
    final tag = match.group(1)!.toLowerCase();
    final text = _assignmentPlainText(match.group(2)!);
    if (text.isNotEmpty) {
      if (tag == 'li') {
        final context = stack.isEmpty ? null : stack.last;
        final marker = context == null
            ? '-'
            : context.ordered
            ? '${++context.index}.'
            : '-';
        blocks.add(
          _AssignmentContentBlock(
            kind: _AssignmentContentKind.listItem,
            text: text,
            listMarker: marker,
          ),
        );
      } else if (tag.startsWith('h')) {
        blocks.add(
          _AssignmentContentBlock(
            kind: _AssignmentContentKind.heading,
            text: text,
          ),
        );
      } else {
        blocks.add(
          _AssignmentContentBlock(
            kind: _AssignmentContentKind.paragraph,
            text: text,
          ),
        );
      }
    }
    cursor = match.end;
  }

  _updateAssignmentListStack(html.substring(cursor), stack);
  if (blocks.isEmpty) {
    final text = _assignmentPlainText(html);
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

void _updateAssignmentListStack(
  String segment,
  List<_AssignmentListContext> stack,
) {
  final tagPattern = RegExp(r'</?(ol|ul)\b[^>]*>', caseSensitive: false);
  for (final match in tagPattern.allMatches(segment)) {
    final tag = match.group(0)!.toLowerCase();
    final isClosing = tag.startsWith('</');
    final isOrdered = tag.contains('ol');
    if (!isClosing) {
      stack.add(_AssignmentListContext(isOrdered));
      continue;
    }
    final index = stack.lastIndexWhere(
      (context) => context.ordered == isOrdered,
    );
    if (index >= 0) {
      stack.removeRange(index, stack.length);
    }
  }
}

String _assignmentPlainText(String html) {
  return _decodeAssignmentHtmlEntities(html)
      .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'<[^>]+>'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

String _decodeAssignmentHtmlEntities(String value) {
  return value.replaceAllMapped(RegExp(r'&(#x?[0-9a-fA-F]+|[a-zA-Z]+);'), (
    match,
  ) {
    final entity = match.group(1)!;
    return switch (entity) {
      'nbsp' => ' ',
      'amp' => '&',
      'lt' => '<',
      'gt' => '>',
      'quot' => '"',
      'apos' => "'",
      _ when entity.startsWith('#x') || entity.startsWith('#X') =>
        String.fromCharCode(int.tryParse(entity.substring(2), radix: 16) ?? 0),
      _ when entity.startsWith('#') => String.fromCharCode(
        int.tryParse(entity.substring(1)) ?? 0,
      ),
      _ => match.group(0)!,
    };
  });
}
