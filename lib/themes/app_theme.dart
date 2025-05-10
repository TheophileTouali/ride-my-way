import 'package:flutter/material.dart';

class AppColors {
  static const Color gold = Color(0xFFD4AF37);
  static const Color black = Color(0xFF121212);
  static const Color grey = Color(0xFFF5F5F5);
  static const Color error = Colors.redAccent;
}

class AppTheme {
  static ThemeData lightTheme = ThemeData(
    brightness: Brightness.light,
    scaffoldBackgroundColor: AppColors.grey,
    primaryColor: AppColors.gold,
    colorScheme: ColorScheme.light(
      primary: AppColors.gold,
      secondary: AppColors.black,
      background: AppColors.grey,
      error: AppColors.error,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.black,
      foregroundColor: AppColors.gold,
      elevation: 0,
    ),
    textTheme: const TextTheme(
      headlineLarge: TextStyle(
        fontSize: 32,
        fontWeight: FontWeight.bold,
        color: AppColors.black,
        fontFamily: 'PlayfairDisplay',
      ),
      bodyMedium: TextStyle(
        fontSize: 16,
        color: AppColors.black,
        fontFamily: 'PlayfairDisplay',
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.gold,
        foregroundColor: AppColors.black,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        textStyle: const TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 16,
          fontFamily: 'PlayfairDisplay',
        ),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.gold),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.gold, width: 2),
      ),
      labelStyle: const TextStyle(
        color: AppColors.black,
        fontFamily: 'PlayfairDisplay',
      ),
    ),
  );
}
