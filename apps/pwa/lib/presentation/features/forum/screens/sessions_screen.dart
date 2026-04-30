import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:lynk_core/core.dart';
import 'package:go_router/go_router.dart';
import '../cubit/forum_sessions_cubit.dart';
import '../cubit/forum_sessions_state.dart';

class SessionsScreen extends StatelessWidget {
  final String eventId;
  final bool isOrganizer;

  const SessionsScreen({
    super.key,
    required this.eventId,
    this.isOrganizer = false,
  });

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => ForumSessionsCubit(eventId: eventId)..loadSessions(),
      child: SessionsView(isOrganizer: isOrganizer),
    );
  }
}

class SessionsView extends StatelessWidget {
  final bool isOrganizer;

  const SessionsView({super.key, required this.isOrganizer});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.primaryBackground,
      appBar: AppBar(
        backgroundColor: AppColors.primaryBackground,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white, size: 28),
          onPressed: () => context.pop(),
        ),
        title: Text(
          'Event Schedule',
          style: AppTypography.interTight(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        actions: [
          if (isOrganizer)
            IconButton(
              icon: const Icon(Icons.add, color: AppColors.primary),
              onPressed: () => _showSessionEditor(context),
            ),
        ],
      ),
      body: BlocBuilder<ForumSessionsCubit, ForumSessionsState>(
        builder: (context, state) {
          if (state.isLoading) {
            return const Center(
                child: CircularProgressIndicator(color: AppColors.primary));
          }

          if (state.errorMessage != null && state.sessions.isEmpty) {
            return Center(
              child: Text(
                state.errorMessage!,
                style: const TextStyle(color: Colors.redAccent),
              ),
            );
          }

          if (state.sessions.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.calendar_today_outlined,
                      size: 64, color: Colors.white10),
                  const SizedBox(height: 16),
                  Text(
                    'No sessions scheduled yet.',
                    style: AppTypography.inter(color: Colors.white38),
                  ),
                  if (isOrganizer) ...[
                    const SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: () => _showSessionEditor(context),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.black,
                      ),
                      child: const Text('Add First Session'),
                    ),
                  ],
                ],
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () => context.read<ForumSessionsCubit>().loadSessions(),
            color: AppColors.primary,
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: state.sessions.length,
              separatorBuilder: (context, index) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final session = state.sessions[index];
                return _SessionListItem(
                  session: session,
                  isOrganizer: isOrganizer,
                );
              },
            ),
          );
        },
      ),
    );
  }

  void _showSessionEditor(BuildContext context, {SessionModel? session}) {
    final cubit = context.read<ForumSessionsCubit>();
    final titleController = TextEditingController(text: session?.title);
    final roomController = TextEditingController(text: session?.room);
    DateTime startsAt = session?.startsAt ?? DateTime.now();
    DateTime endsAt =
        session?.endsAt ?? DateTime.now().add(const Duration(hours: 1));

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1A1A1A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (bottomContext) => StatefulBuilder(
        builder: (context, setState) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
            left: 24,
            right: 24,
            top: 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                session == null ? 'Add Session' : 'Edit Session',
                style: AppTypography.interTight(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 24),
              TextField(
                controller: titleController,
                style: const TextStyle(color: Colors.white),
                decoration: _inputDecoration('Session Title'),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: roomController,
                style: const TextStyle(color: Colors.white),
                decoration: _inputDecoration('Room / Location'),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _DateTimePicker(
                      label: 'Starts At',
                      value: startsAt,
                      onChanged: (val) => setState(() => startsAt = val),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _DateTimePicker(
                      label: 'Ends At',
                      value: endsAt,
                      onChanged: (val) => setState(() => endsAt = val),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: () {
                    final newSession = SessionModel(
                      id: session?.id ?? '', // ID handled by DB on insert
                      eventId: cubit.eventId,
                      title: titleController.text,
                      startsAt: startsAt,
                      endsAt: endsAt,
                      room: roomController.text.isEmpty
                          ? null
                          : roomController.text,
                    );

                    if (session == null) {
                      cubit.addSession(newSession);
                    } else {
                      cubit.updateSession(newSession);
                    }
                    Navigator.pop(context);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Text(session == null ? 'Create' : 'Save Changes'),
                ),
              ),
              if (session != null) ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: () {
                      cubit.deleteSession(session.id);
                      Navigator.pop(context);
                    },
                    child: const Text('Delete Session',
                        style: TextStyle(color: Colors.redAccent)),
                  ),
                ),
              ],
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Colors.white38),
      filled: true,
      fillColor: Colors.white.withValues(alpha: 0.05),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.primary, width: 1),
      ),
    );
  }
}

class _SessionListItem extends StatelessWidget {
  final SessionModel session;
  final bool isOrganizer;

  const _SessionListItem({required this.session, required this.isOrganizer});

  @override
  Widget build(BuildContext context) {
    final timeFormat = DateFormat('HH:mm');
    final dateFormat = DateFormat('MMM d');
    final now = DateTime.now();
    final isActive = now.isAfter(session.startsAt) && now.isBefore(session.endsAt);

    return Container(
      decoration: BoxDecoration(
        color: isActive
            ? AppColors.primary.withValues(alpha: 0.1)
            : const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isActive ? AppColors.primary : Colors.white10,
          width: isActive ? 1.5 : 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: ListTile(
          contentPadding: const EdgeInsets.all(16),
          title: Text(
            session.title,
            style: AppTypography.interTight(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.access_time,
                      size: 14,
                      color: isActive ? AppColors.primary : Colors.white38),
                  const SizedBox(width: 4),
                  Text(
                    '${timeFormat.format(session.startsAt)} - ${timeFormat.format(session.endsAt)} (${dateFormat.format(session.startsAt)})',
                    style: TextStyle(
                      color: isActive ? AppColors.primary : Colors.white60,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
              if (session.room != null) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(Icons.location_on_outlined,
                        size: 14, color: Colors.white38),
                    const SizedBox(width: 4),
                    Text(
                      session.room!,
                      style: const TextStyle(color: Colors.white38, fontSize: 13),
                    ),
                  ],
                ),
              ],
            ],
          ),
          trailing: isOrganizer
              ? IconButton(
                  icon: const Icon(Icons.edit_outlined, color: Colors.white24),
                  onPressed: () => (context.findAncestorWidgetOfExactType<SessionsView>())
                      ?._showSessionEditor(context, session: session),
                )
              : null,
        ),
      ),
    );
  }
}

class _DateTimePicker extends StatelessWidget {
  final String label;
  final DateTime value;
  final ValueChanged<DateTime> onChanged;

  const _DateTimePicker({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.white38, fontSize: 12)),
        const SizedBox(height: 8),
        InkWell(
          onTap: () async {
            final date = await showDatePicker(
              context: context,
              initialDate: value,
              firstDate: DateTime.now().subtract(const Duration(days: 365)),
              lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
            );
            if (date != null) {
              if (!context.mounted) return;
              final time = await showTimePicker(
                context: context,
                initialTime: TimeOfDay.fromDateTime(value),
              );
              if (time != null) {
                onChanged(DateTime(
                  date.year,
                  date.month,
                  date.day,
                  time.hour,
                  time.minute,
                ));
              }
            }
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              DateFormat('HH:mm, MMM d').format(value),
              style: const TextStyle(color: Colors.white, fontSize: 13),
            ),
          ),
        ),
      ],
    );
  }
}
