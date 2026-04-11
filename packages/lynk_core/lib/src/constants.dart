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

// ── Web App ──────────────────────────────────────────────────────────────────

/// Base URL for the Lynk-X web application.
///
/// Organizer/advertiser workflows (event creation, ad campaigns, KYC, payouts,
/// analytics) are handled on the web app. The PWA redirects to these URLs
/// via [url_launcher] when users need those features.
const String kWebAppBaseUrl = String.fromEnvironment(
  'WEB_APP_URL',
  defaultValue: 'https://lynk-x.app',
);

/// Known web-app paths the PWA may redirect to.
class WebRoutes {
  WebRoutes._();
  static String get createEvent => '$kWebAppBaseUrl/dashboard/events/new';
  static String get manageEvents => '$kWebAppBaseUrl/dashboard/events';
  static String get adCampaigns => '$kWebAppBaseUrl/dashboard/ads';
  static String get kyc => '$kWebAppBaseUrl/dashboard/settings/verification';
  static String get payouts => '$kWebAppBaseUrl/dashboard/payouts';
  static String get organizerDashboard => '$kWebAppBaseUrl/dashboard';
}
