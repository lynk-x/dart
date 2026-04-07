import 'package:flutter/material.dart';
import 'package:lynk_core/core.dart';

class AppTheme {
  static ThemeData get darkTheme {
    return ThemeData(
      brightness: Brightness.dark,
      primaryColor: AppColors.primary,
      scaffoldBackgroundColor: Colors.black,
      useMaterial3: true,
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: AppColors.tertiary,
        contentTextStyle: TextStyle(color: Colors.white),
      ),
    );
  }
}
