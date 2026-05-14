import 'package:flutter/material.dart';
import 'package:lynk_core/core.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../cubit/quiz_builder_cubit.dart';

class QuizSettingsSheet extends StatefulWidget {
  const QuizSettingsSheet({super.key});

  @override
  State<QuizSettingsSheet> createState() => _QuizSettingsSheetState();
}

class _QuizSettingsSheetState extends State<QuizSettingsSheet> {
  late TextEditingController _titleController;
  late TextEditingController _infoController;
  late String _type;

  @override
  void initState() {
    super.initState();
    final draft = context.read<QuizBuilderCubit>().state.draft;
    _titleController = TextEditingController(text: draft.title);
    _infoController = TextEditingController(text: draft.info);
    _type = draft.type;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _infoController.dispose();
    super.dispose();
  }

  void _save() {
    context.read<QuizBuilderCubit>().updateSettings(
          _titleController.text,
          _infoController.text,
          _type,
        );
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        24,
        24,
        24,
        MediaQuery.of(context).viewInsets.bottom + 48,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Settings',
              style: AppTypography.inter(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              )),
          const SizedBox(height: 24),
          TextField(
            controller: _titleController,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              labelText: 'Title',
              labelStyle: const TextStyle(color: Colors.white54),
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.05),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _infoController,
            style: const TextStyle(color: Colors.white),
            maxLines: 3,
            decoration: InputDecoration(
              labelText: 'Description (optional)',
              labelStyle: const TextStyle(color: Colors.white54),
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.05),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text('Type',
              style: AppTypography.inter(fontSize: 14, color: Colors.white54)),
          const SizedBox(height: 8),
          RadioGroup<String>(
            groupValue: _type,
            onChanged: (val) => setState(() => _type = val!),
            child: Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () => setState(() => _type = 'quiz'),
                    child: Row(
                      children: [
                        const Radio<String>(
                          value: 'quiz',
                          activeColor: Colors.deepPurpleAccent, // using a fixed color just to be safe if context.accentColor is an extension
                        ),
                        const Text('Quiz', style: TextStyle(color: Colors.white)),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: InkWell(
                    onTap: () => setState(() => _type = 'poll'),
                    child: Row(
                      children: [
                        const Radio<String>(
                          value: 'poll',
                          activeColor: Colors.deepPurpleAccent,
                        ),
                        const Text('Poll', style: TextStyle(color: Colors.white)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: PrimaryButton(
              text: 'Save Settings',
              onPressed: _save,
            ),
          ),
        ],
      ),
    );
  }
}
