import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lynk_core/core.dart';
import 'package:lynk_x/presentation/features/homepage/widgets/unread_badge.dart';

Widget _host(int count) => MaterialApp(
      home: Scaffold(body: Center(child: UnreadBadge(count: count))),
    );

void main() {
  testWidgets('shows the real count', (tester) async {
    await tester.pumpWidget(_host(7));
    expect(find.text('7'), findsOneWidget);
  });

  testWidgets('caps large counts at 99+', (tester) async {
    await tester.pumpWidget(_host(142));
    expect(find.text('99+'), findsOneWidget);
    expect(find.text('142'), findsNothing);
  });

  testWidgets('renders nothing for zero', (tester) async {
    await tester.pumpWidget(_host(0));
    expect(find.byType(Text), findsNothing);
    expect(tester.getSize(find.byType(UnreadBadge)), Size.zero);
  });

  testWidgets('is a pill that grows with its text but never shrinks below 22', (tester) async {
    await tester.pumpWidget(_host(1));
    final one = tester.getSize(find.byType(UnreadBadge));
    await tester.pumpWidget(_host(99));
    final ninetyNine = tester.getSize(find.byType(UnreadBadge));
    await tester.pumpWidget(_host(500));
    final capped = tester.getSize(find.byType(UnreadBadge));

    expect(one.height, 22);
    expect(one.width, greaterThanOrEqualTo(22));
    expect(ninetyNine.width, greaterThan(one.width));
    expect(capped.width, greaterThan(ninetyNine.width), reason: '"99+" is wider than "99"');
  });

  testWidgets('uses the accent color with dark text for contrast on the brand green', (tester) async {
    await tester.pumpWidget(_host(3));
    final box = tester.widget<DecoratedBox>(find.descendant(of: find.byType(UnreadBadge), matching: find.byType(DecoratedBox)));
    expect((box.decoration as BoxDecoration).color, AppColors.primary);
    final text = tester.widget<Text>(find.text('3'));
    expect(text.style!.color, Colors.black);
  });

  testWidgets('has a spoken label with the count', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_host(1));
    expect(find.bySemanticsLabel('1 unread message'), findsOneWidget);
    await tester.pumpWidget(_host(42));
    expect(find.bySemanticsLabel('42 unread messages'), findsOneWidget);
    await tester.pumpWidget(_host(300));
    expect(find.bySemanticsLabel('99+ unread messages'), findsOneWidget);
    handle.dispose();
  });
}
