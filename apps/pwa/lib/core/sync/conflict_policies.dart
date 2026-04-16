import 'sync_item.dart';

/// Per-entity conflict policy defaults.
///
/// When constructing a [SyncItem] for an UPDATE, look up the table here to
/// get the appropriate [ConflictPolicy]. Explicit values passed to [SyncItem]
/// always take precedence over these defaults.
///
/// Policy rationale:
///   serverWins  — Any entity owned by another party (events, tiers) or where
///                 stale writes could cause data integrity issues.
///   clientWins  — Purely local preferences that only the user can meaningfully
///                 change (notification settings, UI state).
///   manual      — Collaborative entities where both versions have semantic value
///                 and a human should decide (e.g., forum messages edited by
///                 both the author and a moderator simultaneously).
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

/// Returns the conflict policy for [table], falling back to [serverWins].
ConflictPolicy conflictPolicyFor(String table) {
  return kTableConflictPolicies[table] ?? ConflictPolicy.serverWins;
}
