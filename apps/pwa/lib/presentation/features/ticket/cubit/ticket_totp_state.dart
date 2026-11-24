part of 'ticket_totp_cubit.dart';

/// State representing the dynamic anti-screenshot TOTP payload and validity progress.
class TicketTotpState {
  /// The HMAC-SHA256 signature payload encoded as:
  /// `${displayCode}|${epoch30s}|${digest}`
  final String barcodePayload;

  /// Time remaining in seconds before current TOTP token expires (0..30).
  final int secondsRemaining;

  /// Progress of current TOTP token epoch from 1.0 (fresh) down to 0.0 (expired).
  final double progress;

  const TicketTotpState({
    this.barcodePayload = '',
    this.secondsRemaining = 30,
    this.progress = 1.0,
  });

  TicketTotpState copyWith({
    String? barcodePayload,
    int? secondsRemaining,
    double? progress,
  }) {
    return TicketTotpState(
      barcodePayload: barcodePayload ?? this.barcodePayload,
      secondsRemaining: secondsRemaining ?? this.secondsRemaining,
      progress: progress ?? this.progress,
    );
  }
}
