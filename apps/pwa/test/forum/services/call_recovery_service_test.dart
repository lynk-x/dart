import 'package:flutter_test/flutter_test.dart';
import 'package:lynk_x/presentation/features/forum/services/call_recovery_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CallRecoveryService', () {
    setUp(() {
      CallRecoveryService().cancel();
    });

    tearDown(() {
      CallRecoveryService().cancel();
    });

    test('requestReconnect does nothing if no action registered', () async {
      bool gaveUp = false;
      await CallRecoveryService().requestReconnect(
        side: RecoverySide.publish,
        onGiveUp: () => gaveUp = true,
      );
      expect(gaveUp, false);
    });

    test('successful action resets state', () async {
      var calls = 0;
      CallRecoveryService().setPublishAction(RecoveryAction(() async {
        calls++;
      }));
      bool gaveUp = false;
      await CallRecoveryService().requestReconnect(
        side: RecoverySide.publish,
        onGiveUp: () => gaveUp = true,
      );
      expect(calls, 1);
      expect(gaveUp, false);
    });

    test('RecoveryAbort stops immediately without retry', () async {
      var calls = 0;
      CallRecoveryService().setPublishAction(RecoveryAction(() async {
        calls++;
        throw RecoveryAbort('test');
      }));
      bool gaveUp = false;
      await CallRecoveryService().requestReconnect(
        side: RecoverySide.publish,
        onGiveUp: () => gaveUp = true,
      );
      expect(calls, 1);
      expect(gaveUp, false);
    });

    test('cancel resets state', () async {
      CallRecoveryService().setPublishAction(RecoveryAction(() async {}));
      CallRecoveryService().cancel();
      expect(CallRecoveryService().isRecoveringNotifier.value, false);
      expect(CallRecoveryService().attemptNotifier.value, 0);
    });
  });
}
