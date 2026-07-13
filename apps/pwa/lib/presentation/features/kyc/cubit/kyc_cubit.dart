import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:lynk_core/core.dart';

import 'package:lynk_x/data/repositories/repositories.dart';
import 'package:lynk_x/data/repositories/repository_providers.dart';
import 'package:lynk_x/core/utils/storage_utils.dart';
import 'kyc_state.dart';

/// Mirrors identity.kyc_document_type in supabase/schema/00_base/04_types.sql.
const _validDocumentTypes = {
  'national_id',
  'passport',
  'alien_card',
  'incorporation_cert',
  'utility_bill',
};

String _resolveDocumentType(String? raw) {
  if (raw == null) return 'national_id';
  for (final candidate in raw.split('|')) {
    if (_validDocumentTypes.contains(candidate)) return candidate;
  }
  return 'national_id';
}

/// Drives the attendee/organizer identity-verification flow: resolves the
/// caller's account, loads dynamic requirements + current status, collects
/// documents/info across a 3-step wizard, and submits one verification
/// attempt via api.submit_identity_verification.
class KycCubit extends Cubit<KycState> {
  final KycRepository _repo;
  final SupabaseClient _supabase;

  KycCubit({KycRepository? repository, SupabaseClient? supabase})
      : _repo = repository ?? kycRepository,
        _supabase = supabase ?? Supabase.instance.client,
        super(const KycState());

  Future<void> load() async {
    emit(state.copyWith(isLoading: true, clearError: true));
    try {
      final accountId = await _resolveAccountId();
      if (accountId == null) {
        emit(state.copyWith(isLoading: false, error: 'No account found for this profile.'));
        return;
      }

      final account = await _supabase
          .schema('api')
          .from('v1_accounts')
          .select('type, country_code')
          .eq('id', accountId)
          .maybeSingle();

      final accountType = account?['type'] as String? ?? 'organizer';
      final countryCode = account?['country_code'] as String? ?? 'KE';

      final results = await Future.wait([
        _repo.getRequirements(countryCode: countryCode, accountType: accountType),
        _repo.getStatus(accountId),
      ]);
      final requirements = results[0] as List<Map<String, dynamic>>;
      final statusData = results[1] as Map<String, dynamic>;

      emit(state.copyWith(
        isLoading: false,
        accountId: accountId,
        accountType: accountType,
        countryCode: countryCode,
        requirements: requirements,
        status: kycStatusFromString(statusData['status'] as String?),
        rejectionReason: statusData['status'] == 'rejected'
            ? statusData['rejection_reason'] as String?
            : null,
      ));
    } catch (e) {
      emit(state.copyWith(isLoading: false, error: e.toFriendlyMessage()));
    }
  }

  Future<String?> _resolveAccountId() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return null;
    final row = await _supabase
        .schema('api')
        .from('v1_account_memberships')
        .select('account_id')
        .eq('user_id', userId)
        .order('created_at', ascending: true)
        .limit(1)
        .maybeSingle();
    return row?['account_id'] as String?;
  }

  // ── Step navigation ────────────────────────────────────────────────────

  void goToStep(KycStep step) => emit(state.copyWith(step: step));

  // ── Text fields ────────────────────────────────────────────────────────

  void setTextValue(String reqId, String value) {
    emit(state.copyWith(textValues: {...state.textValues, reqId: value}));
  }

  // ── File staging & review ─────────────────────────────────────────────

  /// Stages a just-picked file. Images go through a readability-confirmation
  /// step (see [confirmPendingReview]); non-images commit immediately.
  void stageFile({
    required String reqId,
    required KycPendingFile file,
    int? sideIndex,
  }) {
    if (!file.isImage) {
      _commitFile(reqId, file, sideIndex);
      return;
    }
    emit(state.copyWith(
      pendingReviewReqId: reqId,
      pendingReviewSideIndex: sideIndex,
      pendingReviewFile: file,
    ));
  }

  void confirmPendingReview() {
    if (!state.hasPendingReview) return;
    _commitFile(state.pendingReviewReqId!, state.pendingReviewFile!, state.pendingReviewSideIndex);
    emit(state.copyWith(clearPendingReview: true));
  }

  void retakePendingReview() {
    emit(state.copyWith(clearPendingReview: true));
  }

  void _commitFile(String reqId, KycPendingFile file, int? sideIndex) {
    final next = Map<String, List<KycPendingFile?>>.from(state.files);
    final slots = List<KycPendingFile?>.from(next[reqId] ?? const []);
    if (sideIndex != null) {
      while (slots.length <= sideIndex) {
        slots.add(null);
      }
      slots[sideIndex] = file;
    } else {
      slots
        ..clear()
        ..add(file);
    }
    next[reqId] = slots;
    emit(state.copyWith(files: next));
  }

  void removeFile(String reqId, {int? sideIndex}) {
    final next = Map<String, List<KycPendingFile?>>.from(state.files);
    final slots = List<KycPendingFile?>.from(next[reqId] ?? const []);
    if (sideIndex != null && sideIndex < slots.length) {
      slots[sideIndex] = null;
    } else {
      slots.clear();
    }
    next[reqId] = slots;
    emit(state.copyWith(files: next));
  }

  // ── Confirm step ───────────────────────────────────────────────────────

  void setConsentAccepted(bool value) => emit(state.copyWith(consentAccepted: value));
  void setAccuracyConfirmed(bool value) => emit(state.copyWith(accuracyConfirmed: value));

  // ── Submit ─────────────────────────────────────────────────────────────

  Future<void> submit({String tierSlug = 'tier_1_basic'}) async {
    final accountId = state.accountId;
    if (accountId == null || !state.consentAccepted || !state.accuracyConfirmed) return;

    emit(state.copyWith(isSubmitting: true, clearError: true));
    try {
      final uploadedDocs = <String>[];
      final piiData = <String, dynamic>{
        'data_processing_consent': true,
        'data_accuracy_confirmed': true,
      };
      String? primaryDocumentType;

      for (final req in state.requirements) {
        final id = req['id'] as String;
        if (req['type'] == 'file') {
          final slots = state.files[id];
          if (slots == null || slots.every((f) => f == null)) continue;

          for (final file in slots) {
            if (file == null) continue;
            final ext = file.filename.split('.').last;
            final name = '${DateTime.now().millisecondsSinceEpoch}_${id}_$ext';
            final fileKey = await uploadToStorage(
              bytes: file.bytes,
              filename: name,
              contentType: file.contentType,
              folder: 'accounts',
              mediaType: 'image',
            );
            uploadedDocs.add(fileKey);
          }
          primaryDocumentType ??= _resolveDocumentType((req['subtype'] as String?) ?? id);
        } else {
          final value = state.textValues[id];
          if (value == null || value.trim().isEmpty) continue;
          piiData[id] = value.trim();
        }
      }

      final result = await _repo.submit(
        accountId: accountId,
        tierSlug: tierSlug,
        documentType: primaryDocumentType ?? 'national_id',
        uploadedDocs: uploadedDocs,
        piiData: piiData,
      );

      emit(state.copyWith(
        isSubmitting: false,
        submitted: result['success'] == true,
        status: KycStatus.pending,
      ));
    } catch (e) {
      emit(state.copyWith(isSubmitting: false, error: e.toFriendlyMessage()));
    }
  }
}
