import 'package:flutter/material.dart';

/// Shared motion timings for the Kiln UI. Accessibility takes precedence:
/// "Reduce motion" uses immediate state changes rather than entrance movement.
abstract final class KilnMotion {
  static const Duration quick = Duration(milliseconds: 160);
  static const Duration normal = Duration(milliseconds: 260);

  static const Curve enter = Curves.easeOutCubic;
  static const Curve exit = Curves.easeInCubic;

  static Duration duration(BuildContext context, Duration requested) =>
      MediaQuery.maybeOf(context)?.disableAnimations == true
          ? Duration.zero
          : requested;
}

/// Material-style fade-through with a subtle 3% rise. Only *keyed* content
/// changes animate; ordinary controller rebuilds leave the current view intact.
///
/// Outgoing children cannot receive taps or accessibility focus while fading.
/// A bounded parent (Expanded or Positioned.fill) is required.
class KilnFadeThrough extends StatelessWidget {
  const KilnFadeThrough({
    super.key,
    required this.child,
    this.duration = KilnMotion.normal,
  });

  final Widget child;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    final effective = KilnMotion.duration(context, duration);
    return AnimatedSwitcher(
      duration: effective,
      reverseDuration: KilnMotion.duration(context, KilnMotion.quick),
      switchInCurve: KilnMotion.enter,
      switchOutCurve: KilnMotion.exit,
      layoutBuilder: (current, previous) => Stack(
        fit: StackFit.expand,
        children: [
          for (final leaving in previous)
            IgnorePointer(
              child: ExcludeSemantics(child: leaving),
            ),
          if (current != null) current,
        ],
      ),
      transitionBuilder: (content, animation) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.03),
            end: Offset.zero,
          ).animate(animation),
          child: content,
        ),
      ),
      child: child,
    );
  }
}
