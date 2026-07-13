import 'dart:typed_data' show Uint8List;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lynk_core/core.dart';

import '../cubit/kyc_cubit.dart';
import '../cubit/kyc_state.dart';

/// Renders the file/text requirement inputs for one step of the identity
/// verification wizard (text-only "info" step, or file-only "documents"
/// step — see [KycState.textRequirements] / [fileRequirements]).
///
/// Mirrors the web's KycRequirementsForm.tsx: two-sided documents (a
/// national ID front/back) render one labeled dropzone per side instead of
/// a freeform multi-file uploader, and a just-picked image is staged for a
/// readability check before being committed.
class KycRequirementsForm extends StatelessWidget {
  final List<Map<String, dynamic>> requirements;
  final String emptyStateHint;

  const KycRequirementsForm({
    super.key,
    required this.requirements,
    this.emptyStateHint = 'You can proceed to the next step.',
  });

  Future<void> _pickFile(BuildContext context, String reqId, {int? sideIndex}) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png', 'pdf'],
      withData: true,
    );
    final picked = result?.files.single;
    if (picked == null || picked.bytes == null) return;
    if (!context.mounted) return;

    final ext = (picked.extension ?? '').toLowerCase();
    final contentType = switch (ext) {
      'pdf' => 'application/pdf',
      'png' => 'image/png',
      _ => 'image/jpeg',
    };

    context.read<KycCubit>().stageFile(
          reqId: reqId,
          sideIndex: sideIndex,
          file: KycPendingFile(
            bytes: picked.bytes!,
            filename: picked.name,
            contentType: contentType,
          ),
        );
  }

  @override
  Widget build(BuildContext context) {
    if (requirements.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Column(
          children: [
            const Text(
              'No specific verification requirements for your country.',
              style: TextStyle(color: Colors.white70, fontSize: 14),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              emptyStateHint,
              style: const TextStyle(color: Colors.white38, fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return BlocBuilder<KycCubit, KycState>(
      buildWhen: (a, b) => a.files != b.files || a.textValues != b.textValues,
      builder: (context, state) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final req in requirements) ...[
              _RequirementField(
                req: req,
                state: state,
                onPickFile: (sideIndex) => _pickFile(context, req['id'] as String, sideIndex: sideIndex),
              ),
              const SizedBox(height: 20),
            ],
          ],
        );
      },
    );
  }
}

class _RequirementField extends StatelessWidget {
  final Map<String, dynamic> req;
  final KycState state;
  final void Function(int? sideIndex) onPickFile;

  const _RequirementField({required this.req, required this.state, required this.onPickFile});

  @override
  Widget build(BuildContext context) {
    final id = req['id'] as String;
    final label = req['label'] as String? ?? '';
    final mandatory = req['mandatory'] == true;
    final hint = req['hint'] as String?;
    final sides = (req['sides'] as List?)?.cast<String>();
    final type = req['type'] as String? ?? 'file';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(label, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
            if (mandatory) ...[
              const SizedBox(width: 6),
              const Text('*Required', style: TextStyle(color: Colors.amber, fontSize: 11)),
            ],
          ],
        ),
        if (hint != null) ...[
          const SizedBox(height: 4),
          Text(hint, style: const TextStyle(color: Colors.white38, fontSize: 12)),
        ],
        const SizedBox(height: 10),
        if (type == 'text')
          _TextInput(reqId: id, value: state.textValues[id] ?? '', label: label)
        else if (sides != null)
          _SidesUploader(reqId: id, sides: sides, state: state, onPickFile: onPickFile)
        else
          _SingleUploader(reqId: id, state: state, onPick: () => onPickFile(null)),
      ],
    );
  }
}

class _TextInput extends StatelessWidget {
  final String reqId;
  final String value;
  final String label;

  const _TextInput({required this.reqId, required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: TextEditingController(text: value)
        ..selection = TextSelection.collapsed(offset: value.length),
      onChanged: (v) => context.read<KycCubit>().setTextValue(reqId, v),
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        hintText: 'Enter ${label.toLowerCase()}...',
        hintStyle: const TextStyle(color: Colors.white24),
        filled: true,
        fillColor: AppColors.tertiary,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
    );
  }
}

class _SingleUploader extends StatelessWidget {
  final String reqId;
  final KycState state;
  final VoidCallback onPick;

  const _SingleUploader({required this.reqId, required this.state, required this.onPick});

  @override
  Widget build(BuildContext context) {
    final file = (state.files[reqId] ?? const []).isNotEmpty ? state.files[reqId]![0] : null;

    if (file != null) {
      return _FileTile(
        file: file,
        onRemove: () => context.read<KycCubit>().removeFile(reqId),
      );
    }

    return _Dropzone(label: 'Upload document', onTap: onPick);
  }
}

class _SidesUploader extends StatelessWidget {
  final String reqId;
  final List<String> sides;
  final KycState state;
  final void Function(int? sideIndex) onPickFile;

  const _SidesUploader({
    required this.reqId,
    required this.sides,
    required this.state,
    required this.onPickFile,
  });

  @override
  Widget build(BuildContext context) {
    final slots = state.files[reqId] ?? const [];
    return Row(
      children: [
        for (var i = 0; i < sides.length; i++) ...[
          if (i > 0) const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(sides[i], style: const TextStyle(color: Colors.white54, fontSize: 11)),
                const SizedBox(height: 6),
                if (i < slots.length && slots[i] != null)
                  _FileTile(
                    file: slots[i]!,
                    onRemove: () => context.read<KycCubit>().removeFile(reqId, sideIndex: i),
                    compact: true,
                  )
                else
                  _Dropzone(
                    label: 'Upload ${sides[i].toLowerCase()}',
                    onTap: () => onPickFile(i),
                    compact: true,
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _Dropzone extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final bool compact;

  const _Dropzone({required this.label, required this.onTap, this.compact = false});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        height: compact ? 96 : 110,
        decoration: BoxDecoration(
          color: AppColors.tertiary,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white12),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.upload_file_outlined, color: Colors.white38, size: 22),
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FileTile extends StatelessWidget {
  final KycPendingFile file;
  final VoidCallback onRemove;
  final bool compact;

  const _FileTile({required this.file, required this.onRemove, this.compact = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: compact ? 96 : null,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.tertiary,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: Colors.black26,
              borderRadius: BorderRadius.circular(8),
            ),
            child: file.isImage
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.memory(_asBytes(file.bytes), fit: BoxFit.cover),
                  )
                : const Icon(Icons.picture_as_pdf_outlined, color: Colors.white54, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              file.filename,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white38, size: 18),
            onPressed: onRemove,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }
}

// KycPendingFile.bytes is a List<int>; Image.memory needs Uint8List.
Uint8List _asBytes(List<int> bytes) => Uint8List.fromList(bytes);
