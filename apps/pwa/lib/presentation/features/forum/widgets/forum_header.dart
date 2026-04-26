import 'package:flutter/material.dart';
import 'package:lynk_core/core.dart';

/// The header component for the Forum screen.
///
/// Displays the 'Community Forum' title inside a green [AppColors.primary]
/// container and can toggle into an inline search [TextField].
class ForumHeader extends StatefulWidget {
  /// Callback triggered when the user types in the search field.
  final Function(String)? onSearch;

  /// Callback triggered when the search mode is toggled.
  final VoidCallback? onSearchToggle;

  /// When true, the lock/unlock icon button is shown.
  final bool isOrganizer;

  /// Current read-only state of the forum (true = locked).
  final bool isReadOnly;

  /// Called when the organizer taps the lock/unlock button.
  final VoidCallback? onLockToggle;

  const ForumHeader({
    super.key,
    this.onSearch,
    this.onSearchToggle,
    this.isOrganizer = false,
    this.isReadOnly = false,
    this.onLockToggle,
  });

  @override
  State<ForumHeader> createState() => _ForumHeaderState();
}

class _ForumHeaderState extends State<ForumHeader> {
  bool _isSearching = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 4),
      margin: const EdgeInsets.symmetric(horizontal: 2),
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const SizedBox(width: 8),
          Icon(_isSearching ? Icons.search : Icons.forum, color: Colors.black),
          const SizedBox(width: 8),
          Expanded(
            child: _isSearching
                ? TextField(
                    autofocus: true,
                    cursorColor: Colors.black,
                    style: AppTypography.interTight(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.black,
                    ),
                    onChanged: widget.onSearch,
                    decoration: const InputDecoration(
                      hintText: 'Search community...',
                      hintStyle: TextStyle(color: Colors.black54),
                      border: InputBorder.none,
                      isDense: true,
                    ),
                  )
                : Text(
                    'Community Forum',
                    style: AppTypography.interTight(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.black,
                    ),
                  ),
          ),
          if (widget.isOrganizer)
            IconButton(
              tooltip: widget.isReadOnly ? 'Unlock chat' : 'Lock chat',
              icon: Icon(
                widget.isReadOnly ? Icons.lock_open_rounded : Icons.lock_rounded,
                color: Colors.black,
              ),
              onPressed: widget.onLockToggle,
            ),
          IconButton(
            icon: Icon(
              _isSearching ? Icons.close : Icons.search,
              color: Colors.black,
            ),
            onPressed: () {
              setState(() => _isSearching = !_isSearching);
              widget.onSearchToggle?.call();
            },
          ),
        ],
      ),
    );
  }
}
