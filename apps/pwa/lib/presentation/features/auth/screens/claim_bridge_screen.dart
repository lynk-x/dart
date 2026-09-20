import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:lynk_x/presentation/shared/screens/system_error_screen.dart';

/// Landing screen for the "Enter Event Forum" link on the checkout
/// confirmation page. Checkout never establishes a session (it resolves the
/// buyer's identity as an anonymous request), so this screen is reached
/// with no session of its own — the confirmation page instead mints a
/// single-use magic-link token_hash server-side and appends it to the
/// bridge link. This screen exchanges that token for a real session via
/// verifyOtp before forwarding to the forum; if no token is present
/// (returning users navigating here with an existing session already),
/// it forwards immediately. If the token is present but fails to verify
/// (expired/already-consumed — expected for a bookmarked confirmation page
/// or a reopened old email) it re-checks for a session before deciding
/// where to send the visitor: someone who's independently already
/// authenticated (e.g. a separate login, or a prior bridge link on the
/// same device) proceeds straight to the forum; only a genuinely
/// unauthenticated visitor is routed through the login screen.
class ClaimBridgeScreen extends StatefulWidget {
  final String? forumReference;
  final String? tokenHash;

  const ClaimBridgeScreen({super.key, this.forumReference, this.tokenHash});

  @override
  State<ClaimBridgeScreen> createState() => _ClaimBridgeScreenState();
}

class _ClaimBridgeScreenState extends State<ClaimBridgeScreen> {
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _forward());
  }

  Future<void> _forward() async {
    final forumReference = widget.forumReference;
    if (forumReference == null || forumReference.isEmpty) {
      setState(() => _errorMessage = 'This link is missing its event.');
      return;
    }

    final tokenHash = widget.tokenHash;
    final hasSession = Supabase.instance.client.auth.currentSession != null;

    if (tokenHash != null && tokenHash.isNotEmpty && !hasSession) {
      try {
        await Supabase.instance.client.auth.verifyOTP(
          tokenHash: tokenHash,
          type: OtpType.magiclink,
        );
      } catch (e) {
        // Token is single-use and short-lived — expired/already-consumed is
        // expected for a bookmarked confirmation page or a reopened old
        // email, not a dead end. Re-check for a session rather than assume
        // there still isn't one: a failed verifyOTP doesn't mean the user
        // is signed out — they may already hold a valid session from a
        // completely separate login (e.g. they logged into the app
        // directly before ever opening this link, or a previous bridge
        // link on the same device already authenticated them). Only fall
        // back to the login screen if they're genuinely unauthenticated;
        // an already-authenticated visitor should proceed straight to the
        // forum instead of being routed through login redundantly.
        final hasSessionAfterFailure =
            Supabase.instance.client.auth.currentSession != null;
        if (!hasSessionAfterFailure) {
          if (mounted) {
            context
                .go('/auth?next=${Uri.encodeComponent('/forum/$forumReference')}');
          }
          return;
        }
      }
    } else if (!hasSession) {
      // No token at all and no session — same fallback as above.
      if (mounted) {
        context.go('/auth?next=${Uri.encodeComponent('/forum/$forumReference')}');
      }
      return;
    }

    if (!mounted) return;
    context.go('/forum/$forumReference');
  }

  @override
  Widget build(BuildContext context) {
    if (_errorMessage != null) {
      return SystemErrorScreen(
        title: 'Could not open forum',
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
