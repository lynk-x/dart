import 'package:material_ui/material_ui.dart';
import 'package:lynk_core/core.dart';

class DeleteAccountDialog extends StatefulWidget {
  final VoidCallback onDelete;

  const DeleteAccountDialog({super.key, required this.onDelete});

  @override
  State<DeleteAccountDialog> createState() => _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends State<DeleteAccountDialog> {
  final TextEditingController _confirmController = TextEditingController();
  bool _isDeleting = false;

  @override
  void dispose() {
    _confirmController.dispose();
    super.dispose();
  }

  void _onDelete() {
    if (_isDeleting || _confirmController.text != 'DELETE') return;
    setState(() => _isDeleting = true);
    Navigator.pop(context);
    widget.onDelete();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.primaryBackground,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 24),
          SizedBox(width: 10),
          Text('Delete Account?',
              style:
                  TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'This permanently deletes your profile, tickets and event history. This cannot be undone.',
            style: TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 20),
          const Text(
            'Type DELETE to confirm:',
            style: TextStyle(color: Colors.white60, fontSize: 13),
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: _confirmController,
            autofocus: true,
            enabled: !_isDeleting,
            style: const TextStyle(
              color: Colors.white,
              letterSpacing: 2,
              fontWeight: FontWeight.bold,
            ),
            decoration: InputDecoration(
              hintText: 'DELETE',
              hintStyle: const TextStyle(color: Colors.white12),
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.06),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Colors.redAccent, width: 1),
              ),
            ),
            onChanged: (_) => setState(() {}),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _isDeleting ? null : () => Navigator.pop(context),
          child: const Text('Cancel', style: TextStyle(color: Colors.white60)),
        ),
        TextButton(
          onPressed: (_confirmController.text == 'DELETE' && !_isDeleting)
              ? _onDelete
              : null,
          child: Text(
            _isDeleting ? 'Deleting...' : 'Delete Forever',
            style: TextStyle(
              color: (_confirmController.text == 'DELETE' && !_isDeleting)
                  ? Colors.redAccent
                  : Colors.redAccent.withValues(alpha: 0.3),
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }
}
