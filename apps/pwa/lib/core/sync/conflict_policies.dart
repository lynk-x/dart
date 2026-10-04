import 'sync_item.dart';

/// Default table-to-policy mapping for offline synchronization conflicts.
///
/// When constructing a [SyncItem] for an UPDATE action, this map is consulted to
/// determine the appropriate [ConflictPolicy]. Explicit values passed to [SyncItem]
/// always take precedence over these defaults.
///
/// ### Policy Rationale
/// - [ConflictPolicy.serverWins]: Entities owned by an organization or third party (events, ticket tiers)
///   where stale offline overwrites would cause data loss.
/// - [ConflictPolicy.clientWins]: Purely local user preferences (notification settings, UI state)
///   where user intent is strictly authoritative.
/// - [ConflictPolicy.manual]: Collaborative or shared records (e.g. forum messages edited concurrently)
///   where conflict resolution requires user confirmation.
const Map<String, ConflictPolicy> kTableConflictPolicies = {
  // ── User-owned preferences (client always wins) ──────────────────────────
  'notification_preferences': ConflictPolicy.clientWins,
  'user_interests':           ConflictPolicy.clientWins,

  // ── User profile (client wins for self-edits; server enforces field rules) ─
  // The user is the sole editor of their own profile, so client intent wins.
  'user_profile':             ConflictPolicy.clientWins,

  // ── Organizer-owned entities (server wins) ────────────────────────────────
  // These are managed by an org with multiple members. If another member
  // saved changes while the client was offline, their version is authoritative.
  'events':                   ConflictPolicy.serverWins,
  'ticket_tiers':             ConflictPolicy.serverWins,
  'ad_campaigns':             ConflictPolicy.serverWins,
  'accounts':                 ConflictPolicy.serverWins,

  // ── Collaborative / append-only (manual resolution) ──────────────────────
  // Forum messages can be edited by both the author and a moderator.
  // Surface the conflict so the author can decide.
  'forum_messages':           ConflictPolicy.manual,

  // ── Default for any table not listed: serverWins (safe fallback) ─────────
};

/// Returns the conflict policy configured for [table], defaulting to [ConflictPolicy.serverWins].
ConflictPolicy conflictPolicyFor(String table) {
  return kTableConflictPolicies[table] ?? ConflictPolicy.serverWins;
}
