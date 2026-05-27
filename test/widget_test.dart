import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lottery_results/main.dart';

void main() {
  testWidgets('Lottery dashboard renders and switches lottery selections', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MyApp());

    expect(find.text('Lottery Results'), findsOneWidget);
    expect(find.text('Choose lottery'), findsOneWidget);

    expect(find.text('West'), findsWidgets);
    expect(find.text('East'), findsWidgets);
    expect(find.text('Singapore'), findsWidgets);

    expect(find.widgetWithText(FilterChip, 'Magnum'), findsOneWidget);
    expect(find.widgetWithText(FilterChip, 'Sports Toto'), findsOneWidget);
    expect(find.widgetWithText(FilterChip, 'Damacai'), findsOneWidget);

    expect(find.byKey(const Key('selected-lottery-name')), findsOneWidget);
    expect(find.byKey(const Key('selected-lottery-subtitle')), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const Key('selected-lottery-name'))).data,
      'Magnum',
    );
    expect(find.text('No results available for this date'), findsOneWidget);
  });
}
