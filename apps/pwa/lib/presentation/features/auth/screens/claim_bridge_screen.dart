import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:lynk_x/data/repositories/repository_providers.dart';
import 'package:lynk_x/presentation/shared/screens/system_error_screen.dart';

/// Landing screen for the "Enter Event Forum" link on the checkout
/// confirmation page. Checkout now signs the buyer into a real, durable
/// account via phone+OTP (see CheckoutView on the web side), so by the time
/// this screen loads the router's own auth gate has already ensured the
/// visitor is signed in — no claim token or anonymous session bootstrap is
/// needed here. This screen only resolves the event id to its forum route
/// and forwards there.
class ClaimBridgeScreen extends StatefulWidget {
  final String? eventId;
  final String? eventCreatedAt;

  const ClaimBridgeScreen({super.key, required this.eventId, this.eventCreatedAt});

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
    final eventId = widget.eventId;
    if (eventId == null || eventId.isEmpty) {
      setState(() => _errorMessage = 'This link is missing its event.');
      return;
    }

    try {
      final segment = await forumRepository.getForumRouteSegmentByEventId(
        eventId,
        eventCreatedAt: widget.eventCreatedAt,
      );
      if (!mounted) return;
      if (segment != null) {
        context.go('/forum/$segment');
      } else {
        context.go('/');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = 'Something went wrong while opening the forum: $e');
    }
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
