/// App-wide constants used across the presentation layer.
///
/// Centralised here to avoid magic strings scattered across cubits and screens.

library;

// ── Auth ──────────────────────────────────────────────────────────────────────

/// Sentinel user ID used when no authenticated session is present.
///
/// Used throughout the forum and notification cubits to skip operations
/// that require a real user account (analytics, reactions, preferences, etc.).
/// Replace this string check with [isGuestUser] for clarity.
const String kGuestUserId = 'guest_user';

/// Returns `true` if [userId] represents an unauthenticated guest session.
bool isGuestUser(String userId) => userId == kGuestUserId;
