import 'package:flutter/material.dart';

const kBlue = Color(0xFF2563EB);

const kHeroGradient = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [Color(0xFF1E3A8A), Color(0xFF2563EB), Color(0xFF3B82F6)],
);

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

ThemeData buildTheme([Brightness brightness = Brightness.light]) {
  final dark = brightness == Brightness.dark;
  final p = dark ? AppPalette.dark : AppPalette.light;
  final primary = dark ? const Color(0xFF3B82F6) : kBlue;
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
    colorScheme: scheme,
    scaffoldBackgroundColor: p.bg,
    canvasColor: p.card,
    extensions: [p],
    splashFactory: InkSparkle.splashFactory,
    textTheme: base.textTheme.apply(bodyColor: p.ink, displayColor: p.ink),
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
