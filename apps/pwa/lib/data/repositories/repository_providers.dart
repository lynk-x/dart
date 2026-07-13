import 'package:supabase_flutter/supabase_flutter.dart';
import 'repositories.dart';
import 'package:lynk_core/profiles/data/repositories/profile_repository.dart';

/// Lazily-initialized singletons. The SupabaseClient is resolved at call-time
/// so this file is safe to import before Supabase.initialize() completes.
SupabaseClient get _db => Supabase.instance.client;

EventRepository get eventRepository => EventRepository(_db);
ForumRepository get forumRepository => ForumRepository(_db);
KycRepository get kycRepository => KycRepository(_db);
NotificationRepository get notificationRepository => NotificationRepository(_db);
WalletRepository get walletRepository => WalletRepository(_db);
TicketRepository get ticketRepository => TicketRepository(_db);
QuizRepository get quizRepository => QuizRepository(_db);
ProfileRepository get profileRepository => ProfileRepository(_db);
SupportRepository get supportRepository => SupportRepository(client: _db);
