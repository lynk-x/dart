import 'package:flutter_test/flutter_test.dart';
import 'package:lynk_x/presentation/features/notifications/cubit/notification_cubit.dart';
import 'package:lynk_x/presentation/features/notifications/cubit/notification_state.dart';
import 'package:lynk_x/data/repositories/repositories.dart';
import 'package:mocktail/mocktail.dart';

class MockNotificationRepository extends Mock implements NotificationRepository {}
class MockAccountRepository extends Mock implements AccountRepository {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('NotificationCubit', () {
    late MockNotificationRepository repo;
    late MockAccountRepository accountRepo;

    setUp(() {
      repo = MockNotificationRepository();
      accountRepo = MockAccountRepository();
    });

    test('initial state is NotificationInitial', () {
      final cubit = NotificationCubit(repo, accountRepo);
      expect(cubit.state, isA<NotificationInitial>());
      cubit.close();
    });

    test('reset clears state', () {
      final cubit = NotificationCubit(repo, accountRepo);
      cubit.reset();
      expect(cubit.state, isA<NotificationInitial>());
      cubit.close();
    });
  });
}
