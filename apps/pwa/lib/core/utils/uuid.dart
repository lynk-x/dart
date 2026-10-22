import 'package:uuid/uuid.dart';

/// Client-generated idempotency keys. `SyncItem` generates one per action
/// (UUID v4) and the server dedupes on `(user_id, idempotencyKey)`, so a crash
/// between `addWork` and persist — or a duplicate cubit call — can never queue
/// the same logical action twice. This is the single source of truth for key
/// generation so callers don't reach for `const Uuid().v4()` directly.

String newIdempotencyKey() => const Uuid().v4();