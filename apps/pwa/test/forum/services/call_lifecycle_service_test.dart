import 'package:flutter_test/flutter_test.dart';
import 'package:lynk_x/presentation/features/forum/services/call_lifecycle_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CallLifecycleService', () {
    setUp(() {
      // Reset singleton state between tests
      CallLifecycleService().leave();
    });

    test('initial state is not joined', () {
      expect(CallLifecycleService().isJoined, false);
    });

    test('join is idempotent', () async {
      await CallLifecycleService().join();
      final first = CallLifecycleService().isJoined;
      await CallLifecycleService().join();
      expect(first, true);
      expect(CallLifecycleService().isJoined, true);
      CallLifecycleService().leave();
    });

    test('leave resets joined state', () async {
      await CallLifecycleService().join();
      expect(CallLifecycleService().isJoined, true);
      CallLifecycleService().leave();
      expect(CallLifecycleService().isJoined, false);
    });

    test('join after leave works again', () async {
      await CallLifecycleService().join();
      CallLifecycleService().leave();
      await CallLifecycleService().join();
      expect(CallLifecycleService().isJoined, true);
      CallLifecycleService().leave();
    });
  });
}
