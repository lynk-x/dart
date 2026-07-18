import 'dart:async';
import 'package:flutter/material.dart';
import 'package:lynk_core/core.dart';
import 'package:lynk_x/data/repositories/repositories.dart';

/// A username text field that debounces input and checks (via
/// [TicketRepository.checkUsernameExists]) whether a matching user exists,
/// surfacing a found/not-found indicator and helper text as the user types.
///
/// Shared between the ticket transfer dialog and resale sheet, which
/// previously each hand-rolled an identical debounce/lookup block.
class UsernameLookupField extends StatefulWidget {
  final TicketRepository repository;
  final TextEditingController controller;

  /// If true, an '@' in the input is treated as an email address and skips
  /// the username lookup entirely (used by transfer, which accepts either).
  final bool allowEmail;
  final String hintText;

  /// Called whenever the "found" state changes, so the parent can gate a
  /// submit button on it.
  final ValueChanged<bool?>? onFoundChanged;

  const UsernameLookupField({
    super.key,
    required this.repository,
    required this.controller,
    this.allowEmail = false,
    this.hintText = 'username',
    this.onFoundChanged,
  });

  @override
  State<UsernameLookupField> createState() => _UsernameLookupFieldState();
}

class _UsernameLookupFieldState extends State<UsernameLookupField> {
  Timer? _debounceTimer;
  bool _isChecking = false;
  bool? _recipientFound;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onInputChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onInputChanged);
    _debounceTimer?.cancel();
    super.dispose();
  }

  void _setFound(bool? value) {
    _recipientFound = value;
    widget.onFoundChanged?.call(value);
  }

  void _onInputChanged() {
    final value = widget.controller.text.trim();

    final isEmail = widget.allowEmail && value.contains('@');
    if (value.isEmpty || value.length < 3 || isEmail) {
      _debounceTimer?.cancel();
      if (mounted) setState(() { _setFound(null); _isChecking = false; });
      return;
    }

    if (_debounceTimer?.isActive ?? false) _debounceTimer?.cancel();
    setState(() => _isChecking = true);

    final checkedValue = value;
    _debounceTimer = Timer(const Duration(milliseconds: 500), () async {
      if (!mounted) return;
      try {
        final found = await widget.repository.checkUsernameExists(checkedValue);
        if (mounted && widget.controller.text.trim() == checkedValue) {
          setState(() { _setFound(found); _isChecking = false; });
        }
      } catch (_) {
        if (mounted && widget.controller.text.trim() == checkedValue) {
          setState(() => _isChecking = false);
        }
      }
    });
  }

  Widget? _suffixIcon(BuildContext context) {
    if (_isChecking) {
      return const SizedBox(
        width: 20,
        height: 20,
        child: Padding(
          padding: EdgeInsets.all(12),
          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white24),
        ),
      );
    }
    if (widget.allowEmail && widget.controller.text.contains('@')) return null;
    if (_recipientFound == true) return Icon(Icons.check_circle, color: context.accentColor, size: 20);
    if (_recipientFound == false) return const Icon(Icons.error, color: Colors.redAccent, size: 20);
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final value = widget.controller.text.trim();
    final isEmail = widget.allowEmail && value.contains('@');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: widget.controller,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: widget.hintText,
            hintStyle: const TextStyle(color: Colors.white30),
            filled: true,
            fillColor: Colors.white.withValues(alpha: 0.06),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: context.accentColor, width: 1),
            ),
            suffixIcon: _suffixIcon(context),
          ),
        ),
        if (value.length >= 3 && !isEmail && !_isChecking) ...[
          const SizedBox(height: 6),
          if (_recipientFound == false)
            const Text(
              'No user found with that username.',
              style: TextStyle(color: Colors.redAccent, fontSize: 12),
            )
          else if (_recipientFound == true)
            Text(
              'Recipient found.',
              style: TextStyle(color: context.accentColor.withValues(alpha: 0.8), fontSize: 12),
            ),
        ],
      ],
    );
  }
}
