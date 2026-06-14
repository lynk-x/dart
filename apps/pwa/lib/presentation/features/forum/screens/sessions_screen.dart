import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:lynk_core/core.dart';
import 'package:go_router/go_router.dart';
import '../cubit/forum_sessions_cubit.dart';
import '../cubit/forum_sessions_state.dart';

class SessionsScreen extends StatelessWidget {
  final String? forumId;
  final bool isOrganizer;
  final DateTime? forumCreatedAt;
  final String? forumReference;

  const SessionsScreen({
    super.key,
    this.forumId,
    this.isOrganizer = false,
    this.forumCreatedAt,
    this.forumReference,
  });

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => ForumSessionsCubit(
        forumId: forumId ?? '',
        forumCreatedAt: forumCreatedAt,
        forumReference: forumReference,
      )..loadSessions(),
      child: SessionsView(
        isOrganizer: isOrganizer,
        forumReference: forumReference,
      ),
    );
  }
}

class SessionsView extends StatelessWidget {
  final bool isOrganizer;
  final String? forumReference;

  const SessionsView({
    super.key,
    required this.isOrganizer,
    this.forumReference,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.primaryBackground,
      appBar: AppBar(
        backgroundColor: AppColors.primaryBackground,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white, size: 32),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else if (forumReference != null && forumReference!.isNotEmpty) {
              context.go('/forum/$forumReference');
            } else {
              context.go('/');
            }
          },
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
              icon: Icon(Icons.add, color: context.accentColor, size: 32),
              onPressed: () => _showSessionEditor(context),
            ),
        ],
      ),
      body: BlocBuilder<ForumSessionsCubit, ForumSessionsState>(
        builder: (context, state) {
          if (state.isLoading) {
            return Center(
                child: CircularProgressIndicator(color: context.accentColor));
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
                        backgroundColor: context.accentColor,
                        foregroundColor: Colors.black,
                      ),
                      child: const Text('Add First Session'),
                    ),
                  ],
                ],
              ),
            );
          }

          final sortedSessions = List<SessionModel>.from(state.sessions)
            ..sort((a, b) => a.startsAt.compareTo(b.startsAt));

          final items = <dynamic>[];
          DateTime? lastDate;
          for (final session in sortedSessions) {
            final sessionDate = DateTime(session.startsAt.year, session.startsAt.month, session.startsAt.day);
            if (lastDate == null || lastDate != sessionDate) {
              lastDate = sessionDate;
              items.add(sessionDate);
            }
            items.add(session);
          }

          final dateFormat = DateFormat('EEEE, MMMM d');

          return RefreshIndicator(
            onRefresh: () => context.read<ForumSessionsCubit>().loadSessions(),
            color: context.accentColor,
            child: ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              itemCount: items.length,
              itemBuilder: (context, index) {
                final item = items[index];
                if (item is DateTime) {
                  return Padding(
                    padding: const EdgeInsets.only(top: 20, bottom: 8, left: 4),
                    child: Text(
                      dateFormat.format(item).toUpperCase(),
                      style: AppTypography.interTight(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: context.accentColor,
                        letterSpacing: 1.2,
                      ),
                    ),
                  );
                }

                final session = item as SessionModel;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: _SessionListItem(
                    session: session,
                    isOrganizer: isOrganizer,
                    onEdit: () => _showSessionEditor(context, session: session),
                  ),
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
        builder: (_, setState) => Padding(
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
                decoration: _inputDecoration('Session Title', context),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: roomController,
                style: const TextStyle(color: Colors.white),
                decoration: _inputDecoration('Room / Location', context),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _DateTimePicker(
                      label: 'Starts At',
                      value: startsAt,
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(12),
                        bottomLeft: Radius.circular(12),
                      ),
                      showRightBorder: true,
                      onChanged: (val) => setState(() => startsAt = val),
                    ),
                  ),
                  Expanded(
                    child: _DateTimePicker(
                      label: 'Ends At',
                      value: endsAt,
                      borderRadius: const BorderRadius.only(
                        topRight: Radius.circular(12),
                        bottomRight: Radius.circular(12),
                      ),
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
                    final title = titleController.text.trim();
                    if (title.isEmpty) {
                      ScaffoldMessenger.of(bottomContext).showSnackBar(
                        const SnackBar(content: Text('Session title is required.')),
                      );
                      return;
                    }
                    if (!endsAt.isAfter(startsAt)) {
                      ScaffoldMessenger.of(bottomContext).showSnackBar(
                        const SnackBar(content: Text('End time must be after start time.')),
                      );
                      return;
                    }

                    final newSession = SessionModel(
                      id: session?.id ?? '',
                      forumId: cubit.activeForumId,
                      title: title,
                      startsAt: startsAt,
                      endsAt: endsAt,
                      room: roomController.text.trim().isEmpty
                          ? null
                          : roomController.text.trim(),
                      forumCreatedAt: session?.forumCreatedAt ?? cubit.activeForumCreatedAt,
                    );

                    if (session == null) {
                      cubit.addSession(newSession);
                    } else {
                      cubit.updateSession(newSession);
                    }
                    Navigator.pop(bottomContext);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: context.accentColor,
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
                  height: 50,
                  child: ElevatedButton(
                    onPressed: () {
                      cubit.deleteSession(session.id);
                      Navigator.pop(bottomContext);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.redAccent.withValues(alpha: 0.15),
                      foregroundColor: Colors.redAccent,
                      elevation: 0,
                      side: const BorderSide(color: Colors.redAccent, width: 1.5),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Delete Session',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
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

  InputDecoration _inputDecoration(String label, BuildContext context) {
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
        borderSide: BorderSide(color: context.accentColor, width: 1),
      ),
    );
  }
}

class _LiveIndicator extends StatelessWidget {
  const _LiveIndicator();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.redAccent,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        'LIVE NOW',
        style: AppTypography.interTight(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      ),
    );
  }
}

class _SessionListItem extends StatelessWidget {
  final SessionModel session;
  final bool isOrganizer;
  final VoidCallback? onEdit;

  const _SessionListItem({
    required this.session,
    required this.isOrganizer,
    this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final timeFormat = DateFormat('HH:mm');
    final dateFormat = DateFormat('MMM d');
    final now = DateTime.now();
    final isActive = now.isAfter(session.startsAt) && now.isBefore(session.endsAt);

    return Container(
      decoration: BoxDecoration(
        color: isActive
            ? Color.lerp(const Color(0xFF1E1E1E), context.accentColor, 0.1)!
            : const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isActive ? context.accentColor : const Color(0xFF2C2C2C),
          width: isActive ? 1.5 : 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      session.title,
                      style: AppTypography.interTight(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(Icons.access_time,
                            size: 14,
                            color: isActive ? context.accentColor : Colors.white38),
                        const SizedBox(width: 4),
                        Text(
                          '${timeFormat.format(session.startsAt)} - ${timeFormat.format(session.endsAt)} (${dateFormat.format(session.startsAt)})',
                          style: TextStyle(
                            color: isActive ? context.accentColor : Colors.white60,
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
              ),
              if (isActive) ...[
                const SizedBox(width: 8),
                const _LiveIndicator(),
              ],
              if (isOrganizer) ...[
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.edit_outlined, color: Colors.white24),
                  onPressed: onEdit,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _DateTimePicker extends StatelessWidget {
  final String label;
  final DateTime value;
  final ValueChanged<DateTime> onChanged;
  final BorderRadius? borderRadius;
  final bool showRightBorder;

  const _DateTimePicker({
    required this.label,
    required this.value,
    required this.onChanged,
    this.borderRadius,
    this.showRightBorder = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.white38, fontSize: 12)),
        const SizedBox(height: 8),
        InkWell(
          onTap: () {
            DateTime tempDateTime = value;
            showCupertinoModalPopup<void>(
              context: context,
              builder: (BuildContext modalContext) => CupertinoTheme(
                data: const CupertinoThemeData(
                  brightness: Brightness.dark,
                ),
                child: Container(
                  height: 300,
                  color: const Color(0xFF1E1E1E),
                  child: Column(
                    children: [
                      Container(
                        decoration: const BoxDecoration(
                          color: Color(0xFF2C2C2C),
                          border: Border(
                            bottom: BorderSide(color: Colors.white12, width: 0.5),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            CupertinoButton(
                              child: const Text('Cancel', style: TextStyle(color: Colors.white54, fontSize: 15)),
                              onPressed: () => Navigator.pop(modalContext),
                            ),
                            Text(
                              label,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                decoration: TextDecoration.none,
                              ),
                            ),
                            CupertinoButton(
                              child: Text(
                                'Done',
                                style: TextStyle(
                                  color: context.accentColor,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                ),
                              ),
                              onPressed: () {
                                onChanged(tempDateTime);
                                Navigator.pop(modalContext);
                              },
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: CupertinoDatePicker(
                          initialDateTime: value,
                          mode: CupertinoDatePickerMode.dateAndTime,
                          use24hFormat: false,
                          onDateTimeChanged: (DateTime newDateTime) {
                            tempDateTime = newDateTime;
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: borderRadius ?? BorderRadius.circular(12),
              border: showRightBorder
                  ? const Border(
                      right: BorderSide(color: Colors.white12, width: 0.5),
                    )
                  : null,
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
