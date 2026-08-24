import 'package:flutter/material.dart';
import 'package:lynk_core/core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:lynk_x/l10n/app_localizations.dart';
import '../services/forum_video_stream_service.dart';
import 'forum_skeletons.dart';
import 'user_presence.dart';

/// The end-drawer component for the Forum screen.
///
/// Displays the list of online members (using [UserPresenceCard]) or toggles inline
/// to the Hardware & Stream Settings panel (Option B), retaining full video canvas visibility.
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

  String _selectedCamera = 'Built-in Front Camera';
  String _selectedAudioInput = 'Default Microphone';
  String _selectedAudioOutput = 'Default Speaker';
  String _streamQuality = 'Auto (Adaptive HD)';

  @override
  void initState() {
    super.initState();
    _loadAvailableDevices();
  }

  Future<void> _loadAvailableDevices() async {
    setState(() {
      _isLoadingDevices = true;
    });
    final devices = await ForumVideoStreamService().getAvailableDevices();
    if (mounted) {
      setState(() {
        _availableDevices = devices;
        _isLoadingDevices = false;
      });
    }
  }

  /// Merges the full member roster with live presence, keyed by user id.
  List<Map<String, dynamic>> _mergedRoster() {
    final onlineById = <String, Map<String, dynamic>>{};
    for (final u in widget.onlineUsers) {
      final id = (u['user_id'] ?? u['id'] ?? '').toString();
      if (id.isNotEmpty) onlineById[id] = u;
    }

    final seen = <String>{};
    final merged = <Map<String, dynamic>>[];

    for (final m in widget.members) {
      final id = (m['id'] ?? '').toString();
      if (id.isEmpty) continue;
      seen.add(id);
      final online = onlineById[id];
      merged.add({
        'id': id,
        'user_name':
            online?['user_name'] ?? online?['full_name'] ?? m['user_name'],
        'role_id': m['role_id'],
        'is_organizer': online?['is_organizer'] ?? m['is_organizer'] == true,
        'is_premium': m['is_premium'] == true,
        'is_online': online != null,
      });
    }

    for (final u in widget.onlineUsers) {
      final id = (u['user_id'] ?? u['id'] ?? '').toString();
      if (id.isEmpty || seen.contains(id)) continue;
      merged.add({
        'id': id,
        'user_name': u['user_name'] ?? u['full_name'] ?? 'Unknown',
        'role_id': u['is_organizer'] == true ? 'organizer' : null,
        'is_organizer': u['is_organizer'] == true,
        'is_premium': u['is_premium'] == true,
        'is_online': true,
      });
    }

    merged.sort((a, b) {
      if (a['is_online'] != b['is_online']) {
        return a['is_online'] == true ? -1 : 1;
      }
      return (a['user_name'] as String)
          .toLowerCase()
          .compareTo((b['user_name'] as String).toLowerCase());
    });

    return merged;
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
              onChanged: (val) {
                if (val != null) setState(() => _selectedCamera = val);
              },
            ),
            _buildDropdownSection(
              label: 'Microphone Input',
              icon: Icons.mic_rounded,
              value: _selectedAudioInput,
              items: audioInputItems,
              onChanged: (val) {
                if (val != null) setState(() => _selectedAudioInput = val);
              },
            ),
            _buildDropdownSection(
              label: 'Audio Output',
              icon: Icons.volume_up_rounded,
              value: _selectedAudioOutput,
              items: audioOutputItems,
              onChanged: (val) {
                if (val != null) setState(() => _selectedAudioOutput = val);
              },
            ),
            _buildDropdownSection(
              label: 'Stream Quality Preset',
              icon: Icons.high_quality_rounded,
              value: _streamQuality,
              items: qualityItems,
              onChanged: (val) {
                if (val != null) setState(() => _streamQuality = val);
              },
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildParticipantRoster(
      BuildContext context, List<Map<String, dynamic>> roster) {
    return SkeletonFade(
      child: widget.isLoading
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

                          final match = participants.firstWhere(
                            (p) =>
                                p.id == userId ||
                                (p.isHost &&
                                    p.id == 'host' &&
                                    userId ==
                                        Supabase.instance.client.auth.currentUser
                                            ?.id),
                            orElse: () => const StreamParticipant(
                                id: '', name: '', role: ''),
                          );

                          final bool isStreamActive = match.id.isNotEmpty;

                          return UserPresenceCard(
                            key: ValueKey('presence_$userId'),
                            userId: userId,
                            username:
                                (user['user_name'] ?? 'Unknown').toString(),
                            roleId: user['role_id'] as String?,
                            isOnline: user['is_online'] == true,
                            isOrganizer: user['is_organizer'] == true,
                            isPremium: user['is_premium'] == true,
                            showMicControl: isVideoLive || widget.isAudioLive,
                            showCameraControl: isVideoLive,
                            isPrimary: userId ==
                                Supabase
                                    .instance.client.auth.currentUser?.id,
                            isMicMuted: isStreamActive ? match.isMicMuted : null,
                            isCameraOn: isStreamActive ? match.isCameraOn : null,
                            onToggleMic: (id) => ForumVideoStreamService()
                                .toggleParticipantMic(id),
                            onToggleCamera: (id) => ForumVideoStreamService()
                                .toggleParticipantCamera(id),
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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final roster = _mergedRoster();
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
                    : _buildParticipantRoster(context, roster),
              ),
            ),
            // Persistent Bottom Section
            Container(
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: Colors.white10)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  InkWell(
                    onTap: () {
                      if (widget.eventId == null || widget.eventId!.isEmpty) return;
                      Navigator.of(context).pop();
                      widget.onEventProgressTap?.call();
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
                              value: widget.eventProgress,
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
            ),
          ],
        ),
      ),
    );
  }
}
