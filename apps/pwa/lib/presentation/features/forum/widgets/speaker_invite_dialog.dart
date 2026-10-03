import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lynk_x/presentation/shared/utils/app_snackbars.dart';
import '../cubit/forum_audio_stream_cubit.dart';

/// Prompts a member to accept or decline a host's "invite to speak"
/// (ForumAudioStreamCubit.pendingInviteFromHostName). Mirrors the
/// transfer-ticket dialog's showDialog pattern — no input field needed
/// here, just accept/decline.
void showSpeakerInviteDialog(BuildContext context, String fromHostName) {
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => SpeakerInviteDialog(fromHostName: fromHostName, parentContext: context),
  );
}

class SpeakerInviteDialog extends StatefulWidget {
  final String fromHostName;
  final BuildContext parentContext;

  const SpeakerInviteDialog({
    super.key,
    required this.fromHostName,
    required this.parentContext,
  });

  @override
  State<SpeakerInviteDialog> createState() => _SpeakerInviteDialogState();
}

class _SpeakerInviteDialogState extends State<SpeakerInviteDialog> {
  bool _isResponding = false;

  Future<void> _accept() async {
    setState(() => _isResponding = true);
    final cubit = widget.parentContext.read<ForumAudioStreamCubit>();
    final success = await cubit.acceptSpeakerInvite();
    if (!mounted) return;
    Navigator.pop(context);
    if (!success && widget.parentContext.mounted) {
      AppSnackBars.showError(widget.parentContext, 'Could not join as a speaker — please try again.');
    }
  }

  void _decline() {
    widget.parentContext.read<ForumAudioStreamCubit>().declineSpeakerInvite();
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Invited to Speak'),
      content: Text('${widget.fromHostName} has invited you to speak in this call.'),
      actions: [
        TextButton(
          onPressed: _isResponding ? null : _decline,
          child: const Text('Decline'),
        ),
        FilledButton(
          onPressed: _isResponding ? null : _accept,
          child: _isResponding
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Accept'),
        ),
      ],
    );
  }
}
