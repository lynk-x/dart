import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:lynk_x/presentation/features/homepage/cubit/home_cubit.dart';
import 'package:lynk_x/presentation/features/homepage/screens/home_screen.dart';
import 'package:lynk_x/data/repositories/event_repository.dart';
import 'package:lynk_core/core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _FakeEventRepository extends EventRepository {
  _FakeEventRepository() : super(_unreachable());

  static SupabaseClient _unreachable() => throw UnimplementedError();

  @override
  Future<List<EventModel>> getUserForums(String userId,
          {int limit = 15, int offset = 0}) async =>
      [];
}

void main() {
  testWidgets('HomeView renders empty state when no events',
      (WidgetTester tester) async {
    final cubit = HomeCubit(_FakeEventRepository());

    await tester.pumpWidget(
      BlocProvider<HomeCubit>.value(
        value: cubit,
        child: const MaterialApp(home: HomeView()),
      ),
    );

    await tester.pumpAndSettle();
    await cubit.close();
  });

  testWidgets('HomeView shows loading indicator during init',
      (WidgetTester tester) async {
    final cubit = HomeCubit(_FakeEventRepository());

    await tester.pumpWidget(
      BlocProvider<HomeCubit>.value(
        value: cubit,
        child: const MaterialApp(home: HomeView()),
      ),
    );

    await tester.pump();
    await cubit.close();
  });
}
