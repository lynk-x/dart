import 'dart:async';
import 'package:flutter/material.dart';
import 'package:lynk_core/core.dart';

/// Interactive Live Stream screen for hosts and attendees.
class LiveStreamScreen extends StatefulWidget {
  final String forumName;
  final String hostName;
  final bool isHost;

  const LiveStreamScreen({
    super.key,
    this.forumName = 'Community Live Stream',
    this.hostName = 'Alex',
    this.isHost = true,
  });

  @override
  State<LiveStreamScreen> createState() => _LiveStreamScreenState();
}

class _LiveStreamScreenState extends State<LiveStreamScreen> {
  bool _isMicMuted = false;
  bool _isCameraOn = true;
  bool _isFrontCamera = true;
  bool _isHandRaised = false;
  bool _showChatOverlay = false;
  int _spectatorCount = 142;
  String _selectedCamera = 'Built-in Front Camera';
  String _selectedAudioInput = 'Default Microphone';

  Timer? _spectatorTimer;

  @override
  void initState() {
    super.initState();
    _startSpectatorSimulation();
  }

  void _startSpectatorSimulation() {
    _spectatorTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!mounted) return;
      setState(() {
        _spectatorCount += (1 - (DateTime.now().second % 3));
      });
    });
  }

  @override
  void dispose() {
    _spectatorTimer?.cancel();
    super.dispose();
  }

  void _showDeviceSelectorModal() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF121418),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Media Device Settings',
                    style: AppTypography.interTight(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Camera Input',
                    style: AppTypography.interTight(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.white70,
                    ),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: _selectedCamera,
                    dropdownColor: const Color(0xFF1E222A),
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.06),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    items: const [
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
                    ],
                    onChanged: (val) {
                      if (val != null) {
                        setModalState(() => _selectedCamera = val);
                        setState(() => _selectedCamera = val);
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Microphone Input',
                    style: AppTypography.interTight(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.white70,
                    ),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: _selectedAudioInput,
                    dropdownColor: const Color(0xFF1E222A),
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.06),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    items: const [
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
                    ],
                    onChanged: (val) {
                      if (val != null) {
                        setModalState(() => _selectedAudioInput = val);
                        setState(() => _selectedAudioInput = val);
                      }
                    },
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            // 1. VIDEO CANVAS STAGE
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF0F1115),
                  image: _isCameraOn
                      ? null
                      : const DecorationImage(
                          image: AssetImage('assets/images/lynk-x_logo.png'),
                          opacity: 0.15,
                          fit: BoxFit.contain,
                        ),
                ),
                child: Center(
                  child: _isCameraOn
                      ? Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              width: 96,
                              height: 96,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: context.accentColor.withValues(alpha: 0.2),
                                border: Border.all(color: context.accentColor, width: 2),
                              ),
                              child: const Icon(
                                Icons.videocam_rounded,
                                color: Colors.white,
                                size: 48,
                              ),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Live Stream Feed',
                              style: AppTypography.interTight(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Active Camera: $_selectedCamera',
                              style: AppTypography.interTight(
                                fontSize: 12,
                                color: Colors.white54,
                              ),
                            ),
                          ],
                        )
                      : Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.videocam_off_rounded,
                              color: Colors.white38,
                              size: 56,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Camera Turned Off',
                              style: AppTypography.interTight(
                                fontSize: 16,
                                color: Colors.white54,
                              ),
                            ),
                          ],
                        ),
                ),
              ),
            ),

            // Speaker Tag Overlay at Bottom-Left of Canvas
            Positioned(
              left: 16,
              bottom: 96,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _isMicMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
                      color: _isMicMuted ? Colors.redAccent : context.accentColor,
                      size: 16,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '${widget.hostName} (Host)',
                      style: AppTypography.interTight(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // 2. TOP BAR OVERLAY
            Positioned(
              top: 12,
              left: 16,
              right: 16,
              child: Row(
                children: [
                  // Collapse / PiP Action Button
                  InkWell(
                    onTap: () => Navigator.of(context).pop(),
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.5),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.picture_in_picture_alt_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  ),

                  const Spacer(),

                  // Live Telemetry Pill
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: Colors.redAccent,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'LIVE',
                          style: AppTypography.interTight(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Colors.redAccent,
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Icon(
                          Icons.visibility_rounded,
                          color: Colors.white70,
                          size: 14,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '$_spectatorCount',
                          style: AppTypography.interTight(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const Spacer(),

                  // Settings / Device Selector Button
                  InkWell(
                    onTap: _showDeviceSelectorModal,
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.5),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.tune_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // 3. BOTTOM FLOATING CONTROL DOCK
            Positioned(
              left: 20,
              right: 20,
              bottom: 20,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFF161920).withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(32),
                  border: Border.all(color: Colors.white12),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black45,
                      blurRadius: 16,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    // Position 1: Chat Toggle
                    IconButton(
                      icon: Icon(
                        _showChatOverlay
                            ? Icons.chat_bubble_rounded
                            : Icons.chat_bubble_outline_rounded,
                        color: _showChatOverlay ? context.accentColor : Colors.white,
                      ),
                      onPressed: () {
                        setState(() => _showChatOverlay = !_showChatOverlay);
                      },
                      tooltip: 'Toggle Live Chat',
                    ),

                    // Position 2: Mic Toggle
                    IconButton(
                      icon: Icon(
                        _isMicMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
                        color: _isMicMuted ? Colors.redAccent : Colors.white,
                      ),
                      onPressed: () {
                        setState(() => _isMicMuted = !_isMicMuted);
                      },
                      tooltip: _isMicMuted ? 'Unmute Mic' : 'Mute Mic',
                    ),

                    // Position 3: Center Red End Broadcast Button
                    InkWell(
                      onTap: () => Navigator.of(context).pop(),
                      borderRadius: BorderRadius.circular(28),
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: const BoxDecoration(
                          color: Colors.redAccent,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.call_end_rounded,
                          color: Colors.white,
                          size: 24,
                        ),
                      ),
                    ),

                    // Position 4: Camera Toggle
                    IconButton(
                      icon: Icon(
                        _isCameraOn ? Icons.videocam_rounded : Icons.videocam_off_rounded,
                        color: _isCameraOn ? Colors.white : Colors.redAccent,
                      ),
                      onPressed: () {
                        setState(() => _isCameraOn = !_isCameraOn);
                      },
                      tooltip: _isCameraOn ? 'Turn Camera Off' : 'Turn Camera On',
                    ),

                    // Position 5: Flip Camera
                    IconButton(
                      icon: Icon(
                        Icons.flip_camera_ios_rounded,
                        color: _isFrontCamera ? Colors.white : context.accentColor,
                      ),
                      onPressed: () {
                        setState(() => _isFrontCamera = !_isFrontCamera);
                      },
                      tooltip: 'Flip Camera',
                    ),

                    // Position 6: Raise Hand
                    IconButton(
                      icon: Icon(
                        _isHandRaised ? Icons.front_hand_rounded : Icons.front_hand_outlined,
                        color: _isHandRaised ? Colors.amberAccent : Colors.white70,
                      ),
                      onPressed: () {
                        setState(() => _isHandRaised = !_isHandRaised);
                      },
                      tooltip: 'Raise Hand',
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
