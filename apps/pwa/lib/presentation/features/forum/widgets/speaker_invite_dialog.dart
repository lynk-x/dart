import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lynk_x/presentation/shared/utils/app_snackbars.dart';
import '../cubit/forum_audio_stream_cubit.dart';
import '../cubit/forum_cubit.dart';
import '../services/stream_service.dart';

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

/// Video's counterpart to showSpeakerInviteDialog/SpeakerInviteDialog —
/// prompts a member to accept or decline a host's "invite to speak" on
/// the live VIDEO call (ForumVideoStreamService
/// .pendingVideoInviteFromHostName). Calls the service directly rather
/// than a cubit (video has none — see that field's own comment for why
/// the accept/decline logic lives on the singleton service instead of a
/// Bloc).
void showVideoSpeakerInviteDialog(BuildContext context, String fromHostName) {
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => VideoSpeakerInviteDialog(fromHostName: fromHostName, parentContext: context),
  );
}

class VideoSpeakerInviteDialog extends StatefulWidget {
  final String fromHostName;
  final BuildContext parentContext;

  const VideoSpeakerInviteDialog({
    super.key,
    required this.fromHostName,
    required this.parentContext,
  });

  @override
  State<VideoSpeakerInviteDialog> createState() => _VideoSpeakerInviteDialogState();
}

class _VideoSpeakerInviteDialogState extends State<VideoSpeakerInviteDialog> {
  bool _isResponding = false;

  Future<void> _accept() async {
    setState(() => _isResponding = true);
    final viewerUserName = widget.parentContext.mounted
        ? widget.parentContext.read<ForumCubit>().state.userName
        : '';
    final success = await ForumVideoStreamService().acceptVideoSpeakerInvite(
      viewerUserName: viewerUserName,
    );
    if (!mounted) return;
    Navigator.pop(context);
    if (!success && widget.parentContext.mounted) {
      AppSnackBars.showError(widget.parentContext, 'Could not join as a speaker — please try again.');
    }
  }

  void _decline() {
    ForumVideoStreamService().declineVideoSpeakerInvite();
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
