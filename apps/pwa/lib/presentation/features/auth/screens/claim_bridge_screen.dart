import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:lynk_x/presentation/shared/screens/system_error_screen.dart';

/// Landing screen for the "Enter Event Forum" link on the checkout
/// confirmation page. Checkout now signs the buyer into a real, durable
/// account via phone+OTP (see CheckoutView on the web side), so by the time
/// this screen loads the router's own auth gate has already ensured the
/// visitor is signed in — no claim token or anonymous session bootstrap is
/// needed here. This screen only forwards to the forum's route.
class ClaimBridgeScreen extends StatefulWidget {
  final String? forumReference;

  const ClaimBridgeScreen({super.key, this.forumReference});

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
