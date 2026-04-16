import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:koffiloop/main.dart';

void main() {
  testWidgets('Counter increments smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const KofiLoopApp());
    await tester.pumpAndSettle();

    expect(find.text('Welcome to KofiLoop'), findsOneWidget);
    expect(find.text('0'), findsOneWidget);
    expect(find.text('1'), findsNothing);

    await tester.tap(find.byIcon(Icons.add));
    await tester.pump();

    expect(find.text('0'), findsNothing);
    expect(find.text('1'), findsOneWidget);
  });
}
