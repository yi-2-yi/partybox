import 'package:material_ui/material_ui.dart';

class PartyColors {
  static const bgDeep = Color(0xFF0A0F1E);
  static const bgSurface = Color(0xFF131B31);
  static const bgCard = Color(0xFF1A2542);
  static const bgElevated = Color(0xFF233054);
  static const border = Color(0xFF2E3D66);

  static const gold = Color(0xFFF5C451);
  static const goldSoft = Color(0x33F5C451);
  static const wolfRed = Color(0xFFE05263);
  static const wolfRedSoft = Color(0x33E05263);
  static const seerCyan = Color(0xFF38BDF8);
  static const witchPurple = Color(0xFFA855F7);
  static const guardGreen = Color(0xFF34D399);
  static const textPrimary = Color(0xFFF3F6FF);
  static const textSecondary = Color(0xFFA4B1D1);
  static const textMuted = Color(0xFF6F7FA3);
}

ThemeData buildPartyTheme() {
  final base = ThemeData.dark(useMaterial3: true);
  return base.copyWith(
    scaffoldBackgroundColor: PartyColors.bgDeep,
    colorScheme: const ColorScheme.dark(
      primary: PartyColors.gold,
      onPrimary: Color(0xFF1A1400),
      secondary: PartyColors.seerCyan,
      onSecondary: Color(0xFF041A24),
      surface: PartyColors.bgSurface,
      onSurface: PartyColors.textPrimary,
      error: PartyColors.wolfRed,
      onError: Colors.white,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: PartyColors.bgDeep,
      foregroundColor: PartyColors.textPrimary,
      elevation: 0,
      centerTitle: false,
    ),
    cardTheme: CardThemeData(
      color: PartyColors.bgCard,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: PartyColors.border, width: 1),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: PartyColors.gold,
        foregroundColor: const Color(0xFF1A1400),
        minimumSize: const Size(0, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: PartyColors.textPrimary,
        side: const BorderSide(color: PartyColors.border),
        minimumSize: const Size(0, 46),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: PartyColors.bgSurface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: PartyColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: PartyColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: PartyColors.gold, width: 1.5),
      ),
      labelStyle: const TextStyle(color: PartyColors.textSecondary),
      hintStyle: const TextStyle(color: PartyColors.textMuted),
    ),
  );
}
