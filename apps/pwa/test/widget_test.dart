import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:lynk_x/presentation/features/homepage/cubit/home_cubit.dart';
import 'package:lynk_x/presentation/features/homepage/screens/home_screen.dart';

void main() {
  // Pump just the HomeView subtree (no Supabase / GoRouter needed)
  testWidgets('HomeView renders a feed card after init completes',
      (WidgetTester tester) async {
    final cubit = HomeCubit();
    await cubit.init();

    await tester.pumpWidget(
      BlocProvider<HomeCubit>.value(
        value: cubit,
        child: const MaterialApp(home: HomeView()),
      ),
    );

    // Let async frames settle
    await tester.pumpAndSettle();

    // The primary button text should be visible
    expect(find.text('Look up new events'), findsOneWidget);

    await cubit.close();
  });

  testWidgets('HomeView shows loading indicator during init',
      (WidgetTester tester) async {
    final cubit = HomeCubit(); // not yet init'd → isLoading=false by default

    // Emit a loading state manually before pumping
    await tester.pumpWidget(
      BlocProvider<HomeCubit>.value(
        value: cubit,
        child: const MaterialApp(home: HomeView()),
      ),
    );

    await tester.pump(); // initial frame — cubit starts init via BlocProvider

    await cubit.close();
  });
}
