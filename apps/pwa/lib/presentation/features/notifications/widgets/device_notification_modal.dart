import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lynk_core/core.dart';
import 'package:lynk_x/services/push_notification_service.dart';

class DeviceNotificationModal extends StatelessWidget {
  const DeviceNotificationModal({super.key});

  static Future<void> checkAndShow(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    final hasPrompted = prefs.getBool('has_prompted_notifications_on_device') ?? false;

    if (!hasPrompted && context.mounted) {
      // Small delay to let feed render first
      await Future.delayed(const Duration(seconds: 1));
      if (!context.mounted) return;
      
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => const DeviceNotificationModal(),
      );
    }
  }

  Future<void> _handleAllow(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('has_prompted_notifications_on_device', true);
    
    // Attempt initialization which triggers OS prompt
    await PushNotificationService.instance.init();
    
    if (context.mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _handleNotNow(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('has_prompted_notifications_on_device', true);
    
    if (context.mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF1E1E1E),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 48),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: context.accentColor.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.notifications_active_outlined, 
              size: 48, 
              color: context.accentColor,
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'Never miss out!',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Turn on notifications to get important updates on your upcoming events and ticket purchases.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15,
              color: Colors.white70,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 32),
          PrimaryButton(
            text: 'Allow Notifications',
            onPressed: () => _handleAllow(context),
          ),
          const SizedBox(height: 16),
          TextButton(
            onPressed: () => _handleNotNow(context),
            style: TextButton.styleFrom(
              foregroundColor: Colors.white54,
              textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
            ),
            child: const Text('Not Now'),
          ),
        ],
      ),
    );
  }
}
