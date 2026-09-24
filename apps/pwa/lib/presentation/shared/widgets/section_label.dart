import 'package:flutter/material.dart';
import 'package:lynk_core/core.dart';

/// Small uppercase eyebrow label used above a grouped section in a list
/// (e.g. "LIVE NOW", "NOT STARTED", "FINISHED").
class SectionLabel extends StatelessWidget {
  final String text;
  const SectionLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
      child: Text(
        text.toUpperCase(),
        style: AppTypography.inter(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: Colors.white38,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}
