import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_cloud_client/src/assignment_content_view.dart';

void main() {
  Future<void> pumpContent(WidgetTester tester, String content) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: AssignmentContentView(content: content)),
      ),
    );
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
  }

  testWidgets('uncached assignment content parses after the first frame', (
    tester,
  ) async {
    const content = '<p>异步解析的作业要求</p>';

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: AssignmentContentView(content: content)),
      ),
    );

    expect(find.text('异步解析的作业要求'), findsNothing);

    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();

    expect(find.text('异步解析的作业要求'), findsOneWidget);
  });

  testWidgets('images render as visible placeholders instead of disappearing', (
    tester,
  ) async {
    await pumpContent(
      tester,
      '<p>根据下图作答</p>'
      '<p><img src="https://example.com/figure1.png" alt="图 1 结构示意图"></p>',
    );

    expect(find.text('根据下图作答'), findsOneWidget);
    expect(find.text('图 1 结构示意图'), findsOneWidget);
    expect(find.byIcon(Icons.image_outlined), findsOneWidget);
  });

  testWidgets('images without alt fall back to the file name', (tester) async {
    await pumpContent(
      tester,
      '<img src="https://example.com/files/diagram.png">',
    );

    expect(find.text('diagram.png'), findsOneWidget);
  });

  testWidgets('tables render rows and cells instead of flattening away', (
    tester,
  ) async {
    await pumpContent(
      tester,
      '<table><tr><th>名称</th><th>数量</th></tr>'
      '<tr><td>样本</td><td>3</td></tr></table>',
    );

    expect(find.text('名称'), findsOneWidget);
    expect(find.text('数量'), findsOneWidget);
    expect(find.text('样本'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
  });
}
