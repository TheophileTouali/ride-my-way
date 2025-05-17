import 'package:flutter/material.dart';

class AppColors {
  static const Color black = Color(0xFF0A0A0A); // fond noir pur
  static const Color gold = Color(0xFFB78E45); // or prélevé du logo
  static const Color grey = Color(0xFFBDBDBD); // gris utilisé pour les labels
  static const Color texturedBlack = Color(0xFF0A0A0A);
}


class AppTheme {
  static ThemeData lightTheme = ThemeData(
    scaffoldBackgroundColor: AppColors.texturedBlack,
    primaryColor: AppColors.gold,
    fontFamily: 'PlayfairDisplay',

    colorScheme: ColorScheme.fromSwatch().copyWith(
      primary: AppColors.gold,
      secondary: AppColors.grey,
      background: AppColors.black,
    ),

    textTheme: const TextTheme(
      headlineLarge: TextStyle(
        fontSize: 32,
        fontWeight: FontWeight.bold,
        color: Color(0xFFBDBDBD),
        fontFamily: 'PlayfairDisplay',
      ),
      bodyMedium: TextStyle(
        fontSize: 16,
        color: Color(0xFFBDBDBD),
        fontFamily: 'PlayfairDisplay',
      ),
    ),

    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.black,
      foregroundColor: AppColors.gold,
      elevation: 0,
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
      fillColor: Color(0xFFBDBDBD),
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
