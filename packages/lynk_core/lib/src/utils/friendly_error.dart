import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/services.dart';

/// Centralized utility to parse raw developer exceptions into premium, human-friendly messages.
class FriendlyError {
  /// Resolves any Exception/Object into a polished, human-friendly string.
  static String parse(Object error) {
    final errorStr = error.toString();

    // 1. Network / Connection issues
    if (errorStr.contains('SocketException') ||
        errorStr.contains('ClientException') ||
        errorStr.contains('HttpException') ||
        errorStr.contains('Connection timed out') ||
        errorStr.contains('Network is unreachable') ||
        errorStr.contains('Failed host lookup')) {
      return 'Network connection issue. Please check your internet connection and try again.';
    }

    // 2. Supabase PostgrestException (Database & RLS specific)
    if (error is PostgrestException) {
      final code = error.code;
      final msg = error.message;

      // Handle common Postgres constraint violation or security denial codes
      if (code == '42501' || msg.contains('violates row-level security policy')) {
        return 'Access denied. You do not have permission to perform this action.';
      }
      if (code == '23505' || msg.contains('duplicate key value')) {
        return 'This record already exists in our system.';
      }
      if (code == '23503' || msg.contains('violates foreign key constraint')) {
        return 'This item references another record that does not exist or has been deleted.';
      }
      if (code == '23514' || msg.contains('violates check constraint')) {
        return 'The request contains invalid parameters that violate system validation rules.';
      }
      if (code == '42P01') {
        return 'A server configuration error occurred. Our technical team has been notified.';
      }

      // Check if it is a user-friendly trigger error raised via PL/pgSQL (e.g. 'Daily limit exceeded')
      // Custom raised exceptions are passed in the 'message' parameter
      if (msg.isNotEmpty && !msg.contains('Exception') && !msg.contains('error') && msg.length < 100) {
        return msg;
      }

      return 'A database connection error occurred. Please try again later.';
    }

    // 3. Supabase AuthException
    if (error is AuthException) {
      final msg = error.message;
      if (msg.contains('Invalid login credentials') || msg.contains('invalid_credentials')) {
        return 'Incorrect email or password. Please try again.';
      }
      if (msg.contains('Email not confirmed') || msg.contains('email_not_confirmed')) {
        return 'Please verify your email address before signing in.';
      }
      if (msg.contains('User already exists') || msg.contains('user_already_exists')) {
        return 'An account with this email address already exists.';
      }
      if (msg.contains('Password is too short') || msg.contains('password_too_short')) {
        return 'The password provided is too short. It must be at least 6 characters.';
      }
      return msg;
    }

    // 4. Platform / Hardware Permissions
    if (error is PlatformException) {
      final code = error.code;
      if (code == 'photo_access_denied' || code == 'photo_permission_denied') {
        return 'Could not access photo gallery. Please grant photo library access in your device settings.';
      }
      if (code == 'camera_access_denied' || code == 'camera_permission_denied') {
        return 'Could not access camera. Please grant camera access in your device settings.';
      }
      return error.message ?? 'A hardware permission error occurred.';
    }

    // 5. Standard Exception cleanup
    if (error is Exception) {
      final cleanMsg = errorStr.replaceFirst('Exception: ', '').trim();
      if (cleanMsg.isNotEmpty && cleanMsg.length < 100) {
        return cleanMsg;
      }
    }

    return 'An unexpected error occurred. Please try again later.';
  }
}

/// Extension to easily trigger friendly parsing on any caught exception object.
extension FriendlyErrorExtension on Object {
  String toFriendlyMessage() {
    return FriendlyError.parse(this);
  }
}
