import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:lynk_x/data/repositories/repository_providers.dart';
import 'package:lynk_x/presentation/shared/screens/system_error_screen.dart';

/// Landing screen for the signed claim-link sent on the checkout confirmation
/// page ("Enter Event Forum"). Attaches the order's tickets to whatever
/// session is active in the PWA (bootstrapping an anonymous one if there is
/// none yet) via `api.claim_order`, then forwards into the event's forum.
///
/// This is the primary, zero-friction path for a guest checkout's tickets to
/// end up attached to a real PWA session — no phone number or OTP involved.
/// Phone-OTP recovery is a separate flow for guests who lose this link.
class ClaimBridgeScreen extends StatefulWidget {
  final String? claimToken;

  const ClaimBridgeScreen({super.key, required this.claimToken});

  @override
  State<ClaimBridgeScreen> createState() => _ClaimBridgeScreenState();
}

class _ClaimBridgeScreenState extends State<ClaimBridgeScreen> {
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _claim());
  }

  Future<void> _claim() async {
    final raw = widget.claimToken;
    if (raw == null || raw.isEmpty) {
      setState(() => _errorMessage = 'This link is missing its claim code.');
      return;
    }

    final tokens =
        raw.split(',').where((t) => t.trim().isNotEmpty).toList();

    try {
      if (Supabase.instance.client.auth.currentUser == null) {
        await Supabase.instance.client.auth.signInAnonymously();
      }

      String? claimedEventId;
      var anyAlreadyClaimed = false;

      for (final token in tokens) {
        final result = await Supabase.instance.client
            .schema('api')
            .rpc('claim_order', params: {'p_token': token.trim()});

        final status = (result as Map)['status'] as String?;
        if (status == 'claimed') {
          claimedEventId ??= result['event_id'] as String?;
        } else if (status == 'already_claimed') {
          anyAlreadyClaimed = true;
        }
      }

      if (claimedEventId != null) {
        final segment =
            await forumRepository.getForumRouteSegmentByEventId(claimedEventId);
        if (!mounted) return;
        if (segment != null) {
          context.go('/forum/$segment');
        } else {
          context.go('/');
        }
        return;
      }

      if (anyAlreadyClaimed) {
        setState(() => _errorMessage =
            'These tickets have already been claimed by another account. '
            'If this was you, try recovering your tickets by phone number instead.');
        return;
      }

      setState(() => _errorMessage =
          'This link is invalid or has expired. If you completed a purchase, '
          'try recovering your tickets by phone number instead.');
    } catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = 'Something went wrong while claiming your tickets: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_errorMessage != null) {
      return SystemErrorScreen(
        title: 'Could not claim tickets',
        message: _errorMessage!,
      );
    }

    return const Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: CircularProgressIndicator(color: Colors.white),
      ),
    );
  }
}
