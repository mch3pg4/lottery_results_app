import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lottery_results/main.dart';

void main() {
  testWidgets('Lottery dashboard renders and switches lottery selections',
      (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());

    expect(find.text('Lottery Results'), findsOneWidget);
    expect(find.text('Today'), findsOneWidget);
    expect(find.text('Choose lottery'), findsOneWidget);
    expect(find.text('Power Pick'), findsOneWidget);
    expect(find.text('Daily Lucky'), findsOneWidget);
    expect(find.text('Placeholder results'), findsOneWidget);

    expect(find.byKey(const Key('selected-lottery-name')), findsOneWidget);
    expect(find.byKey(const Key('selected-lottery-subtitle')), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const Key('selected-lottery-name'))).data,
      'Lotto Max',
    );
    expect(
      tester.widget<Text>(find.byKey(const Key('selected-lottery-subtitle')))
          .data,
      'Evening draw',
    );
    expect(find.text('04'), findsOneWidget);
    expect(find.text('09'), findsOneWidget);

    await tester.tap(find.text('Daily Lucky'));
    await tester.pumpAndSettle();

    expect(
      tester.widget<Text>(find.byKey(const Key('selected-lottery-name'))).data,
      'Daily Lucky',
    );
    expect(
      tester.widget<Text>(find.byKey(const Key('selected-lottery-subtitle')))
          .data,
      'Morning draw',
    );
    expect(find.text('01'), findsOneWidget);
    expect(find.text('12'), findsOneWidget);
  });
}
