import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:lynk_x/presentation/features/homepage/cubit/home_cubit.dart';
import 'package:lynk_x/presentation/features/homepage/screens/home_screen.dart';
import 'package:lynk_x/presentation/features/notifications/cubit/notification_cubit.dart';
import 'package:lynk_x/data/repositories/event_repository.dart';
import 'package:lynk_x/data/repositories/notification_repository.dart';
import 'package:lynk_core/core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _FakeSupabaseClient extends Fake implements SupabaseClient {}

class _FakeEventRepository extends EventRepository {
  _FakeEventRepository() : super(_FakeSupabaseClient());

  @override
  Future<List<EventModel>> getUserForums(String userId,
          {int limit = 15, int offset = 0}) async =>
      [];
}

class _FakeNotificationRepository extends Fake implements NotificationRepository {}

class _FakeNotificationCubit extends NotificationCubit {
  _FakeNotificationCubit() : super(_FakeNotificationRepository());

  @override
  Future<void> loadNotifications() async {}

  @override
  void reset() {}
}

void main() {
  testWidgets('HomeView renders empty state when no events',
      (WidgetTester tester) async {
    final homeCubit = HomeCubit(_FakeEventRepository());
    final notificationCubit = _FakeNotificationCubit();

    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<HomeCubit>.value(value: homeCubit),
          BlocProvider<NotificationCubit>.value(value: notificationCubit),
        ],
        child: const MaterialApp(home: HomeView()),
      ),
    );

    await tester.pumpAndSettle();
    await homeCubit.close();
    await notificationCubit.close();
  });

  testWidgets('HomeView shows loading indicator during init',
      (WidgetTester tester) async {
    final homeCubit = HomeCubit(_FakeEventRepository());
    final notificationCubit = _FakeNotificationCubit();

    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<HomeCubit>.value(value: homeCubit),
          BlocProvider<NotificationCubit>.value(value: notificationCubit),
        ],
        child: const MaterialApp(home: HomeView()),
      ),
    );

    await tester.pump();
    await homeCubit.close();
    await notificationCubit.close();
  });
}
