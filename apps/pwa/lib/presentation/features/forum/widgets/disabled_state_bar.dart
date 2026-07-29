import 'package:flutter/material.dart';
import 'package:lynk_core/core.dart';

enum DisabledForumState {
  muted,
  readOnly,
  archived,
}

class DisabledStateBar extends StatelessWidget {
  final DisabledForumState state;

  const DisabledStateBar({
    super.key,
    required this.state,
  });

  @override
  Widget build(BuildContext context) {
    final IconData icon;
    final Color color;
    final String text;

    switch (state) {
      case DisabledForumState.muted:
        icon = Icons.mic_off_rounded;
        color = Colors.redAccent;
        text = 'You have been muted in this forum';
        break;
      case DisabledForumState.readOnly:
        icon = Icons.lock_outline_rounded;
        color = Colors.white38;
        text = 'This forum is in read-only mode';
        break;
      case DisabledForumState.archived:
        icon = Icons.archive_outlined;
        color = Colors.white38;
        text = 'This forum has been archived';
        break;
    }

    return Container(
      padding: const EdgeInsets.all(16),
      width: double.infinity,
      decoration: const BoxDecoration(
        color: Colors.black26,
        border: Border(top: BorderSide(color: Colors.white10)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 8),
          Text(
            text,
            style: AppTypography.inter(fontSize: 13, color: color),
          ),
        ],
      ),
    );
  }
}
