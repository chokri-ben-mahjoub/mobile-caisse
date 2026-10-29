import 'package:flutter/material.dart';

/// One selectable main colour of the app: a deep, a main and a light shade.
@immutable
class AppAccent {
  const AppAccent(this.key, this.label, this.deep, this.main, this.light);
  final String key;
  final String label;
  final Color deep;
  final Color main;
  final Color light;

  static const blue = AppAccent('blue', 'Bleu', Color(0xFF1E3A8A), Color(0xFF2563EB), Color(0xFF3B82F6));
  static const violet = AppAccent('violet', 'Violet', Color(0xFF4C1D95), Color(0xFF7C3AED), Color(0xFF8B5CF6));
  static const green = AppAccent('green', 'Vert', Color(0xFF065F46), Color(0xFF059669), Color(0xFF10B981));
  static const orange = AppAccent('orange', 'Orange', Color(0xFF9A3412), Color(0xFFEA580C), Color(0xFFF97316));
  static const red = AppAccent('red', 'Rouge', Color(0xFF991B1B), Color(0xFFDC2626), Color(0xFFEF4444));
  static const teal = AppAccent('teal', 'Turquoise', Color(0xFF115E59), Color(0xFF0D9488), Color(0xFF14B8A6));
  static const pink = AppAccent('pink', 'Rose', Color(0xFF9D174D), Color(0xFFDB2777), Color(0xFFEC4899));
  static const slate = AppAccent('slate', 'Ardoise', Color(0xFF1E293B), Color(0xFF334155), Color(0xFF475569));

  static const all = [blue, violet, green, orange, red, teal, pink, slate];

  /// Colour in use; set when the settings load or change, read by [kBlue] and [kHeroGradient].
  static AppAccent current = blue;

  static AppAccent byKey(String key) => all.firstWhere((a) => a.key == key, orElse: () => blue);
}

/// Main colour of the app (blue by default, see [AppAccent]).
Color get kBlue => AppAccent.current.main;

LinearGradient get kHeroGradient => LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [AppAccent.current.deep, AppAccent.current.main, AppAccent.current.light],
    );

/// Soft coloured shadow under accent-coloured surfaces.
List<BoxShadow> accentShadow({double blur = 24, double dy = 10, double alpha = 0.33}) =>
    [BoxShadow(color: AppAccent.current.main.withValues(alpha: alpha), blurRadius: blur, offset: Offset(0, dy))];

/// App colours that differ between the light and dark themes.
@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.bg,
    required this.card,
    required this.ink,
    required this.muted,
    required this.soft,
    required this.soft2,
    required this.border,
    required this.accent,
    required this.goodBg,
    required this.goodFg,
    required this.badBg,
    required this.badFg,
    required this.shadow,
  });

  final Color bg; // page background
  final Color card; // cards, sheets, inputs
  final Color ink; // main text
  final Color muted; // secondary text
  final Color soft; // tinted blue (avatars, nav indicator)
  final Color soft2; // lighter tint (stepper pill, neutral panels)
  final Color border;
  final Color accent; // blue text / icons on cards
  final Color goodBg, goodFg, badBg, badFg;
  final List<BoxShadow> shadow;

  static const light = AppPalette(
    bg: Color(0xFFF1F5FB),
    card: Colors.white,
    ink: Color(0xFF0F172A),
    muted: Color(0xFF64748B),
    soft: Color(0xFFDBE7FE),
    soft2: Color(0xFFEEF3FC),
    border: Color(0xFFD5DEF0),
    accent: Color(0xFF1E40AF),
    goodBg: Color(0xFFDCFCE7),
    goodFg: Color(0xFF15803D),
    badBg: Color(0xFFFEE2E2),
    badFg: Color(0xFFB91C1C),
    shadow: [BoxShadow(color: Color(0x141E3A8A), blurRadius: 18, offset: Offset(0, 6))],
  );

  static const dark = AppPalette(
    bg: Color(0xFF0B1220),
    card: Color(0xFF151E31),
    ink: Color(0xFFE6EBF5),
    muted: Color(0xFF94A3B8),
    soft: Color(0xFF1F2E54),
    soft2: Color(0xFF1B2640),
    border: Color(0xFF2A3753),
    accent: Color(0xFF9DB8FF),
    goodBg: Color(0xFF0F2E1C),
    goodFg: Color(0xFF4ADE80),
    badBg: Color(0xFF3A1417),
    badFg: Color(0xFFF87171),
    shadow: [BoxShadow(color: Color(0x66000000), blurRadius: 16, offset: Offset(0, 6))],
  );

  @override
  AppPalette copyWith() => this;

  @override
  AppPalette lerp(AppPalette? other, double t) => t < 0.5 ? this : (other ?? this);
}

extension PaletteX on BuildContext {
  AppPalette get pal => Theme.of(this).extension<AppPalette>()!;
}

/// The palette tinted with the current accent colour (the blue default keeps the original look).
AppPalette _tinted(AppPalette base, bool dark) {
  final a = AppAccent.current;
  if (a.key == AppAccent.blue.key) return base;
  Color mix(Color c, Color t, double k) => Color.lerp(c, t, k)!;
  return AppPalette(
    bg: mix(base.bg, a.main, dark ? 0.03 : 0.035),
    card: base.card,
    ink: base.ink,
    muted: base.muted,
    soft: dark ? mix(base.card, a.main, 0.30) : mix(Colors.white, a.main, 0.17),
    soft2: dark ? mix(base.card, a.main, 0.14) : mix(Colors.white, a.main, 0.07),
    border: mix(base.border, a.main, dark ? 0.12 : 0.10),
    accent: dark ? mix(a.light, Colors.white, 0.35) : a.deep,
    goodBg: base.goodBg,
    goodFg: base.goodFg,
    badBg: base.badBg,
    badFg: base.badFg,
    shadow: dark ? base.shadow : [BoxShadow(color: a.deep.withValues(alpha: 0.08), blurRadius: 18, offset: const Offset(0, 6))],
  );
}

ThemeData buildTheme([Brightness brightness = Brightness.light, bool arabic = false]) {
  final dark = brightness == Brightness.dark;
  final p = _tinted(dark ? AppPalette.dark : AppPalette.light, dark);
  final primary = dark ? AppAccent.current.light : kBlue;
  final scheme = ColorScheme.fromSeed(
    seedColor: kBlue,
    brightness: brightness,
    primary: primary,
    onPrimary: Colors.white,
    surface: p.card,
    onSurface: p.ink,
  );
  OutlineInputBorder border(Color c, [double w = 1]) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: c, width: w),
      );
  final base = dark ? ThemeData.dark() : ThemeData.light();

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    fontFamily: arabic ? 'Tajawal' : null,
    colorScheme: scheme,
    scaffoldBackgroundColor: p.bg,
    canvasColor: p.card,
    extensions: [p],
    splashFactory: InkSparkle.splashFactory,
    textTheme: base.textTheme.apply(bodyColor: p.ink, displayColor: p.ink, fontFamily: arabic ? 'Tajawal' : null),
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: p.ink, letterSpacing: -0.5),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(60),
        textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(54),
        foregroundColor: dark ? p.accent : kBlue,
        side: BorderSide(color: p.border, width: 1.5),
        backgroundColor: p.card,
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: dark ? p.accent : kBlue,
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: p.card,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: border(p.border),
      enabledBorder: border(p.border),
      focusedBorder: border(primary, 2),
      errorBorder: border(const Color(0xFFDC2626)),
      focusedErrorBorder: border(const Color(0xFFDC2626), 2),
    ),
    cardTheme: CardThemeData(
      color: p.card,
      elevation: dark ? 0 : 2.5,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: dark ? BorderSide(color: p.border) : BorderSide.none,
      ),
      shadowColor: const Color(0x331E3A8A),
      surfaceTintColor: Colors.transparent,
    ),
    listTileTheme: ListTileThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: p.card,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: p.card,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: dark ? const Color(0xFF2A3753) : const Color(0xFF0F172A),
      contentTextStyle: const TextStyle(color: Colors.white),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: p.card,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: p.card,
      side: BorderSide(color: p.border),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      labelStyle: TextStyle(fontWeight: FontWeight.w700, color: p.ink),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        minimumSize: const WidgetStatePropertyAll(Size.fromHeight(52)),
        side: WidgetStatePropertyAll(BorderSide(color: p.border)),
        textStyle: const WidgetStatePropertyAll(TextStyle(fontWeight: FontWeight.w800)),
        backgroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? primary : p.card),
        foregroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Colors.white : p.ink),
        shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Colors.white : p.muted),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? primary : p.soft2),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: primary,
      foregroundColor: Colors.white,
      extendedTextStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
    dividerTheme: DividerThemeData(color: p.border),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: p.card,
      surfaceTintColor: Colors.transparent,
      elevation: dark ? 0 : 12,
      shadowColor: const Color(0x331E3A8A),
      height: 72,
      indicatorColor: p.soft,
      indicatorShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      labelTextStyle: WidgetStateProperty.resolveWith((s) => TextStyle(
            fontSize: 12,
            fontWeight: s.contains(WidgetState.selected) ? FontWeight.w800 : FontWeight.w600,
            color: s.contains(WidgetState.selected) ? p.accent : p.muted,
          )),
      iconTheme: WidgetStateProperty.resolveWith(
          (s) => IconThemeData(size: 26, color: s.contains(WidgetState.selected) ? p.accent : p.muted)),
    ),
  );
}
