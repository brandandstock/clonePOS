import 'package:flutter/material.dart';

/// Design tokens straight from the master specification (Section 4).
/// Values marked "placeholder" are explicitly not final — see the spec
/// doc's Deferred Items list before treating any of these as locked.
class ClonePosColors {
  static const cream = Color(0xFFF2E8D5); // base canvas
  static const creamCard = Color(0xFFFFFBF2); // card/panel surfaces
  static const mustard = Color(0xFFE8B84B); // metric card fill
  static const rust = Color(0xFFC1551C); // accent / role pill / readouts
  static const walnut = Color(0xFF4A3728); // primary text
  static const orangeButton = Color(0xFFFF7A1A); // PLACEHOLDER — confirm exact hex from Figma FAB component
}

/// Canonical font family for the app — Google Sans Flex.
///
/// Client-locked: **every** Text in the app renders in this family, now
/// and forever. Do not override `fontFamily` in any `TextStyle` — leave
/// it unset and it will inherit from the theme.
///
/// Ships as a single variable-font file under the SIL Open Font License
/// at `assets/fonts/GoogleSansFlex-VariableFont.ttf`, registered in
/// `pubspec.yaml`. Flutter interpolates weight via `TextStyle.fontWeight`
/// from the variable-font's `wght` axis.
const String kClonePosFontFamily = 'Google Sans Flex';

class ClonePosTheme {
  static ThemeData get staffAppTheme {
    return ThemeData(
      useMaterial3: true,
      fontFamily: kClonePosFontFamily,
      scaffoldBackgroundColor: ClonePosColors.cream,
      colorScheme: ColorScheme.fromSeed(
        seedColor: ClonePosColors.rust,
        brightness: Brightness.light,
        surface: ClonePosColors.creamCard,
      ),
      textTheme: const TextTheme(
        headlineMedium: TextStyle(
          fontWeight: FontWeight.bold,
          color: ClonePosColors.walnut,
        ),
        titleMedium: TextStyle(
          fontWeight: FontWeight.w500,
          color: ClonePosColors.walnut,
        ),
        bodyMedium: TextStyle(color: ClonePosColors.walnut),
      ),
    );
  }
}
