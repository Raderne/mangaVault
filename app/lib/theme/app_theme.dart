import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_dimens.dart';

/// Typography scale from `App design/minimalist_slate/DESIGN.md` (Inter only).
const _textTheme = TextTheme(
  // display-lg: 48/700, lh 56, ls -0.02em
  displayLarge: TextStyle(
    fontSize: 48,
    fontWeight: FontWeight.w700,
    height: 56 / 48,
    letterSpacing: -0.96,
  ),
  // headline-lg: 32/600, lh 40, ls -0.01em
  headlineLarge: TextStyle(
    fontSize: 32,
    fontWeight: FontWeight.w600,
    height: 40 / 32,
    letterSpacing: -0.32,
  ),
  // headline-lg-mobile: 24/600, lh 32
  headlineMedium: TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.w600,
    height: 32 / 24,
  ),
  // title-md: 20/600, lh 28
  titleMedium: TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w600,
    height: 28 / 20,
  ),
  // body-lg: 16/400, lh 24
  bodyLarge: TextStyle(fontSize: 16, fontWeight: FontWeight.w400, height: 24 / 16),
  // body-sm: 14/400, lh 20
  bodyMedium: TextStyle(fontSize: 14, fontWeight: FontWeight.w400, height: 20 / 14),
  // label-caps: 12/600, lh 16, ls 0.05em (apply uppercase at call sites)
  labelSmall: TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w600,
    height: 16 / 12,
    letterSpacing: 0.6,
  ),
);

ThemeData buildAppTheme() {
  const scheme = AppColors.colorScheme;
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    fontFamily: 'Inter',
    textTheme: _textTheme.apply(
      bodyColor: scheme.onSurface,
      displayColor: scheme.onSurface,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      foregroundColor: scheme.onSurface,
      centerTitle: false,
      titleTextStyle: _textTheme.headlineMedium!.copyWith(color: scheme.onSurface),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: scheme.surfaceContainer.withValues(alpha: 0.8),
      indicatorColor: scheme.primaryContainer,
      iconTheme: WidgetStatePropertyAll(IconThemeData(color: scheme.onSurfaceVariant)),
      labelTextStyle: WidgetStatePropertyAll(
        _textTheme.labelSmall!.copyWith(color: scheme.onSurfaceVariant),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: scheme.secondaryContainer,
        foregroundColor: scheme.onSurface,
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        textStyle: _textTheme.bodyMedium!.copyWith(fontWeight: FontWeight.w600),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerLowest,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppDimens.coverRadius),
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppDimens.coverRadius),
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppDimens.coverRadius),
        borderSide: BorderSide(color: scheme.secondary),
      ),
    ),
    dividerTheme: DividerThemeData(color: scheme.outlineVariant.withValues(alpha: 0.5)),
  );
}
