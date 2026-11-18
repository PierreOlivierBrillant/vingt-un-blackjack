import 'package:flutter/material.dart';

/// Extra semantic colours that Material's [ColorScheme] has no slot for.
@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.background,
    required this.surface,
    required this.surfaceRaised,
    required this.surfaceSunken,
    required this.border,
    required this.textMuted,
    required this.win,
    required this.loss,
    required this.warning,
    required this.gold,
    required this.yes,
    required this.no,
  });

  final Color background;
  final Color surface;
  final Color surfaceRaised;
  final Color surfaceSunken;
  final Color border;
  final Color textMuted;
  final Color win;
  final Color loss;
  final Color warning;
  final Color gold;
  final Color yes;
  final Color no;

  static const dark = AppPalette(
    background: Color(0xFF0F212E),
    surface: Color(0xFF1A2C38),
    surfaceRaised: Color(0xFF213743),
    surfaceSunken: Color(0xFF071824),
    border: Color(0xFF2F4553),
    textMuted: Color(0xFFB1BAD3),
    win: Color(0xFF00E701),
    loss: Color(0xFFED4163),
    warning: Color(0xFFFFB020),
    gold: Color(0xFFF5C451),
    yes: Color(0xFF27AE60),
    no: Color(0xFFE64800),
  );

  static const light = AppPalette(
    background: Color(0xFFEEF2F6),
    surface: Color(0xFFFFFFFF),
    surfaceRaised: Color(0xFFF6F8FB),
    surfaceSunken: Color(0xFFE1E7EE),
    border: Color(0xFFCBD5E0),
    textMuted: Color(0xFF4F6275),
    win: Color(0xFF008A00),
    loss: Color(0xFFC62245),
    warning: Color(0xFFB86E00),
    gold: Color(0xFF9A6B00),
    yes: Color(0xFF1E8449),
    no: Color(0xFFC0392B),
  );

  @override
  AppPalette copyWith({Color? background, Color? surface}) => AppPalette(
        background: background ?? this.background,
        surface: surface ?? this.surface,
        surfaceRaised: surfaceRaised,
        surfaceSunken: surfaceSunken,
        border: border,
        textMuted: textMuted,
        win: win,
        loss: loss,
        warning: warning,
        gold: gold,
        yes: yes,
        no: no,
      );

  @override
  AppPalette lerp(ThemeExtension<AppPalette>? other, double t) {
    if (other is! AppPalette) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppPalette(
      background: l(background, other.background),
      surface: l(surface, other.surface),
      surfaceRaised: l(surfaceRaised, other.surfaceRaised),
      surfaceSunken: l(surfaceSunken, other.surfaceSunken),
      border: l(border, other.border),
      textMuted: l(textMuted, other.textMuted),
      win: l(win, other.win),
      loss: l(loss, other.loss),
      warning: l(warning, other.warning),
      gold: l(gold, other.gold),
      yes: l(yes, other.yes),
      no: l(no, other.no),
    );
  }
}

extension AppThemeX on BuildContext {
  AppPalette get palette => Theme.of(this).extension<AppPalette>()!;
}

/// Brand colours shared by both themes.
abstract final class BrandColors {
  static const green = Color(0xFF00E701);
  static const greenDeep = Color(0xFF00A800);
  static const blue = Color(0xFF1475E1);
  static const onGreen = Color(0xFF051A05);
}

/// Android's system sans-serif. Named explicitly so painters and button
/// styles (which do not inherit the theme's text theme) use it too.
const kAppFont = 'Roboto';

abstract final class AppTheme {
  static const radius = 12.0;

  static ThemeData dark() => _build(Brightness.dark, AppPalette.dark);
  static ThemeData light() => _build(Brightness.light, AppPalette.light);

  static ThemeData _build(Brightness brightness, AppPalette p) {
    final isDark = brightness == Brightness.dark;
    final onSurface = isDark ? Colors.white : const Color(0xFF0F212E);
    final primary = isDark ? BrandColors.green : BrandColors.greenDeep;
    final scheme = ColorScheme(
      brightness: brightness,
      primary: primary,
      onPrimary: isDark ? BrandColors.onGreen : Colors.white,
      primaryContainer: isDark ? const Color(0xFF0B3D16) : const Color(0xFFCDF5CD),
      onPrimaryContainer: isDark ? BrandColors.green : const Color(0xFF003300),
      secondary: BrandColors.blue,
      onSecondary: Colors.white,
      secondaryContainer: isDark ? const Color(0xFF10325A) : const Color(0xFFD6E6FA),
      onSecondaryContainer: isDark ? const Color(0xFF9CC7F7) : const Color(0xFF0A3463),
      tertiary: p.gold,
      onTertiary: Colors.black,
      error: p.loss,
      onError: Colors.white,
      surface: p.surface,
      onSurface: onSurface,
      onSurfaceVariant: p.textMuted,
      surfaceContainerLowest: p.surfaceSunken,
      surfaceContainerLow: p.background,
      surfaceContainer: p.surface,
      surfaceContainerHigh: p.surfaceRaised,
      surfaceContainerHighest: p.border,
      outline: p.border,
      outlineVariant: p.border.withValues(alpha: 0.6),
      shadow: Colors.black,
      inverseSurface: isDark ? Colors.white : const Color(0xFF0F212E),
      onInverseSurface: isDark ? const Color(0xFF0F212E) : Colors.white,
    );

    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      brightness: brightness,
      visualDensity: VisualDensity.compact,
      fontFamily: kAppFont,
    );
    final text = base.textTheme.apply(bodyColor: onSurface, displayColor: onSurface);
    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius));

    return base.copyWith(
      scaffoldBackgroundColor: p.background,
      extensions: [p],
      textTheme: text.copyWith(
        titleLarge: text.titleLarge?.copyWith(fontWeight: FontWeight.w800),
        titleMedium: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        labelLarge: text.labelLarge?.copyWith(fontWeight: FontWeight.w700),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: p.background,
        foregroundColor: onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: text.titleMedium?.copyWith(fontWeight: FontWeight.w800),
      ),
      cardTheme: CardThemeData(
        color: p.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: shape,
      ),
      dividerTheme: DividerThemeData(color: p.border, thickness: 1, space: 1),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: scheme.onPrimary,
          minimumSize: const Size(64, 48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          textStyle: const TextStyle(fontFamily: kAppFont, fontWeight: FontWeight.w800),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: onSurface,
          minimumSize: const Size(64, 48),
          side: BorderSide(color: p.border),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          textStyle: const TextStyle(fontFamily: kAppFont, fontWeight: FontWeight.w700),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: isDark ? const Color(0xFF9CC7F7) : BrandColors.blue,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: p.surfaceSunken,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: p.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: p.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: primary, width: 2),
        ),
        labelStyle: TextStyle(color: p.textMuted),
        hintStyle: TextStyle(color: p.textMuted.withValues(alpha: 0.7)),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: p.surface,
        indicatorColor: primary.withValues(alpha: 0.18),
        height: 64,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (s) => TextStyle(
            fontFamily: kAppFont,
            fontSize: 11,
            fontWeight: s.contains(WidgetState.selected) ? FontWeight.w800 : FontWeight.w500,
            color: s.contains(WidgetState.selected) ? onSurface : p.textMuted,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (s) => IconThemeData(
            color: s.contains(WidgetState.selected) ? primary : p.textMuted,
          ),
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: p.surfaceRaised,
        selectedColor: primary.withValues(alpha: 0.2),
        side: BorderSide(color: p.border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        labelStyle: TextStyle(fontFamily: kAppFont, color: onSurface, fontWeight: FontWeight.w600),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: onSurface,
        unselectedLabelColor: p.textMuted,
        indicatorColor: primary,
        dividerColor: p.border,
        labelStyle: const TextStyle(fontFamily: kAppFont, fontWeight: FontWeight.w800),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: p.textMuted,
        dense: true,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: p.surfaceRaised,
        contentTextStyle: TextStyle(color: onSurface),
        behavior: SnackBarBehavior.floating,
      ),
      dialogTheme: DialogThemeData(backgroundColor: p.surface, shape: shape),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: p.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          foregroundColor: p.textMuted,
          iconColor: p.textMuted,
          selectedBackgroundColor: primary.withValues(alpha: 0.2),
          selectedForegroundColor: onSurface,
          side: BorderSide(color: p.border),
        ),
      ),
    );
  }
}
