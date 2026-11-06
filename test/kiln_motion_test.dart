import 'package:better_oqb/src/theme/kiln_motion.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget motionHost({required bool details, bool reduceMotion = false}) {
  return MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: reduceMotion),
      child: Scaffold(
        body: KilnFadeThrough(
          child: Center(
            key: ValueKey(details ? 'details' : 'overview'),
            child: Text(details ? 'Details' : 'Overview'),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('keyed views fade through, then remove outgoing content', (tester) async {
    await tester.pumpWidget(motionHost(details: false));
    await tester.pumpWidget(motionHost(details: true));
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Details'), findsOneWidget);
    expect(find.text('Overview'), findsOneWidget);

    // Leaving content remains visible briefly, but cannot intercept a tap
    // or be announced again by accessibility services.
    final outgoing = find.ancestor(
      of: find.text('Overview'),
      matching: find.byType(IgnorePointer),
    );
    expect(outgoing, findsWidgets);

    await tester.pumpAndSettle();
    expect(find.text('Overview'), findsNothing);
    expect(find.text('Details'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reduce motion disables fade-through duration', (tester) async {
    await tester.pumpWidget(motionHost(details: false, reduceMotion: true));
    final switcher = tester.widget<AnimatedSwitcher>(
      find.descendant(
        of: find.byType(KilnFadeThrough),
        matching: find.byType(AnimatedSwitcher),
      ),
    );
    expect(switcher.duration, Duration.zero);
    expect(switcher.reverseDuration, Duration.zero);

    await tester.pumpWidget(motionHost(details: true, reduceMotion: true));
    await tester.pumpAndSettle();
    expect(find.text('Details'), findsOneWidget);
    expect(find.text('Overview'), findsNothing);
  });
}
