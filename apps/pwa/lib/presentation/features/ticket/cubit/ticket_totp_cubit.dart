import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lynk_x/presentation/features/ticket/models/ticket_model.dart';

part 'ticket_totp_state.dart';

/// Cubit responsible for generating dynamic HMAC-SHA256 TOTP tokens for anti-screenshot
/// security, ticking second-by-second countdowns and recalculating the signature across 30s boundaries.
class TicketTotpCubit extends Cubit<TicketTotpState> {
  Timer? _tickerTimer;
  TicketModel? _ticket;

  TicketTotpCubit() : super(const TicketTotpState());

  @override
  Future<void> close() {
    _tickerTimer?.cancel();
    return super.close();
  }

  /// Initialize or update the ticket to generate dynamic TOTP barcode signatures for.
  void setTicket(TicketModel ticket) {
    if (_ticket?.id == ticket.id &&
        _ticket?.displayCode == ticket.displayCode &&
        _ticket?.secretKey == ticket.secretKey) {
      return;
    }
    _ticket = ticket;
    _updateTotpState();
    _startTimer();
  }

  void _startTimer() {
    _tickerTimer?.cancel();
    _tickerTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _updateTotpState();
    });
  }

  /// Recomputes current TOTP token payload and second-by-second epoch progress.
  void _updateTotpState() {
    if (_ticket == null) return;

    final now = DateTime.now().toUtc();
    final millis = now.millisecondsSinceEpoch;
    final epoch30s = millis ~/ 30000;
    final elapsedInEpochMs = millis % 30000;
    final remainingSeconds = 30 - (elapsedInEpochMs ~/ 1000);
    final progress = (30000 - elapsedInEpochMs) / 30000.0;

    final payload = _generateTotpBarcodeData(_ticket!, epoch30s);

    emit(state.copyWith(
      barcodePayload: payload,
      secondsRemaining: remainingSeconds,
      progress: progress.clamp(0.0, 1.0),
    ));
  }

  /// Generates a dynamic HMAC-SHA256 TOTP payload signature valid for 30s.
  String _generateTotpBarcodeData(TicketModel ticket, int epoch30s) {
    final secretKey = ticket.secretKey ?? ticket.displayCode;
    final keyBytes = utf8.encode(secretKey);
    final messageBytes = utf8.encode('${ticket.id}:$epoch30s');
    final hmac = Hmac(sha256, keyBytes);
    final digest = hmac.convert(messageBytes);
    return '${ticket.displayCode}|$epoch30s|$digest';
  }
}
