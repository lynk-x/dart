import 'package:equatable/equatable.dart';

/// One in-progress file selected for a given requirement (or requirement+side).
class KycPendingFile extends Equatable {
  final List<int> bytes;
  final String filename;
  final String contentType;

  const KycPendingFile({
    required this.bytes,
    required this.filename,
    required this.contentType,
  });

  bool get isImage => contentType.startsWith('image/');

  @override
  List<Object?> get props => [filename, bytes.length, contentType];
}

/// Which step of the verification flow is active.
enum KycStep { info, documents, confirm }

/// Latest verification attempt status, mirrored from
/// identity.identity_verifications.status (infra.approval_status).
enum KycStatus { notStarted, pending, approved, rejected, unknown }

KycStatus kycStatusFromString(String? raw) {
  switch (raw) {
    case 'not_started':
      return KycStatus.notStarted;
    case 'pending':
      return KycStatus.pending;
    case 'approved':
      return KycStatus.approved;
    case 'rejected':
      return KycStatus.rejected;
    default:
      return raw == null ? KycStatus.notStarted : KycStatus.unknown;
  }
}

class KycState extends Equatable {
  // ── Loading ──────────────────────────────────────────────────────────────
  final bool isLoading;
  final bool isSubmitting;
  final String? error;

  // ── Resolved context ────────────────────────────────────────────────────
  final String? accountId;
  final String? accountType;
  final String? countryCode;

  // ── Current status ──────────────────────────────────────────────────────
  final KycStatus status;
  final String? rejectionReason;

  // ── Requirements & in-progress submission ───────────────────────────────
  final List<Map<String, dynamic>> requirements;
  final KycStep step;

  /// Keyed by requirement id. A requirement without `sides` stores its file(s)
  /// at index 0; a requirement with `sides` stores one entry per side index.
  final Map<String, List<KycPendingFile?>> files;
  final Map<String, String> textValues;

  /// An image just picked, staged for the user to confirm it's readable
  /// before it's committed to [files] — mirrors the web's review-before-commit step.
  final String? pendingReviewReqId;
  final int? pendingReviewSideIndex;
  final KycPendingFile? pendingReviewFile;

  final bool consentAccepted;
  final bool accuracyConfirmed;
  final bool submitted;

  const KycState({
    this.isLoading = true,
    this.isSubmitting = false,
    this.error,
    this.accountId,
    this.accountType,
    this.countryCode,
    this.status = KycStatus.notStarted,
    this.rejectionReason,
    this.requirements = const [],
    this.step = KycStep.info,
    this.files = const {},
    this.textValues = const {},
    this.pendingReviewReqId,
    this.pendingReviewSideIndex,
    this.pendingReviewFile,
    this.consentAccepted = false,
    this.accuracyConfirmed = false,
    this.submitted = false,
  });

  List<Map<String, dynamic>> get textRequirements =>
      requirements.where((r) => r['type'] == 'text').toList();

  List<Map<String, dynamic>> get fileRequirements =>
      requirements.where((r) => r['type'] == 'file').toList();

  /// True when every mandatory requirement in [subset] has a satisfying value.
  bool isSatisfied(List<Map<String, dynamic>> subset) {
    for (final req in subset) {
      if (req['mandatory'] != true) continue;
      final id = req['id'] as String;
      if (req['type'] == 'file') {
        final sides = (req['sides'] as List?)?.cast<String>();
        final slots = files[id];
        if (sides != null) {
          for (var i = 0; i < sides.length; i++) {
            if (slots == null || i >= slots.length || slots[i] == null) return false;
          }
        } else if (slots == null || slots.isEmpty || slots[0] == null) {
          return false;
        }
      } else {
        final value = textValues[id];
        if (value == null || value.trim().isEmpty) return false;
      }
    }
    return true;
  }

  bool get hasPendingReview => pendingReviewFile != null;

  KycState copyWith({
    bool? isLoading,
    bool? isSubmitting,
    String? error,
    bool clearError = false,
    String? accountId,
    String? accountType,
    String? countryCode,
    KycStatus? status,
    String? rejectionReason,
    List<Map<String, dynamic>>? requirements,
    KycStep? step,
    Map<String, List<KycPendingFile?>>? files,
    Map<String, String>? textValues,
    String? pendingReviewReqId,
    int? pendingReviewSideIndex,
    KycPendingFile? pendingReviewFile,
    bool clearPendingReview = false,
    bool? consentAccepted,
    bool? accuracyConfirmed,
    bool? submitted,
  }) {
    return KycState(
      isLoading: isLoading ?? this.isLoading,
      isSubmitting: isSubmitting ?? this.isSubmitting,
      error: clearError ? null : (error ?? this.error),
      accountId: accountId ?? this.accountId,
      accountType: accountType ?? this.accountType,
      countryCode: countryCode ?? this.countryCode,
      status: status ?? this.status,
      rejectionReason: rejectionReason ?? this.rejectionReason,
      requirements: requirements ?? this.requirements,
      step: step ?? this.step,
      files: files ?? this.files,
      textValues: textValues ?? this.textValues,
      pendingReviewReqId: clearPendingReview ? null : (pendingReviewReqId ?? this.pendingReviewReqId),
      pendingReviewSideIndex: clearPendingReview ? null : (pendingReviewSideIndex ?? this.pendingReviewSideIndex),
      pendingReviewFile: clearPendingReview ? null : (pendingReviewFile ?? this.pendingReviewFile),
      consentAccepted: consentAccepted ?? this.consentAccepted,
      accuracyConfirmed: accuracyConfirmed ?? this.accuracyConfirmed,
      submitted: submitted ?? this.submitted,
    );
  }

  @override
  List<Object?> get props => [
        isLoading,
        isSubmitting,
        error,
        accountId,
        accountType,
        countryCode,
        status,
        rejectionReason,
        requirements,
        step,
        files,
        textValues,
        pendingReviewReqId,
        pendingReviewSideIndex,
        pendingReviewFile,
        consentAccepted,
        accuracyConfirmed,
        submitted,
      ];
}
