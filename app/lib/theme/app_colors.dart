import 'package:flutter/material.dart';

/// Minimalist Slate color tokens, verbatim from
/// `App design/minimalist_slate/DESIGN.md`. Token names there are Material 3
/// color roles, so they map 1:1 onto [ColorScheme].
abstract final class AppColors {
  static const surface = Color(0xFF111415);
  static const surfaceDim = Color(0xFF111415);
  static const surfaceBright = Color(0xFF37393B);
  static const surfaceContainerLowest = Color(0xFF0C0F10);
  static const surfaceContainerLow = Color(0xFF191C1E);
  static const surfaceContainer = Color(0xFF1D2022);
  static const surfaceContainerHigh = Color(0xFF282A2C);
  static const surfaceContainerHighest = Color(0xFF323537);
  static const onSurface = Color(0xFFE1E2E4);
  static const onSurfaceVariant = Color(0xFFC7C6CD);
  static const inverseSurface = Color(0xFFE1E2E4);
  static const inverseOnSurface = Color(0xFF2E3132);
  static const outline = Color(0xFF909097);
  static const outlineVariant = Color(0xFF46464C);
  static const surfaceTint = Color(0xFFC2C5DB);
  static const primary = Color(0xFFC2C5DB);
  static const onPrimary = Color(0xFF2C3040);
  static const primaryContainer = Color(0xFF1A1E2E);
  static const onPrimaryContainer = Color(0xFF828599);
  static const inversePrimary = Color(0xFF5A5D70);
  static const secondary = Color(0xFFC2C1FF);
  static const onSecondary = Color(0xFF1800A7);
  static const secondaryContainer = Color(0xFF3630BF);
  static const onSecondaryContainer = Color(0xFFB1B1FF);
  static const tertiary = Color(0xFFC2C1FF);
  static const onTertiary = Color(0xFF272475);
  static const tertiaryContainer = Color(0xFF140D64);
  static const onTertiaryContainer = Color(0xFF7F7ED2);
  static const error = Color(0xFFFFB4AB);
  static const onError = Color(0xFF690005);
  static const errorContainer = Color(0xFF93000A);
  static const onErrorContainer = Color(0xFFFFDAD6);
  static const primaryFixed = Color(0xFFDEE1F8);
  static const primaryFixedDim = Color(0xFFC2C5DB);
  static const onPrimaryFixed = Color(0xFF171B2B);
  static const onPrimaryFixedVariant = Color(0xFF424658);
  static const secondaryFixed = Color(0xFFE2DFFF);
  static const secondaryFixedDim = Color(0xFFC2C1FF);
  static const onSecondaryFixed = Color(0xFF0C006B);
  static const onSecondaryFixedVariant = Color(0xFF332DBC);
  static const tertiaryFixed = Color(0xFFE2DFFF);
  static const tertiaryFixedDim = Color(0xFFC2C1FF);
  static const onTertiaryFixed = Color(0xFF100761);
  static const onTertiaryFixedVariant = Color(0xFF3E3D8C);

  static const colorScheme = ColorScheme(
    brightness: Brightness.dark,
    surface: surface,
    surfaceDim: surfaceDim,
    surfaceBright: surfaceBright,
    surfaceContainerLowest: surfaceContainerLowest,
    surfaceContainerLow: surfaceContainerLow,
    surfaceContainer: surfaceContainer,
    surfaceContainerHigh: surfaceContainerHigh,
    surfaceContainerHighest: surfaceContainerHighest,
    onSurface: onSurface,
    onSurfaceVariant: onSurfaceVariant,
    inverseSurface: inverseSurface,
    onInverseSurface: inverseOnSurface,
    outline: outline,
    outlineVariant: outlineVariant,
    surfaceTint: surfaceTint,
    primary: primary,
    onPrimary: onPrimary,
    primaryContainer: primaryContainer,
    onPrimaryContainer: onPrimaryContainer,
    inversePrimary: inversePrimary,
    secondary: secondary,
    onSecondary: onSecondary,
    secondaryContainer: secondaryContainer,
    onSecondaryContainer: onSecondaryContainer,
    tertiary: tertiary,
    onTertiary: onTertiary,
    tertiaryContainer: tertiaryContainer,
    onTertiaryContainer: onTertiaryContainer,
    error: error,
    onError: onError,
    errorContainer: errorContainer,
    onErrorContainer: onErrorContainer,
    primaryFixed: primaryFixed,
    primaryFixedDim: primaryFixedDim,
    onPrimaryFixed: onPrimaryFixed,
    onPrimaryFixedVariant: onPrimaryFixedVariant,
    secondaryFixed: secondaryFixed,
    secondaryFixedDim: secondaryFixedDim,
    onSecondaryFixed: onSecondaryFixed,
    onSecondaryFixedVariant: onSecondaryFixedVariant,
    tertiaryFixed: tertiaryFixed,
    tertiaryFixedDim: tertiaryFixedDim,
    onTertiaryFixed: onTertiaryFixed,
    onTertiaryFixedVariant: onTertiaryFixedVariant,
  );
}
