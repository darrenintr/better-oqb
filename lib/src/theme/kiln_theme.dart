import 'package:flutter/material.dart';

/// Kiln design tokens (mirrors the Kiln design system's tokens.json).
///
/// Ivory is the light theme, Slate the dark one. Read them with
/// `context.kiln` and `context.kilnText`.
@immutable
class KilnColors extends ThemeExtension<KilnColors> {
  const KilnColors({
    required this.bg,
    required this.surface,
    required this.surfaceRaised,
    required this.oat,
    required this.hairline,
    required this.borderControl,
    required this.ink,
    required this.inkMuted,
    required this.onInk,
    required this.clay,
    required this.onClay,
    required this.clayText,
    required this.olive,
    required this.sky,
    required this.successText,
    required this.dangerText,
    required this.shadowSoft,
  });

  /// Page background. Never pure white or pure black.
  final Color bg;

  /// Cards, side panels and grouped content on [bg].
  final Color surface;

  /// Inputs, answer options, popovers.
  final Color surfaceRaised;

  /// Warm tint for selected rows and tags. Never a text colour.
  final Color oat;

  /// Decorative 1px dividers. Not for control borders.
  final Color hairline;

  /// Borders of inputs and secondary buttons (≥3:1 on bg and surface).
  final Color borderControl;

  /// Primary text, and the fill of primary buttons.
  final Color ink;

  /// Secondary text, captions and metadata.
  final Color inkMuted;

  /// Text and icons on an [ink] fill.
  final Color onInk;

  /// The accent fill, at most once per view.
  final Color clay;

  /// Text and icons on a [clay] fill.
  final Color onClay;

  /// Links, accent text and the focus ring.
  final Color clayText;

  /// Progress and success fills behind a word or icon.
  final Color olive;

  /// Informational fills. Use sparingly.
  final Color sky;

  /// Success text, always with a word or check icon.
  final Color successText;

  /// Error text, always with a word or icon.
  final Color dangerText;

  /// Popovers and dialogs only; cards use [hairline].
  final List<BoxShadow> shadowSoft;

  static const KilnColors light = KilnColors(
    bg: Color(0xFFFAF9F5),
    surface: Color(0xFFF0EEE6),
    surfaceRaised: Color(0xFFFFFFFF),
    oat: Color(0xFFE3DACC),
    hairline: Color(0xFFE2DFD5),
    borderControl: Color(0xFF8A8880),
    ink: Color(0xFF141413),
    inkMuted: Color(0xFF5E5D59),
    onInk: Color(0xFFFAF9F5),
    clay: Color(0xFFD97757),
    onClay: Color(0xFF141413),
    clayText: Color(0xFFA9492A),
    olive: Color(0xFF788C5D),
    sky: Color(0xFF6A9BCC),
    successText: Color(0xFF4F6A35),
    dangerText: Color(0xFF9B3B2C),
    shadowSoft: [
      BoxShadow(color: Color(0x0F141413), offset: Offset(0, 1), blurRadius: 2),
      BoxShadow(color: Color(0x0D141413), offset: Offset(0, 4), blurRadius: 16),
    ],
  );

  static const KilnColors dark = KilnColors(
    bg: Color(0xFF1F1E1D),
    surface: Color(0xFF2A2927),
    surfaceRaised: Color(0xFF33322F),
    oat: Color(0xFF3D3A35),
    hairline: Color(0xFF3A3936),
    borderControl: Color(0xFF7D7B73),
    ink: Color(0xFFF5F4EE),
    inkMuted: Color(0xFFA8A69E),
    onInk: Color(0xFF1F1E1D),
    clay: Color(0xFFD97757),
    onClay: Color(0xFF141413),
    clayText: Color(0xFFE08A6C),
    olive: Color(0xFF8FA36F),
    sky: Color(0xFF7AA8D6),
    successText: Color(0xFFA3B585),
    dangerText: Color(0xFFE5917F),
    shadowSoft: [
      BoxShadow(color: Color(0x4D000000), offset: Offset(0, 1), blurRadius: 2),
      BoxShadow(color: Color(0x40000000), offset: Offset(0, 4), blurRadius: 16),
    ],
  );

  @override
  KilnColors copyWith({
    Color? bg,
    Color? surface,
    Color? surfaceRaised,
    Color? oat,
    Color? hairline,
    Color? borderControl,
    Color? ink,
    Color? inkMuted,
    Color? onInk,
    Color? clay,
    Color? onClay,
    Color? clayText,
    Color? olive,
    Color? sky,
    Color? successText,
    Color? dangerText,
    List<BoxShadow>? shadowSoft,
  }) {
    return KilnColors(
      bg: bg ?? this.bg,
      surface: surface ?? this.surface,
      surfaceRaised: surfaceRaised ?? this.surfaceRaised,
      oat: oat ?? this.oat,
      hairline: hairline ?? this.hairline,
      borderControl: borderControl ?? this.borderControl,
      ink: ink ?? this.ink,
      inkMuted: inkMuted ?? this.inkMuted,
      onInk: onInk ?? this.onInk,
      clay: clay ?? this.clay,
      onClay: onClay ?? this.onClay,
      clayText: clayText ?? this.clayText,
      olive: olive ?? this.olive,
      sky: sky ?? this.sky,
      successText: successText ?? this.successText,
      dangerText: dangerText ?? this.dangerText,
      shadowSoft: shadowSoft ?? this.shadowSoft,
    );
  }

  @override
  KilnColors lerp(KilnColors? other, double t) {
    if (other == null) return this;
    Color c(Color a, Color b) => Color.lerp(a, b, t)!;
    return KilnColors(
      bg: c(bg, other.bg),
      surface: c(surface, other.surface),
      surfaceRaised: c(surfaceRaised, other.surfaceRaised),
      oat: c(oat, other.oat),
      hairline: c(hairline, other.hairline),
      borderControl: c(borderControl, other.borderControl),
      ink: c(ink, other.ink),
      inkMuted: c(inkMuted, other.inkMuted),
      onInk: c(onInk, other.onInk),
      clay: c(clay, other.clay),
      onClay: c(onClay, other.onClay),
      clayText: c(clayText, other.clayText),
      olive: c(olive, other.olive),
      sky: c(sky, other.sky),
      successText: c(successText, other.successText),
      dangerText: c(dangerText, other.dangerText),
      shadowSoft: BoxShadow.lerpList(shadowSoft, other.shadowSoft, t) ?? shadowSoft,
    );
  }
}

/// Bundled font families (variable fonts in assets/fonts, SIL OFL).
abstract final class KilnFonts {
  static const String serif = 'Newsreader';
  static const String sans = 'InstrumentSans';
  static const String mono = 'JetBrainsMono';

  static const List<String> serifFallback = ['Source Serif 4', 'Georgia', 'serif'];
  static const List<String> sansFallback = ['Helvetica Neue', 'Arial', 'sans-serif'];
  static const List<String> monoFallback = ['Menlo', 'monospace'];

  /// Drives the variable `wght` axis. Set it alongside `fontWeight` so the
  /// bundled variable fonts render the weight instead of a synthetic bold.
  static List<FontVariation> weight(FontWeight weight) =>
      [FontVariation('wght', weight.value.toDouble())];
}

/// Kiln type scale: serif to read, sans to act.
@immutable
class KilnText extends ThemeExtension<KilnText> {
  const KilnText({
    required this.display,
    required this.headline,
    required this.title,
    required this.prose,
    required this.label,
    required this.body,
    required this.caption,
    required this.eyebrow,
    required this.code,
  });

  /// One per page: hero numbers and headlines.
  final TextStyle display;

  /// Section openers.
  final TextStyle headline;

  /// Card and dialog titles.
  final TextStyle title;

  /// Question stems, choices and model answers.
  final TextStyle prose;

  /// Buttons, tabs, navigation.
  final TextStyle label;

  /// Interface copy.
  final TextStyle body;

  /// Metadata, in ink-muted.
  final TextStyle caption;

  /// The only uppercase in the system.
  final TextStyle eyebrow;

  /// Working and inline code.
  final TextStyle code;

  factory KilnText.of(KilnColors k) {
    TextStyle serif(double size, double line, FontWeight weight, {double spacing = 0}) => TextStyle(
          fontFamily: KilnFonts.serif,
          fontFamilyFallback: KilnFonts.serifFallback,
          fontSize: size,
          height: line / size,
          fontWeight: weight,
          fontVariations: KilnFonts.weight(weight),
          letterSpacing: spacing * size,
          color: k.ink,
        );
    TextStyle sans(double size, double line, FontWeight weight, {double spacing = 0, Color? color}) => TextStyle(
          fontFamily: KilnFonts.sans,
          fontFamilyFallback: KilnFonts.sansFallback,
          fontSize: size,
          height: line / size,
          fontWeight: weight,
          fontVariations: KilnFonts.weight(weight),
          letterSpacing: spacing * size,
          color: color ?? k.ink,
        );
    return KilnText(
      display: serif(64, 68, FontWeight.w400, spacing: -0.02),
      headline: serif(40, 46, FontWeight.w400, spacing: -0.01),
      title: serif(26, 32, FontWeight.w500),
      prose: serif(18, 29, FontWeight.w400),
      label: sans(15, 20, FontWeight.w500),
      body: sans(15, 23, FontWeight.w400),
      caption: sans(13, 18, FontWeight.w400, color: k.inkMuted),
      eyebrow: sans(12, 16, FontWeight.w500, spacing: 0.08, color: k.inkMuted),
      code: TextStyle(
        fontFamily: KilnFonts.mono,
        fontFamilyFallback: KilnFonts.monoFallback,
        fontSize: 14,
        height: 21 / 14,
        fontWeight: FontWeight.w400,
        fontVariations: KilnFonts.weight(FontWeight.w400),
        color: k.ink,
      ),
    );
  }

  @override
  KilnText copyWith({
    TextStyle? display,
    TextStyle? headline,
    TextStyle? title,
    TextStyle? prose,
    TextStyle? label,
    TextStyle? body,
    TextStyle? caption,
    TextStyle? eyebrow,
    TextStyle? code,
  }) {
    return KilnText(
      display: display ?? this.display,
      headline: headline ?? this.headline,
      title: title ?? this.title,
      prose: prose ?? this.prose,
      label: label ?? this.label,
      body: body ?? this.body,
      caption: caption ?? this.caption,
      eyebrow: eyebrow ?? this.eyebrow,
      code: code ?? this.code,
    );
  }

  @override
  KilnText lerp(KilnText? other, double t) {
    if (other == null) return this;
    TextStyle s(TextStyle a, TextStyle b) => TextStyle.lerp(a, b, t)!;
    return KilnText(
      display: s(display, other.display),
      headline: s(headline, other.headline),
      title: s(title, other.title),
      prose: s(prose, other.prose),
      label: s(label, other.label),
      body: s(body, other.body),
      caption: s(caption, other.caption),
      eyebrow: s(eyebrow, other.eyebrow),
      code: s(code, other.code),
    );
  }
}

extension KilnContext on BuildContext {
  /// Kiln colours; falls back to Ivory when no Kiln theme is installed
  /// (for example in widget tests that use a bare MaterialApp).
  KilnColors get kiln {
    final theme = Theme.of(this);
    return theme.extension<KilnColors>() ??
        (theme.brightness == Brightness.dark ? KilnColors.dark : KilnColors.light);
  }

  KilnText get kilnText => Theme.of(this).extension<KilnText>() ?? KilnText.of(kiln);
}

/// Kiln radii.
abstract final class KilnRadius {
  static const double sm = 6;
  static const double md = 10;
  static const double lg = 16;
}

ThemeData buildKilnTheme(Brightness brightness) {
  final k = brightness == Brightness.dark ? KilnColors.dark : KilnColors.light;
  final text = KilnText.of(k);

  final scheme = ColorScheme(
    brightness: brightness,
    primary: k.ink,
    onPrimary: k.onInk,
    primaryContainer: k.oat,
    onPrimaryContainer: k.ink,
    secondary: k.inkMuted,
    onSecondary: k.onInk,
    secondaryContainer: k.oat,
    onSecondaryContainer: k.ink,
    tertiary: k.sky,
    onTertiary: k.onClay,
    error: k.dangerText,
    onError: k.bg,
    errorContainer: k.surface,
    onErrorContainer: k.dangerText,
    surface: k.bg,
    onSurface: k.ink,
    onSurfaceVariant: k.inkMuted,
    surfaceContainerLowest: k.surfaceRaised,
    surfaceContainerLow: k.surface,
    surfaceContainer: k.surface,
    surfaceContainerHigh: k.surface,
    surfaceContainerHighest: k.oat,
    outline: k.borderControl,
    outlineVariant: k.hairline,
    inverseSurface: k.ink,
    onInverseSurface: k.onInk,
    inversePrimary: k.clay,
    shadow: Colors.black,
    scrim: Colors.black,
    surfaceTint: Colors.transparent,
  );

  final textTheme = TextTheme(
    displayLarge: text.display,
    displayMedium: text.headline,
    displaySmall: text.title.copyWith(fontSize: 32, height: 38 / 32),
    headlineLarge: text.headline,
    headlineMedium: text.title.copyWith(fontSize: 30, height: 36 / 30),
    headlineSmall: text.title,
    titleLarge: text.title.copyWith(fontSize: 22, height: 28 / 22),
    titleMedium: text.label.copyWith(fontSize: 17, height: 24 / 17),
    titleSmall: text.label,
    bodyLarge: text.body.copyWith(fontSize: 16, height: 24 / 16),
    bodyMedium: text.body,
    bodySmall: text.caption,
    labelLarge: text.label,
    labelMedium: text.label.copyWith(fontSize: 13, height: 18 / 13),
    labelSmall: text.caption.copyWith(fontSize: 12, height: 16 / 12),
  );

  final controlShape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(KilnRadius.md));
  const controlSize = Size(44, 44);
  const controlPadding = EdgeInsets.symmetric(horizontal: 20);

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    fontFamily: KilnFonts.sans,
    fontFamilyFallback: KilnFonts.sansFallback,
    textTheme: textTheme,
    scaffoldBackgroundColor: k.bg,
    canvasColor: k.bg,
    dividerColor: k.hairline,
    focusColor: k.clayText.withValues(alpha: 0.16),
    hoverColor: k.ink.withValues(alpha: 0.05),
    splashColor: k.ink.withValues(alpha: 0.08),
    highlightColor: k.ink.withValues(alpha: 0.04),
    visualDensity: VisualDensity.standard,
    materialTapTargetSize: MaterialTapTargetSize.padded,
    extensions: [k, text],
    appBarTheme: AppBarTheme(
      backgroundColor: k.bg,
      foregroundColor: k.ink,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      shape: Border(bottom: BorderSide(color: k.hairline)),
      titleTextStyle: text.title.copyWith(fontSize: 22, height: 28 / 22, fontWeight: FontWeight.w400,
          fontVariations: KilnFonts.weight(FontWeight.w400)),
      iconTheme: IconThemeData(color: k.ink),
      actionsIconTheme: IconThemeData(color: k.ink),
    ),
    cardTheme: CardThemeData(
      color: k.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(KilnRadius.lg),
        side: BorderSide(color: k.hairline),
      ),
    ),
    dividerTheme: DividerThemeData(color: k.hairline, thickness: 1, space: 1),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: k.ink,
        foregroundColor: k.onInk,
        disabledBackgroundColor: k.hairline,
        disabledForegroundColor: k.inkMuted,
        minimumSize: controlSize,
        padding: controlPadding,
        shape: controlShape,
        textStyle: text.label,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: k.ink,
        disabledForegroundColor: k.inkMuted,
        minimumSize: controlSize,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        shape: controlShape,
        side: BorderSide(color: k.borderControl),
        textStyle: text.label,
      ).copyWith(
        side: WidgetStateProperty.resolveWith(
          (states) => BorderSide(color: states.contains(WidgetState.disabled) ? k.hairline : k.borderControl),
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: k.clayText,
        disabledForegroundColor: k.inkMuted,
        minimumSize: controlSize,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        shape: controlShape,
        textStyle: text.label,
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: k.ink,
        disabledForegroundColor: k.borderControl,
        minimumSize: controlSize,
        shape: controlShape,
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: k.surfaceRaised,
      surfaceTintColor: Colors.transparent,
      elevation: 3,
      shadowColor: Colors.black.withValues(alpha: 0.3),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(KilnRadius.md),
        side: BorderSide(color: k.hairline),
      ),
      textStyle: text.body,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: k.surfaceRaised,
      surfaceTintColor: Colors.transparent,
      elevation: 3,
      shadowColor: Colors.black.withValues(alpha: 0.3),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(KilnRadius.lg)),
      titleTextStyle: text.title,
      contentTextStyle: text.body.copyWith(color: k.inkMuted),
      iconColor: k.ink,
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: k.bg,
      surfaceTintColor: Colors.transparent,
      modalBackgroundColor: k.bg,
      dragHandleColor: k.borderControl,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(KilnRadius.lg)),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: k.surface,
      selectedColor: k.oat,
      side: BorderSide.none,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(KilnRadius.sm)),
      labelStyle: text.caption.copyWith(color: k.ink),
      padding: const EdgeInsets.symmetric(horizontal: 4),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: k.olive,
      linearTrackColor: k.hairline,
      circularTrackColor: Colors.transparent,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: k.ink,
      contentTextStyle: text.body.copyWith(color: k.onInk),
      actionTextColor: k.onInk,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(KilnRadius.md)),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(color: k.ink, borderRadius: BorderRadius.circular(KilnRadius.sm)),
      textStyle: text.caption.copyWith(color: k.onInk),
    ),
    badgeTheme: BadgeThemeData(backgroundColor: k.ink, textColor: k.onInk),
    listTileTheme: ListTileThemeData(
      iconColor: k.inkMuted,
      textColor: k.ink,
      titleTextStyle: text.label,
      subtitleTextStyle: text.caption,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: k.surfaceRaised,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(KilnRadius.md),
        borderSide: BorderSide(color: k.borderControl),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(KilnRadius.md),
        borderSide: BorderSide(color: k.borderControl),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(KilnRadius.md),
        borderSide: BorderSide(color: k.clayText, width: 2),
      ),
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: k.ink,
      selectionColor: k.sky.withValues(alpha: 0.35),
      selectionHandleColor: k.clayText,
    ),
  );
}

/// The accent action (clay fill). Use at most once per view.
ButtonStyle kilnAccentButtonStyle(KilnColors k) => FilledButton.styleFrom(
      backgroundColor: k.clay,
      foregroundColor: k.onClay,
      disabledBackgroundColor: k.hairline,
      disabledForegroundColor: k.inkMuted,
    );

/// Small metadata tag: filled (surface) or outlined (hairline).
class KilnTag extends StatelessWidget {
  const KilnTag(this.label, {super.key, this.outlined = false, this.icon});

  final String label;
  final bool outlined;
  final Widget? icon;

  @override
  Widget build(BuildContext context) {
    final k = context.kiln;
    final style = context.kilnText.caption.copyWith(color: outlined ? k.inkMuted : k.ink);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: outlined ? null : k.surface,
        border: outlined ? Border.all(color: k.hairline) : null,
        borderRadius: BorderRadius.circular(KilnRadius.sm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[icon!, const SizedBox(width: 6)],
          Flexible(child: Text(label, style: style, overflow: TextOverflow.ellipsis)),
        ],
      ),
    );
  }
}

/// Status pill: an icon and a word, never colour alone.
class KilnPill extends StatelessWidget {
  const KilnPill({
    super.key,
    required this.icon,
    required this.label,
    this.color,
    this.background,
    this.showLabel = true,
  });

  final IconData icon;
  final String label;

  /// Icon and text colour; defaults to ink.
  final Color? color;

  /// Fill; defaults to surface.
  final Color? background;
  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    final k = context.kiln;
    final fg = color ?? k.ink;
    return Container(
      height: 32,
      padding: EdgeInsets.symmetric(horizontal: showLabel ? 12 : 8),
      decoration: BoxDecoration(
        color: background ?? k.surface,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: fg),
          if (showLabel) ...[
            const SizedBox(width: 6),
            Text(label, style: context.kilnText.label.copyWith(fontSize: 13, height: 18 / 13, color: fg)),
          ],
        ],
      ),
    );
  }
}

/// Inline banner on surface with a hairline: a title, detail and action.
class KilnBanner extends StatelessWidget {
  const KilnBanner({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.action,
    this.danger = false,
    this.margin = EdgeInsets.zero,
  });

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  /// Colours the icon and title with danger-text.
  final bool danger;
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) {
    final k = context.kiln;
    final text = context.kilnText;
    final accent = danger ? k.dangerText : k.ink;
    return Container(
      margin: margin,
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
      decoration: BoxDecoration(
        color: k.surface,
        border: Border.all(color: k.hairline),
        borderRadius: BorderRadius.circular(KilnRadius.lg),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(icon, size: 20, color: accent),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title, style: text.label.copyWith(color: accent)),
                if (message != null && message!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(message!, style: text.caption, maxLines: 3, overflow: TextOverflow.ellipsis),
                ],
              ],
            ),
          ),
          if (action != null) ...[const SizedBox(width: 8), action!],
        ],
      ),
    );
  }
}
