import 'dart:async';
import 'package:flutter/material.dart';
import 'package:lynk_core/core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:lynk_x/l10n/app_localizations.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../cubit/forum_audio_stream_cubit.dart';
import '../services/stream_service.dart';
import '../services/participant_service.dart';
import 'skeletons.dart';
import 'user_presence.dart';
import 'stream_stage.dart' show ForumVideoStage;
import 'package:lynk_x/presentation/shared/utils/app_snackbars.dart';

/// The end-drawer component for the Forum screen.
///
/// Refactored to delegate layout into modular child components:
/// - [ParticipantList]: Manages member roster presence cards and media controls.
/// - [EventProgressTimeline]: Displays event progress bar and session progress indicator.
class PresenceDrawer extends StatefulWidget {
  /// The current progress of the forum's active event (0.0 to 1.0).
  final double eventProgress;

  /// Full forum roster (from `ForumState.members`) — every member,
  /// regardless of whether they're currently online.
  final List<Map<String, dynamic>> members;

  /// List of online users extracted from Supabase Presence.
  final List<Map<String, dynamic>> onlineUsers;

  final bool isPremium;
  final bool isOrganizer;
  final bool isAudioLive;
  final String? eventId;
  final String forumId;
  final DateTime? eventCreatedAt;
  final VoidCallback? onEventProgressTap;
  final bool isLoading;

  const PresenceDrawer({
    super.key,
    required this.eventProgress,
    required this.members,
    required this.onlineUsers,
    required this.isPremium,
    required this.isOrganizer,
    required this.forumId,
    required this.isLoading,
    this.isAudioLive = false,
    this.eventId,
    this.eventCreatedAt,
    this.onEventProgressTap,
  });

  @override
  State<PresenceDrawer> createState() => _PresenceDrawerState();
}

class _PresenceDrawerState extends State<PresenceDrawer> {
  bool _showSettingsView = false;
  List<MediaDevice> _availableDevices = [];
  bool _isLoadingDevices = false;
  bool _devicesLoaded = false;

  String _selectedCamera = 'Built-in Front Camera';
  String _selectedAudioInput = 'Default Microphone';
  String _selectedAudioOutput = 'Default Speaker';
  String _streamQuality = 'Auto (Adaptive HD)';
  List<Map<String, dynamic>> _cachedRoster = const [];

  ForumAudioStreamCubit? _audioCubit;
  StreamSubscription? _audioCubitSub;

  @override
  void initState() {
    super.initState();
    try {
      _audioCubit = context.read<ForumAudioStreamCubit>();
    } catch (_) {}
    _audioCubitSub = _audioCubit?.stream.listen((_) => _onCallMembershipChanged());

    // No setState here — this runs before the first build, so assigning
    // directly is enough (matches the pattern setState would otherwise
    // redundantly trigger).
    _cachedRoster = _buildMergedRoster(widget.members, widget.onlineUsers, _collectInCallUserIds());
    ForumVideoStreamService().activeParticipantsNotifier.addListener(_onCallMembershipChanged);
  }

  @override
  void didUpdateWidget(PresenceDrawer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.members, widget.members) ||
        !identical(oldWidget.onlineUsers, widget.onlineUsers)) {
      _rebuildRoster();
    }
  }

  void _onCallMembershipChanged() {
    if (!mounted) return;
    _rebuildRoster();
  }

  void _rebuildRoster() {
    final inCallIds = _collectInCallUserIds();
    final next = _buildMergedRoster(widget.members, widget.onlineUsers, inCallIds);
    setState(() {
      _cachedRoster = next;
    });
  }


  Set<String> _collectInCallUserIds() {
    final ids = <String>{};
    for (final p in ForumVideoStreamService().activeParticipantsNotifier.value) {
      if (p.id.isNotEmpty) ids.add(p.id);
    }

    final audioState = _audioCubit?.state;
    if (audioState != null && audioState.isLive) {
      final speakerNames = audioState.activeSpeakerNames.toSet();
      if (speakerNames.isNotEmpty) {
        for (final m in widget.members) {
          final id = (m['id'] ?? '').toString();
          final name = (m['user_name'] ?? '').toString();
          if (id.isNotEmpty && speakerNames.contains(name)) ids.add(id);
        }
        for (final u in widget.onlineUsers) {
          final id = (u['user_id'] ?? u['id'] ?? '').toString();
          final name = (u['user_name'] ?? u['full_name'] ?? '').toString();
          if (id.isNotEmpty && speakerNames.contains(name)) ids.add(id);
        }
      }
    }

    return ids;
  }

  @override
  void dispose() {
    ForumVideoStreamService().activeParticipantsNotifier.removeListener(_onCallMembershipChanged);
    _audioCubitSub?.cancel();
    super.dispose();
  }

  Future<void> _loadAvailableDevices() async {
    if (_devicesLoaded) return;
    setState(() {
      _isLoadingDevices = true;
    });
    final devices = await MediaDeviceManager().getAvailableDevices();
    if (mounted) {
      setState(() {
        _availableDevices = devices;
        _isLoadingDevices = false;
        _devicesLoaded = true;
      });
    }
  }

  /// Merges the full member roster with live presence, keyed by user id.
  /// [inCallIds] marks members currently attached to a live video call/
  /// stream or actively speaking in a live audio call (see
  /// _collectInCallUserIds) — used to rank them above other online members.
  static List<Map<String, dynamic>> _buildMergedRoster(
    List<Map<String, dynamic>> members,
    List<Map<String, dynamic>> onlineUsers,
    Set<String> inCallIds,
  ) {
    final onlineById = <String, Map<String, dynamic>>{};
    for (final u in onlineUsers) {
      final id = (u['user_id'] ?? u['id'] ?? '').toString();
      if (id.isNotEmpty) onlineById[id] = u;
    }

    final seen = <String>{};
    final merged = <Map<String, dynamic>>[];

    for (final m in members) {
      final id = (m['id'] ?? '').toString();
      if (id.isEmpty) continue;
      seen.add(id);
      final online = onlineById[id];
      merged.add({
        'id': id,
        'user_name':
            online?['user_name'] ?? online?['full_name'] ?? m['user_name'] ?? '',
        'role_id': m['role_id'],
        'is_organizer': online?['is_organizer'] ?? m['is_organizer'] == true,
        'is_premium': m['is_premium'] == true,
        'is_online': online != null,
        'is_in_call': inCallIds.contains(id),
        'joined_at': m['joined_at'],
      });
    }

    for (final u in onlineUsers) {
      final id = (u['user_id'] ?? u['id'] ?? '').toString();
      if (id.isEmpty || seen.contains(id)) continue;
      merged.add({
        'id': id,
        'user_name': u['user_name'] ?? u['full_name'] ?? 'Unknown',
        'role_id': u['is_organizer'] == true ? 'organizer' : null,
        'is_organizer': u['is_organizer'] == true,
        'is_premium': u['is_premium'] == true,
        'is_online': true,
        'is_in_call': inCallIds.contains(id),
        'joined_at': null,
      });
    }

    // Ordered by role, then live-call membership, then online status, then
    // membership age (oldest member first) — replaces an earlier
    // alphabetical-by-username tiebreaker. Usernames are now an anonymous
    // generated adjective_noun+suffix (see identity.generate_anonymous_username
    // on the backend) drawn from a shared word pool, so sorting by that
    // string just clustered whoever happened to draw the same adjective
    // together, which isn't a meaningful ordering for a roster.
    merged.sort((a, b) {
      final roleCompare =
          _rolePriority(a['role_id'] as String?).compareTo(_rolePriority(b['role_id'] as String?));
      if (roleCompare != 0) return roleCompare;

      if (a['is_in_call'] != b['is_in_call']) {
        return a['is_in_call'] == true ? -1 : 1;
      }

      if (a['is_online'] != b['is_online']) {
        return a['is_online'] == true ? -1 : 1;
      }

      final aJoined = DateTime.tryParse(a['joined_at'] as String? ?? '');
      final bJoined = DateTime.tryParse(b['joined_at'] as String? ?? '');
      if (aJoined == null && bJoined == null) return 0;
      if (aJoined == null) return 1;
      if (bJoined == null) return -1;
      return aJoined.compareTo(bJoined);
    });

    return merged;
  }

  /// Lower sorts first: organizer, then moderator, then member/null.
  static int _rolePriority(String? roleId) {
    switch (roleId) {
      case 'organizer':
        return 0;
      case 'moderator':
        return 1;
      default:
        return 2;
    }
  }

  Widget _buildDropdownSection({
    required String label,
    required IconData icon,
    required String value,
    required List<DropdownMenuItem<String>> items,
    required ValueChanged<String?> onChanged,
  }) {
    final validValue = items.any((item) => item.value == value)
        ? value
        : items.first.value;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: Colors.white54),
              const SizedBox(width: 6),
              Text(
                label,
                style: AppTypography.interTight(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.white70,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: const Color(0xFF1B1E26),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white12),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: validValue,
                isExpanded: true,
                dropdownColor: const Color(0xFF1B1E26),
                style: AppTypography.interTight(
                  fontSize: 12,
                  color: Colors.white,
                ),
                icon: const Icon(Icons.arrow_drop_down, color: Colors.white54),
                items: items,
                onChanged: onChanged,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInlineSettingsPanel(BuildContext context) {
    if (_isLoadingDevices) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white54),
      );
    }

    final videoDevices =
        _availableDevices.where((d) => d.kind == 'videoinput').toList();
    final audioInputDevices =
        _availableDevices.where((d) => d.kind == 'audioinput').toList();
    final audioOutputDevices =
        _availableDevices.where((d) => d.kind == 'audiooutput').toList();

    final cameraItems = videoDevices.isNotEmpty
        ? videoDevices.map((d) {
            return DropdownMenuItem(
              value: d.deviceId,
              child: Text(
                d.label.isNotEmpty
                    ? d.label
                    : 'Camera ${d.deviceId.substring(0, 5)}',
                overflow: TextOverflow.ellipsis,
              ),
            );
          }).toList()
        : const [
            DropdownMenuItem(
              value: 'Built-in Front Camera',
              child: Text('Built-in Front Camera'),
            ),
            DropdownMenuItem(
              value: 'Built-in Rear Camera',
              child: Text('Built-in Rear Camera'),
            ),
            DropdownMenuItem(
              value: 'External USB Cam Link (DSLR)',
              child: Text('External USB Cam Link (DSLR)'),
            ),
          ];

    final audioInputItems = audioInputDevices.isNotEmpty
        ? audioInputDevices.map((d) {
            return DropdownMenuItem(
              value: d.deviceId,
              child: Text(
                d.label.isNotEmpty
                    ? d.label
                    : 'Mic ${d.deviceId.substring(0, 5)}',
                overflow: TextOverflow.ellipsis,
              ),
            );
          }).toList()
        : const [
            DropdownMenuItem(
              value: 'Default Microphone',
              child: Text('Default Microphone'),
            ),
            DropdownMenuItem(
              value: 'USB Audio Interface / Mixer',
              child: Text('USB Audio Interface / Mixer'),
            ),
            DropdownMenuItem(
              value: 'Wireless Bluetooth Headset',
              child: Text('Wireless Bluetooth Headset'),
            ),
          ];

    final audioOutputItems = audioOutputDevices.isNotEmpty
        ? audioOutputDevices.map((d) {
            return DropdownMenuItem(
              value: d.deviceId,
              child: Text(
                d.label.isNotEmpty
                    ? d.label
                    : 'Speaker ${d.deviceId.substring(0, 5)}',
                overflow: TextOverflow.ellipsis,
              ),
            );
          }).toList()
        : const [
            DropdownMenuItem(
              value: 'Default Speaker',
              child: Text('Default Speaker'),
            ),
            DropdownMenuItem(
              value: 'Built-in Speaker / Headphones',
              child: Text('Built-in Speaker / Headphones'),
            ),
            DropdownMenuItem(
              value: 'Bluetooth Headset / AirPods',
              child: Text('Bluetooth Headset / AirPods'),
            ),
          ];

    final qualityItems = const [
      DropdownMenuItem(
        value: 'Auto (Adaptive HD)',
        child: Text('Auto (Adaptive HD)'),
      ),
      DropdownMenuItem(
        value: '1080p Full HD',
        child: Text('1080p Full HD'),
      ),
      DropdownMenuItem(
        value: '720p HD (Data Saver)',
        child: Text('720p HD (Data Saver)'),
      ),
      DropdownMenuItem(
        value: '480p SD',
        child: Text('480p SD'),
      ),
    ];

    return Align(
      alignment: Alignment.topCenter,
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            _buildDropdownSection(
              label: 'Camera Input',
              icon: Icons.videocam_rounded,
              value: _selectedCamera,
              items: cameraItems,
              onChanged: (val) async {
                if (val == null) return;
                setState(() => _selectedCamera = val);
                if (videoDevices.isEmpty) return;
                final ok = await MediaDeviceManager().switchCameraDevice(
                  ForumVideoStage.elementId,
                  val,
                );
                if (!context.mounted) return;
                if (!ok) {
                  AppSnackBars.showError(context, 'Could not switch camera.');
                }
              },
            ),
            _buildDropdownSection(
              label: 'Microphone Input',
              icon: Icons.mic_rounded,
              value: _selectedAudioInput,
              items: audioInputItems,
              onChanged: (val) async {
                if (val == null) return;
                setState(() => _selectedAudioInput = val);
                if (audioInputDevices.isEmpty) return;
                final ok = await MediaDeviceManager().switchAudioDevice(val);
                if (!context.mounted) return;
                if (!ok) {
                  AppSnackBars.showError(context, 'Could not switch microphone.');
                }
              },
            ),
            _buildDropdownSection(
              label: 'Audio Output',
              icon: Icons.volume_up_rounded,
              value: _selectedAudioOutput,
              items: audioOutputItems,
              onChanged: (val) async {
                if (val == null) return;
                setState(() => _selectedAudioOutput = val);
                if (audioOutputDevices.isEmpty) return;
                final ok = await MediaDeviceManager().switchAudioOutputDevice(
                  ForumVideoStage.elementId,
                  val,
                );
                if (!context.mounted) return;
                if (!ok) {
                  AppSnackBars.showError(context, 'Could not switch audio output.');
                }
              },
            ),
            _buildDropdownSection(
              label: 'Stream Quality Preset',
              icon: Icons.high_quality_rounded,
              value: _streamQuality,
              items: qualityItems,
              onChanged: (val) {
                if (val == null) return;
                setState(() => _streamQuality = val);
                final quality = switch (val) {
                  '1080p Full HD' => '1080p',
                  '720p HD (Data Saver)' => '720p',
                  '480p SD' => '480p',
                  _ => '720p',
                };
                ForumVideoStreamService().setStreamQuality(
                  ForumVideoStage.elementId,
                  quality,
                );
              },
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final roster = _cachedRoster;
    return Drawer(
      width: (MediaQuery.of(context).size.width * 0.85).clamp(280, 320),
      backgroundColor: Colors.black,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.only(topLeft: Radius.circular(40))),
      child: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 60,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[800],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const SizedBox(width: 40),
                  Text(
                    _showSettingsView
                        ? 'SETTINGS'
                        : 'MEMBERS (${roster.length})',
                    style: AppTypography.interTight(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      Icons.tune_rounded,
                      color: _showSettingsView
                          ? context.accentColor
                          : Colors.white70,
                      size: 20,
                    ),
                    tooltip: 'Settings',
                    onPressed: () {
                      if (!_showSettingsView) _loadAvailableDevices();
                      setState(() {
                        _showSettingsView = !_showSettingsView;
                      });
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                child: _showSettingsView
                    ? _buildInlineSettingsPanel(context)
                    : ParticipantList(
                        isLoading: widget.isLoading,
                        roster: roster,
                        isAudioLive: widget.isAudioLive,
                        isOrganizer: widget.isOrganizer,
                      ),
              ),
            ),
            // Persistent Bottom Section
            EventProgressTimeline(
              eventId: widget.eventId,
              eventProgress: widget.eventProgress,
              onEventProgressTap: widget.onEventProgressTap,
            ),
          ],
        ),
      ),
    );
  }
}

/// Renders member roster presence cards and audio/video participant controls.
class ParticipantList extends StatelessWidget {
  final bool isLoading;
  final List<Map<String, dynamic>> roster;
  final bool isAudioLive;
  final bool isOrganizer;

  const ParticipantList({
    super.key,
    required this.isLoading,
    required this.roster,
    required this.isAudioLive,
    required this.isOrganizer,
  });

  @override
  Widget build(BuildContext context) {
    ForumAudioStreamCubit? audioCubit;
    if (isAudioLive) {
      try {
        audioCubit = context.watch<ForumAudioStreamCubit>();
      } catch (_) {}
    }
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;

    return SkeletonFade(
      child: isLoading
          ? const SkeletonPresenceList(key: ValueKey('skeleton'))
          : ValueListenableBuilder<bool>(
              valueListenable: ForumVideoStreamService().isLiveNotifier,
              builder: (context, isVideoLive, _) {
                return ValueListenableBuilder<List<StreamParticipant>>(
                  valueListenable:
                      ForumVideoStreamService().activeParticipantsNotifier,
                  builder: (context, participants, _) {
                    return ListView.builder(
                      key: const ValueKey('content'),
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: roster.length,
                      itemBuilder: (context, index) {
                        try {
                          final user = roster[index];
                          final String userId = user['id'].toString();
                          if (userId.isEmpty) return const SizedBox.shrink();

                          final bool isSelf = userId == currentUserId;

                          final match = participants.firstWhere(
                            (p) =>
                                p.id == userId ||
                                (p.isHost && isSelf),
                            orElse: () => const StreamParticipant(
                                id: '', name: '', role: ''),
                          );

                          final userName = (user['user_name'] ?? 'Unknown').toString();
                          final bool isStreamActive =
                              match.id.isNotEmpty || isVideoLive || isAudioLive;

                          final mediaState = StreamParticipantService().resolveParticipantState(
                            userId: userId,
                            userName: userName,
                            currentUserId: currentUserId ?? '',
                            videoParticipant: match.id.isNotEmpty ? match : null,
                            audioCubit: isSelf ? audioCubit : null,
                            isStreamActive: isStreamActive,
                          );

                          return UserPresenceCard(
                            key: ValueKey('presence_$userId'),
                            userId: userId,
                            username: userName,
                            roleId: user['role_id'] as String?,
                            isOnline: user['is_online'] == true,
                            isOrganizer: user['is_organizer'] == true,
                            isViewerOrganizer: isOrganizer,
                            isPremium: user['is_premium'] == true,
                            showMicControl: isVideoLive || isAudioLive,
                            showCameraControl: isVideoLive,
                            isPrimary: isSelf,
                            isMicMuted: mediaState.isMicMuted,
                            isCameraOn: isStreamActive ? mediaState.isCameraOn : null,
                            onToggleMic: (id) {
                              StreamParticipantService().toggleMic(
                                userId: id,
                                currentUserId: currentUserId ?? '',
                                audioCubit: audioCubit,
                              );
                            },
                            onToggleCamera: (id) {
                              StreamParticipantService().toggleCamera(
                                userId: id,
                                currentUserId: currentUserId ?? '',
                              );
                            },
                          );
                        } catch (e) {
                          debugPrint(
                              '[PresenceDrawer] Error building user card: $e');
                          return const SizedBox.shrink();
                        }
                      },
                    );
                  },
                );
              },
            ),
    );
  }
}

/// Displays event progress bar and session progress indicator at drawer footer.
class EventProgressTimeline extends StatelessWidget {
  final String? eventId;
  final double eventProgress;
  final VoidCallback? onEventProgressTap;

  const EventProgressTimeline({
    super.key,
    required this.eventId,
    required this.eventProgress,
    this.onEventProgressTap,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Container(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Colors.white10)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () {
              if (eventId == null || eventId!.isEmpty) return;
              Navigator.of(context).pop();
              onEventProgressTap?.call();
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: 20, vertical: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                          (l10n?.eventProgress ?? 'Event Progress')
                              .toUpperCase(),
                          style: AppTypography.inter(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Colors.white54)),
                      const Icon(Icons.chevron_right,
                          color: Colors.white24, size: 16),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: eventProgress,
                      backgroundColor: Colors.white10,
                      valueColor: AlwaysStoppedAnimation<Color>(
                          context.accentColor),
                      minHeight: 8,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }
}
