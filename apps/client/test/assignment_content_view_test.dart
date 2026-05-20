import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_cloud_client/src/assignment_content_view.dart';

void main() {
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
}
