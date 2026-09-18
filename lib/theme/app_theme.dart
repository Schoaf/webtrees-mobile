import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Colors and text styles taken from the design mockup
/// (claude.ai/artifact/9ZLZFPoS9CWJh5JiBb4mpq), not derivable from a plain
/// Material seed color — kept together so screens/widgets share one source.
class AppColors {
  const AppColors._();

  static const primary = Color(0xFF2F6FB0);
  static const secondary = Color(0xFF5C728A);
  static const background = Color(0xFFF7F6FA);
  static const surface = Color(0xFFFFFFFF);

  static const textPrimary = Color(0xFF1B1B1F);
  static const textSecondary = Color(0xFF49454F);
  static const textTertiary = Color(0xFF79747E);
  static const divider = Color(0xFFE7E0EC);

  static const maleAvatarBg = Color(0xFFDCE9F6);
  static const maleAvatarFg = Color(0xFF17557E);
  static const femaleAvatarBg = Color(0xFFF8E1F0);
  static const femaleAvatarFg = Color(0xFF9A3E86);

  static List<BoxShadow> get cardShadow => [
        const BoxShadow(color: Color(0x24000000), blurRadius: 2, offset: Offset(0, 1)),
        const BoxShadow(color: Color(0x14000000), blurRadius: 3, offset: Offset(0, 1)),
      ];
}

ThemeData buildAppTheme() {
  final textTheme = GoogleFonts.robotoTextTheme();

  final colorScheme = ColorScheme.fromSeed(
    seedColor: AppColors.primary,
    primary: AppColors.primary,
    secondary: AppColors.secondary,
    surface: AppColors.surface,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: AppColors.background,
    textTheme: textTheme.apply(bodyColor: AppColors.textPrimary, displayColor: AppColors.textPrimary),
    appBarTheme: AppBarTheme(
      backgroundColor: AppColors.surface,
      foregroundColor: AppColors.textPrimary,
      elevation: 0,
      scrolledUnderElevation: 0,
      shadowColor: Colors.black.withValues(alpha: 0.14),
      titleTextStyle: GoogleFonts.roboto(fontSize: 22, fontWeight: FontWeight.w500, color: AppColors.textPrimary),
      centerTitle: false,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        minimumSize: const Size.fromHeight(56),
        shape: const StadiumBorder(),
        textStyle: GoogleFonts.roboto(fontSize: 15, fontWeight: FontWeight.w500, letterSpacing: 0.02),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.secondary,
        textStyle: GoogleFonts.roboto(fontSize: 13, fontWeight: FontWeight.w500),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppColors.textTertiary),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppColors.textTertiary),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppColors.primary, width: 2),
      ),
      labelStyle: GoogleFonts.roboto(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.textTertiary),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: AppColors.surface,
      indicatorColor: AppColors.secondary.withValues(alpha: 0.22),
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return GoogleFonts.roboto(
          fontSize: 12,
          fontWeight: selected ? FontWeight.w500 : FontWeight.w400,
          color: selected ? AppColors.primary : AppColors.textSecondary,
        );
      }),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return IconThemeData(color: selected ? AppColors.primary : AppColors.textSecondary);
      }),
    ),
    dividerTheme: const DividerThemeData(color: AppColors.divider, thickness: 1, space: 1),
  );
}
