import 'dart:async';
import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

/// Thrown when a row expected to already exist (e.g. the caller's own
/// profile) isn't visible yet — typically a brief provisioning race right
/// after sign-up/sign-in, before a DB trigger has committed the row, rather
/// than a real "not found". See [FriendlyError.parse]'s dedicated case.
class ProfileNotProvisionedException implements Exception {
  @override
  String toString() => 'ProfileNotProvisionedException';
}

/// Centralised utility that parses raw exceptions into friendly,
/// human-readable error messages.
class FriendlyError {
  static String parse(Object error) {
    if (error is ProfileNotProvisionedException) {
      return "We're still setting up your profile. Please try again in a moment.";
    }
    return _socket(error) ??
        _timeout(error) ??
        _format(error) ??
        _flutterErr(error) ??
        _platform(error) ??
        _auth(error) ??
        _postgrest(error) ??
        _exception(error) ??
        _argError(error) ??
        _stateError(error) ??
        'An unexpected error occurred. Please try again later.';
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  Shared matching helper
  // ─────────────────────────────────────────────────────────────────────────

  /// Returns [msg] when [candidates] has at least one substring match against
  /// any non-null entry in [searchIn]; otherwise `null`.
  ///
  /// [searchIn] is typed as `List<Object?>` so nullable fields (e.g.
  /// `PostgrestException.code`) can be passed directly without a pre-check.
  static String? _matchAny(
    List<Object?> searchIn,
    List<String> candidates,
    String msg,
  ) =>
      searchIn.any((v) => v is String && candidates.any(v.contains)) ? msg : null;

  // ─────────────────────────────────────────────────────────────────────────
  //  1. SocketException
  // ─────────────────────────────────────────────────────────────────────────

  static String? _socket(Object error) {
    if (error is! SocketException) return null;
    final m = error.message;

    return _matchAny([m], ['refused', 'reset by peer', 'could not be made'],
            'A seamless connection to our servers could not be made. This could be a temporary issue — please try again.')

        ?? _matchAny([m], ['Bad hostname', 'Bad host', 'unresolved', 'Lookup failed'],
            'Could not reach the server. The address may be incorrect or the server may be offline.')

        ?? _matchAny([m], ['Network is unreachable', 'No route to host'],
            'Network issue: make sure you are connected to the internet.')

        ?? 'A network connection issue occurred. Please check your internet connection and try again.';
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  2. TimeoutException
  // ─────────────────────────────────────────────────────────────────────────

  static String? _timeout(Object error) {
    if (error is! TimeoutException) return null;
    return 'The request took too long to complete. We may be experiencing heavy load — please try again in a moment.';
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  3. FormatException
  // ─────────────────────────────────────────────────────────────────────────

  static String? _format(Object error) {
    if (error is! FormatException) return null;
    return 'The data received from the server was malformed. This may indicate an outdated app version — please update.';
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  4. FlutterError
  // ─────────────────────────────────────────────────────────────────────────

  static String? _flutterErr(Object error) {
    if (error is! FlutterError) return null;
    return 'Something unexpected happened in the app. If the problem persists, please let us know.';
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  5. PlatformException
  // ─────────────────────────────────────────────────────────────────────────

  static String? _platform(Object error) {
    if (error is! PlatformException) return null;
    final c = error.code;

    // ── Photo / gallery ───────────────────────────────────────────────────
    if (_matchAny([c], ['photo_access_denied', 'photo_permission_denied',
            'photo_access_restricted', 'photo_permission_restricted', 'PHPhotoLibrary_addOnly'],
        'Could not access your photo gallery. Please grant photo library access in your device settings.')
        case final String r?) return r;

    // ── Camera ────────────────────────────────────────────────────────────
    if (_matchAny(
          [c],
          ['camera_access_denied', 'camera_permission_denied', 'camera_access_restricted', 'camera_permission_restricted'],
          'Could not access your camera. Please grant camera access in your device settings.',
        ) case final String r?)
      return r;

    // ── Location ───────────────────────────────────────────────────────────
    if (_matchAny(
          [c],
          ['location_access_denied', 'location_permission_denied', 'location_permission_restricted'],
          'Could not access your location. Please grant location permission in your device settings.',
        ) case final String r?)
      return r;

    // ── Microphone ─────────────────────────────────────────────────────────
    if (_matchAny(
          [c],
          ['microphone_access_denied', 'microphone_permission_denied', 'microphone_permission_restricted'],
          'Could not access your microphone. Please grant microphone permission in your device settings.',
        ) case final String r?)
      return r;

    // ── Phone / Calls ──────────────────────────────────────────────────────
    if (_matchAny(
          [c],
          ['call_phone', 'phone_access_denied', 'CALL_PHONE'],
          'Could not make phone calls. Please grant phone permissions in your device settings.',
        ) case final String r?)
      return r;

    // ── Contacts ───────────────────────────────────────────────────────────
    if (_matchAny(
          [c],
          ['contacts_access_denied', 'contacts_permission_denied', 'READ_CONTACTS', 'WRITE_CONTACTS'],
          'Could not access your contacts. Please grant contacts access in your device settings.',
        ) case final String r?)
      return r;

    // ── Notifications ──────────────────────────────────────────────────────
    if (_matchAny(
          [c],
          ['notification_access_denied', 'notification_permission_denied', 'UNAUTHORIZED'],
          'Notifications are currently disabled. Please enable them in your notification settings to stay updated.')
        case final String r?)
      return r;

    // ── Storage / Disk space ────────────────────────────────────────────────
    if (_matchAny(
          [c],
          ['OVERQUOTA_BUDGET', 'QUOTA_EXCEEDED', 'storage_full', 'No space left', 'storage_exception'],
          'Storage is full or a disk-quota was exceeded. Please free up space and try again.')
        case final String r?)
      return r;

    if (error.message case final String msg?) return msg;
    return 'A hardware permission error occurred.';
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  6. Supabase AuthException
  // ─────────────────────────────────────────────────────────────────────────

  static String? _auth(Object error) {
    if (error is! AuthException) return null;
    final m = error.message;

    if (_matchAny([m], ['Invalid login credentials', 'invalid_credentials', 'Invalid email or password'],
            'Incorrect email or password. Please try again.')
        case final String r?) return r;

    if (_matchAny([m], ['Email not confirmed', 'email_not_confirmed', 'Email not verified'],
            'Please verify your email address before signing in.')
        case final String r?) return r;

    if (_matchAny([m], ['User already exists', 'user_already_exists'],
            'An account with this email address already exists.')
        case final String r?) return r;

    if (_matchAny([m], ['Password is too short', 'password_too_short'],
            'The password provided is too short. It must be at least 6 characters.')
        case final String r?) return r;

    if (_matchAny([m], ['Token has expired or is invalid', 'otp_expired', 'Token has expired'],
            'That code is incorrect or has expired. Please check it or request a new one.')
        case final String r?) return r;

    if (_matchAny([m], ['Invalid'], 'Your credentials were rejected. Please try again.')
        case final String r?) return r;

    if (_matchAny([m], ['Unable to validate email: invalid format'],
            'The email address format is not valid.')
        case final String r?) return r;

    if (_matchAny([m], ['MFA is required', 'mfa_required', 'reauthentication_failed', 'reauthentication_auth_failed', 'Totp verification failed', 'Multi-factor authentication failed', 'factor_not_enrolled', 'UsesMfa'],
            'Additional verification is required. Please complete multi-factor authentication.')
        case final String r?) return r;

    if (_matchAny([m], ['Too many requests', 'reauthentication_rate_limited', 'slow_down', 'Too many attempts', 'Too much traffic', 'Email rate limit exceeded', 'request_limit_exceeded'],
            'Too many requests were made. Please wait a moment before trying again.')
        case final String r?) return r;

    if (_matchAny([m], ['Provider credentials', 'provider_credential', 'Identity provider', 'OAuth', 'Unsupported identity provider', 'sign_in_'],
            'Signing in with the external provider failed. Please try again or use another sign-in method.')
        case final String r?) return r;

    if (_matchAny([m], ['refresh_token', 'Refresh Token', 'expired', 'token_expired', 'Session expired', 'Session not found', 'Invalid Refresh Token', 'Access token expired', 'Invalid token', 'expired_token', 'access_token'],
            'Your session has expired. Please sign in again.')
        case final String r?) return r;

    if (_matchAny([m], ['User disabled', 'user_disabled', 'User not found'],
            'This account has been deactivated. Please contact support if this is unexpected.')
        case final String r?) return r;

    if (_matchAny([m], ['saml', 'SSO', 'single sign on'],
            'Single sign-on could not be completed. Please contact your administrator.')
        case final String r?) return r;

    if (_matchAny([m], ['Access Denied', 'access_denied', 'unauthorized', 'forbidden', 'Forbidden resource'],
            'You do not have permission to perform this action.')
        case final String r?) return r;

    if (_matchAny([m], ['Could not find a matching verification code', 'Could not find a matching access token', 'provider_token', 'Authorisation request failed', 'authorization_request'],
            'Something went wrong with the identity provider. Please sign out and try again.')
        case final String r?) return r;

    if (_matchAny([m], ['Unable to execute SQL', 'delivery', 'SMTP'],
            'We were unable to send a verification email. Please try again in a moment.')
        case final String r?) return r;

    if (_rawMsgIfSafe(m) case final String r?) return r;
    return 'The sign-in request could not be completed. Please try again.';
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  7. Supabase PostgrestException
  // ─────────────────────────────────────────────────────────────────────────

  static String? _postgrest(Object error) {
    if (error is! PostgrestException) return null;
    final code = error.code; // String?
    final m = error.message;  // String

    // PGRST116: .single()/.maybeSingle() got zero or >1 rows. The raw
    // message ("Cannot coerce the result to a single JSON object") is short
    // and contains neither "Exception" nor " error", so it would otherwise
    // slip through the Layer 0 passthrough below unmapped.
    if (code == 'PGRST116') {
      return 'The requested record could not be found. Please try again.';
    }

    // Layer 0 — safe raw message passthrough
    if (_rawMsgIfSafe(m) case final String r?) return r;

    // Layer 1 — RLS / authorization
    if (code == '42501' || m.contains('row-level security')) {
      return 'Access denied. You do not have permission to perform this action.';
    }

    // Layer 2 — constraint violations
    if (_constraints(code, m) case final String r?) return r;

    // Layer 3 — data type / validity errors
    if (_dataValidity(code, m) case final String r?) return r;

    // Layer 4 — schema / missing object
    if (_schema(code) case final String r?) return r;

    // Layer 5 — DDL collisions
    if (_ddl(code) case final String r?) return r;

    // Layer 6 — friendly PL/pgSQL trigger messages
    if (_triggerMsg(m) case final String r?) return r;

    return 'A database operation could not be completed. Please try again later.';
  }

  static String? _constraints(String? code, String m) {
    return _matchAny([code, m], ['23505', 'duplicate key value'],
            'This record already exists in our system.')

        ?? _matchAny([code, m], ['23503', 'foreign key constraint'],
            'This item references another record that does not exist or has been deleted.')

        ?? _matchAny([code, m], ['23514', 'check constraint'],
            'The request contains invalid parameters that violate system validation rules.');
  }

  static String? _dataValidity(String? code, String m) {
    return _matchAny(
            [code, m],
            ['22001', 'value too long', 'string data, right-truncated'],
            'One of the submitted values is longer than the maximum allowed length.')

        ?? _matchAny([code, m], ['22P02', 'invalid input syntax', 'invalid text'],
            'One of the submitted values has an invalid format.')

        ?? _matchAny([code, m], ['22003', 'numeric value out of range'],
            'A numeric value in the request is too large or too small.')

        ?? _matchAny([code, m], ['22012', 'division by zero'],
            'A mathematical error occurred while processing the server data.');
  }

  static String? _schema(String? code) =>
      _matchAny(
        [code],
        ['42P01', 'undefined table'],
        'A server configuration error occurred. Our technical team has been notified.',
      );

  static String? _ddl(String? code) =>
      _matchAny(
        [code],
        ['42P07', 'duplicate_table'],
        'A server resource that is required already exists. Please contact support.',
      );

  static String? _triggerMsg(String m) {
    if (m.isEmpty) return null;
    final lower = m.toLowerCase();

    return _matchAny(
            [lower],
            ['Daily limit exceeded', 'Monthly limit exceeded'],
            'You have reached your daily quota. The counter resets at midnight — please try again tomorrow.')

        ?? _matchAny(
          [lower],
          ['Rate limit exceeded', 'Too many requests'],
          'You are making requests too quickly. Please wait a moment before trying again.',
        )

        ?? _matchAny(
          [lower],
          ['locked'],
          'This account has been temporarily locked due to repeated failed attempts. Please try again later.',
        )

        ?? _matchAny(
          [lower],
          ['Insufficient points', 'Insufficient balance', 'Insufficient tokens'],
          'You do not have enough balance for this action. Please top up your account.',
        )

        ?? _matchAny(
          [lower],
          ['Event is full', 'has reached capacity', 'Sold out', 'Capacity exceeded'],
          'This event is full and cannot accept more attendees. Join the waitlist or choose another event.',
        );
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  8. Generic Exception
  // ─────────────────────────────────────────────────────────────────────────

  static String? _exception(Object error) {
    if (error is! Exception) return null;
    final str = error.toString().replaceFirst('Exception: ', '').trim();

    return _matchAny(
            [str],
            ['Connection timed out', 'Failed host lookup', 'ClientException', 'Network is unreachable'],
            'Network connection issue. Please check your internet connection and try again.')

        ?? _matchAny([str], ['SocketException', 'Network connection lost'],
            'Network connection lost. Please check your connection and retry.')

        ?? _matchAny([str], ['HttpException', 'Bad request', 'Bad response'],
            'The server could not process the request. We have been notified and will investigate.')

        ?? _matchAny([str], ['FormatException', 'malformed', 'MalformedInputException'],
            'The data received was malformed. You may need to update the app.')

        ?? _matchAny([str], ['TimeoutException', 'timed out', 'Timed out'],
            'The request took too long. Please try again shortly.')

        ?? _matchAny([str], ['StorageException', 'storage_exception', 'No space left', 'QuotaExceeded'],
            'Storage is full or a disk-quota was exceeded. Please free up space and try again.')

        ?? _matchAny([str], ['NotAllowed', 'not_allowed', 'Operation not permitted', 'OperationNotAllowed'],
            'Access to this resource was denied. You may need to grant the required permissions in Settings.')

        ?? _matchAny([str], ['Unavailable', 'unavailable', 'Service temporarily unavailable'],
            'The requested resource is currently unavailable. Please try again later.')

        ?? _matchAny([str], ['AlreadyExists', 'already_exists', 'already registered'],
            'This record already exists in our system.')

        ?? _matchAny([str], ['Permission denied', 'permission_denied', 'Insufficient permissions'],
            'Permission was denied for this operation.')

        ?? _matchAny([str], ['Canceled', 'canceled', 'Operation was canceled'],
            'The operation was cancelled.');
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  9. ArgumentError
  // ─────────────────────────────────────────────────────────────────────────

  static String? _argError(Object error) {
    if (error is! ArgumentError) return null;
    return 'An internal validation error occurred. If the problem persists, please let us know.';
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  10. StateError
  // ─────────────────────────────────────────────────────────────────────────

  static String? _stateError(Object error) {
    if (error is! StateError) return null;
    return 'The app entered an invalid state. Please restart it or go back to the previous screen.';
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  Private utility
  // ─────────────────────────────────────────────────────────────────────────

  static String? _rawMsgIfSafe(String msg) {
    if (msg.isEmpty) return null;
    if (msg.contains('Exception')) return null;
    if (msg.toLowerCase().contains(' error')) return null;
    if (msg.length >= 120) return null;
    return msg;
  }
}

/// Lets any caught [Object] resolve itself into a friendly error message
/// without an explicit utility call.
extension FriendlyErrorExtension on Object {
  /// Returns a human-friendly message for this error.
  String toFriendlyMessage() => FriendlyError.parse(this);
}
