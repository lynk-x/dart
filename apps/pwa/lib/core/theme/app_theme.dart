import 'package:flutter/material.dart';
import 'package:lynk_core/core.dart';

class AppTheme {
  static ThemeData get darkTheme {
    return ThemeData(
      brightness: Brightness.dark,
      primaryColor: const Color(0xFF20F928),
      scaffoldBackgroundColor: Colors.black,
      useMaterial3: true,
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: AppColors.tertiary,
        contentTextStyle: TextStyle(color: Colors.white),
      ),
      // Add more theme configurations here as needed
    );
  }
}
