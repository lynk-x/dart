import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lynk_core/core.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../cubit/ticket_validation_cubit.dart';
import '../cubit/ticket_validation_state.dart';
import 'web_qr_scanner.dart';
import 'package:lynk_x/presentation/shared/widgets/permission_request_sheet.dart';
import 'scan_history_drawer.dart';

enum ScanStatus {
  idle,
  scanning,
  processing,
  success,
  alreadyScanned,
  error,
}

enum FeedbackMode {
  sound,      // Sound + Vibration
  vibration,  // Vibration Only
  silent,     // Silent
}

class ScanHistoryItem {
  final String code;
  final String? attendeeName;
  final String? username;
  final ScanStatus status;
  final String? errorMessage;
  final DateTime timestamp;

  const ScanHistoryItem({
    required this.code,
    this.attendeeName,
    this.username,
    required this.status,
    this.errorMessage,
    required this.timestamp,
  });
}

class TicketScannerSheet extends StatefulWidget {
  final String eventId;
  final DateTime eventCreatedAt;

  const TicketScannerSheet({
    super.key,
    required this.eventId,
    required this.eventCreatedAt,
  });

  @override
  State<TicketScannerSheet> createState() => _TicketScannerSheetState();
}

class _TicketScannerSheetState extends State<TicketScannerSheet> {
  late final MobileScannerController? _controller;
  final TextEditingController _textController = TextEditingController();
  final AudioPlayer _audioPlayer = AudioPlayer();
  
  ScanStatus _status = ScanStatus.scanning;
  FeedbackMode _feedbackMode = FeedbackMode.sound;
  final List<ScanHistoryItem> _scanHistory = [];
  String? _attendeeName;
  String? _username;
  String? _tierName;
  String? _redeemedAt;
  String? _errorMessage;
  Timer? _resumeTimer;
  Timer? _syncTimer;

  bool _permissionAcknowledged = false;
  bool _vibrationPermissionAcknowledged = false;
  bool _torchEnabled = false;

  @override
  void initState() {
    super.initState();
    _loadFeedbackMode();
    _checkPermission();
    if (!kIsWeb) {
      _controller = MobileScannerController();
    } else {
      _controller = null;
    }

    // Auto-fetch tickets immediately and sync periodically every 30 seconds
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<TicketValidationCubit>().fetchTickets();
        _syncTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
          if (mounted) {
            context.read<TicketValidationCubit>().fetchTickets();
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _resumeTimer?.cancel();
    _syncTimer?.cancel();
    if (!kIsWeb) {
      _controller?.dispose();
    }
    _textController.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  Future<void> _loadFeedbackMode() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final modeName = prefs.getString('scanner_feedback_mode');
      final hasVibAcknowledged = prefs.getBool('vibration_permission_acknowledged') ?? false;
      if (mounted) {
        setState(() {
          _vibrationPermissionAcknowledged = hasVibAcknowledged;
          if (modeName != null) {
            final loadedMode = FeedbackMode.values.byName(modeName);
            if (loadedMode == FeedbackMode.vibration && !hasVibAcknowledged) {
              _feedbackMode = FeedbackMode.sound;
            } else {
              _feedbackMode = loadedMode;
            }
          }
        });
      }
    } catch (e) {
      debugPrint('[TicketScannerSheet] Error loading feedback mode: $e');
    }
  }

  Future<void> _checkPermission() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final hasAcknowledged = prefs.getBool('camera_permission_acknowledged') ?? false;
      if (mounted) {
        setState(() {
          _permissionAcknowledged = hasAcknowledged;
        });
      }

      if (!hasAcknowledged && mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _showPermissionSheet();
        });
      }
    } catch (e) {
      // SharedPreferences / state error
    }
  }

  void _showPermissionSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isDismissible: false,
      enableDrag: false,
      builder: (sheetContext) => PermissionRequestSheet(
        title: 'Ticket Scanner Access',
        description: 'To scan ticket QR codes, we need access to your device camera.',
        icon: Icons.camera_alt_rounded,
        actionLabel: 'Enable Camera',
        onGranted: () async {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setBool('camera_permission_acknowledged', true);
          if (mounted) {
            setState(() {
              _permissionAcknowledged = true;
            });
            _resetScanner();
          }
        },
      ),
    );
  }

  void _showVibrationPermissionSheet({
    required VoidCallback onGranted,
    required VoidCallback onDenied,
  }) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isDismissible: false,
      enableDrag: false,
      builder: (sheetContext) => PermissionRequestSheet(
        title: 'Vibration Alerts',
        description: 'To confirm ticket validation scans with haptic vibrations, we request permission to vibrate your device.',
        icon: Icons.vibration_rounded,
        actionLabel: 'Enable Vibration',
        onGranted: () async {
          try {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setBool('vibration_permission_acknowledged', true);
            if (mounted) {
              setState(() {
                _vibrationPermissionAcknowledged = true;
              });
              onGranted();
            }
          } catch (e) {
            // SharedPreferences error
          }
        },
        onDenied: onDenied,
      ),
    );
  }

  Future<void> _cycleFeedbackMode() async {
    final nextIndex = (_feedbackMode.index + 1) % FeedbackMode.values.length;
    final nextMode = FeedbackMode.values[nextIndex];

    if (nextMode == FeedbackMode.vibration && !_vibrationPermissionAcknowledged) {
      _showVibrationPermissionSheet(
        onGranted: () async {
          await _saveAndSetFeedbackMode(FeedbackMode.vibration);
          HapticFeedback.lightImpact();
        },
        onDenied: () async {
          // Fallback directly to the next mode after vibration, which is silent
          await _saveAndSetFeedbackMode(FeedbackMode.silent);
        },
      );
    } else {
      await _saveAndSetFeedbackMode(nextMode);
      if (nextMode != FeedbackMode.silent) {
        HapticFeedback.lightImpact();
      }
    }
  }

  Future<void> _saveAndSetFeedbackMode(FeedbackMode mode) async {
    setState(() {
      _feedbackMode = mode;
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('scanner_feedback_mode', mode.name);
    } catch (e) {
      debugPrint('[TicketScannerSheet] Error saving feedback mode: $e');
    }

    if (mounted) {
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            mode == FeedbackMode.sound
                ? 'Audio and Vibration Enabled'
                : mode == FeedbackMode.vibration
                    ? 'Vibration Only'
                    : 'Silent Mode Enabled',
          ),
          duration: const Duration(seconds: 1),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _toggleTorch() async {
    final nextState = !_torchEnabled;
    bool success = true;

    if (kIsWeb) {
      success = await toggleWebTorch(nextState);
    } else {
      if (_controller != null) {
        try {
          await _controller.toggleTorch();
          success = true;
        } catch (e) {
          success = false;
        }
      } else {
        success = false;
      }
    }

    if (!success) {
      if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Flashlight is not supported on this device/browser'),
            duration: Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.redAccent,
          ),
        );
      }
      return;
    }

    if (mounted) {
      setState(() {
        _torchEnabled = nextState;
      });
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_torchEnabled ? 'Flashlight ON' : 'Flashlight OFF'),
          duration: const Duration(seconds: 1),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _switchCamera() async {
    bool success = false;
    if (kIsWeb) {
      success = await switchWebCamera();
    } else {
      if (_controller != null) {
        await _controller.switchCamera();
        success = true;
      }
    }
    if (success && mounted) {
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Switched camera source'),
          duration: Duration(seconds: 1),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _resetScanner() {
    _resumeTimer?.cancel();
    if (mounted) {
      setState(() {
        _status = ScanStatus.scanning;
        _attendeeName = null;
        _username = null;
        _tierName = null;
        _redeemedAt = null;
        _errorMessage = null;
        _textController.clear();
      });
      if (!kIsWeb && _permissionAcknowledged) {
        _controller?.start();
      }
    }
  }

  void _triggerFeedback({required bool isSuccess}) {
    if (_feedbackMode == FeedbackMode.silent) return;

    if (isSuccess) {
      if (_feedbackMode == FeedbackMode.sound) {
        _audioPlayer.play(AssetSource('audio/success.mp3'));
      }
      HapticFeedback.lightImpact();
    } else {
      if (_feedbackMode == FeedbackMode.sound) {
        _audioPlayer.play(AssetSource('audio/error.mp3'));
      }
      HapticFeedback.heavyImpact();
    }
  }

  Future<void> _processTicketCode(String code) async {
    if (_status != ScanStatus.scanning) return;

    setState(() {
      _status = ScanStatus.processing;
    });

    if (_feedbackMode != FeedbackMode.silent) {
      HapticFeedback.mediumImpact();
    }

    try {
      final validationCubit = context.read<TicketValidationCubit>();
      final result = await validationCubit.scanTicketOffline(
        code,
        scannerUserId: Supabase.instance.client.auth.currentUser?.id,
      );

      final bool success = result['success'] == true;

      final status = success
          ? ScanStatus.success
          : ((result['error']?.toString() ?? '').toLowerCase().contains('already')
              ? ScanStatus.alreadyScanned
              : ScanStatus.error);

      final item = ScanHistoryItem(
        code: code,
        attendeeName: result['attendee_name']?.toString(),
        username: result['username']?.toString(),
        status: status,
        errorMessage: success ? null : (result['error']?.toString() ?? 'Unknown error'),
        timestamp: DateTime.now(),
      );

      if (success) {
        _triggerFeedback(isSuccess: true);
        if (mounted) {
          setState(() {
            _status = ScanStatus.success;
            _attendeeName = result['attendee_name']?.toString();
            _username = result['username']?.toString();
            _tierName = result['tier_name']?.toString();
            _scanHistory.insert(0, item);
          });
        }
      } else {
        _triggerFeedback(isSuccess: false);
        final String err = result['error']?.toString() ?? 'Unknown error';
        if (mounted) {
          setState(() {
            if (err.toLowerCase().contains('already checked in') || err.toLowerCase().contains('already scanned')) {
              _status = ScanStatus.alreadyScanned;
              _attendeeName = result['attendee_name']?.toString();
              _redeemedAt = result['redeemed_at']?.toString();
            } else {
              _status = ScanStatus.error;
              _errorMessage = err;
            }
            _scanHistory.insert(0, item);
          });
        }
      }
    } catch (e) {
      _triggerFeedback(isSuccess: false);
      final item = ScanHistoryItem(
        code: code,
        status: ScanStatus.error,
        errorMessage: e.toString(),
        timestamp: DateTime.now(),
      );
      if (mounted) {
        setState(() {
          _status = ScanStatus.error;
          _errorMessage = e.toString();
          _scanHistory.insert(0, item);
        });
      }
    }

    // Auto-resume scanning after 3 seconds
    _resumeTimer = Timer(const Duration(milliseconds: 3000), () {
      _resetScanner();
    });
  }

  String _formatTime(DateTime? dt) {
    if (dt == null) return 'Never';
    final hour = dt.hour.toString().padLeft(2, '0');
    final minute = dt.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return BlocBuilder<TicketValidationCubit, TicketValidationState>(
      builder: (context, state) {
        return Scaffold(
          backgroundColor: Colors.black,
          endDrawer: ScanHistoryDrawer(
            history: _scanHistory,
            onClearHistory: () {
              setState(() {
                _scanHistory.clear();
              });
              if (Navigator.canPop(context)) {
                Navigator.pop(context); // Close the drawer
              }
              ScaffoldMessenger.of(context).clearSnackBars();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Scan history cleared'),
                  duration: Duration(seconds: 1),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
          ),
          appBar: AppBar(
            backgroundColor: Colors.black,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_rounded, color: Colors.white, size: 32),
              onPressed: () => Navigator.pop(context),
            ),
            titleSpacing: 0,
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Ticket Scanner',
                  style: AppTypography.interTight(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: state.error != null ? Colors.orange : Colors.green,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'tickets: ${state.tickets.length} • Last updated: ${_formatTime(state.lastSyncedAt)}',
                      style: AppTypography.inter(
                        fontSize: 11,
                        color: Colors.white60,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            actions: [
              if (state.isLoading)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Center(
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white70,
                      ),
                    ),
                  ),
                ),
              Builder(
                builder: (context) => IconButton(
                  icon: const Icon(Icons.groups, color: Colors.white, size: 32),
                  onPressed: () {
                    Scaffold.of(context).openEndDrawer();
                  },
                ),
              ),
            ],
          ),
          body: Stack(
            children: [
              // 1. Camera Feed / Native Scanner (Full screen background)
              if (_status == ScanStatus.scanning || _status == ScanStatus.processing)
                Positioned.fill(
                  child: !_permissionAcknowledged
                      ? Container(
                          color: Colors.black87,
                          child: Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(
                                  Icons.camera_alt_rounded,
                                  color: Colors.white30,
                                  size: 48,
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'Camera Access Required',
                                  style: AppTypography.inter(
                                    color: Colors.white70,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Enable camera to start scanning tickets.',
                                  style: AppTypography.inter(
                                    color: Colors.white38,
                                    fontSize: 12,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 16),
                                TextButton(
                                  onPressed: _showPermissionSheet,
                                  style: TextButton.styleFrom(
                                    backgroundColor: context.accentColor,
                                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                  child: Text(
                                    'Enable Camera',
                                    style: AppTypography.inter(
                                      color: Colors.black,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      : (kIsWeb
                          ? WebQrScanner(
                              torchEnabled: _torchEnabled,
                              onDetect: (code) {
                                _processTicketCode(code);
                              },
                            )
                          : MobileScanner(
                              controller: _controller!,
                              onDetect: (capture) {
                                final List<Barcode> barcodes = capture.barcodes;
                                if (barcodes.isNotEmpty) {
                                  final String? code = barcodes.first.rawValue;
                                  if (code != null && code.isNotEmpty) {
                                    _processTicketCode(code);
                                  }
                                }
                              },
                            )),
                ),

              // 2. Stylized Barcode Overlay Guide (Translucent vertical barcode stripes)
              if (_status == ScanStatus.scanning && _permissionAcknowledged)
                Center(
                  child: Opacity(
                    opacity: 0.18, // Subtly translucent as seen in reference image
                    child: SizedBox(
                      width: 260,
                      height: 70,
                      child: CustomPaint(
                        painter: BarcodeGuidePainter(),
                      ),
                    ),
                  ),
                ),

              // 4. Result Overlays (Full screen success/error)
              if (_status == ScanStatus.processing)
                Positioned.fill(
                  child: Container(
                    color: Colors.black54,
                    child: const Center(
                      child: CircularProgressIndicator(color: Colors.white),
                    ),
                  ),
                ),

              if (_status == ScanStatus.success)
                Positioned.fill(
                  child: _buildResultCard(
                    color: const Color(0xFF2E7D32),
                    icon: Icons.check_circle_outline_rounded,
                    title: 'TICKET VALIDATED',
                    subtitle: _attendeeName ?? 'Valid Attendee',
                    extra: 'Username: ${_username ?? "N/A"}\nTier: ${_tierName ?? "General Admission"}',
                  ),
                ),

              if (_status == ScanStatus.alreadyScanned)
                Positioned.fill(
                  child: _buildResultCard(
                    color: const Color(0xFFC62828),
                    icon: Icons.error_outline_rounded,
                    title: 'ALREADY REDEEMED',
                    subtitle: _attendeeName ?? 'Attendee',
                    extra: _redeemedAt != null
                        ? 'Redeemed at: ${_formatTime(DateTime.tryParse(_redeemedAt!))}'
                        : 'This ticket was already used.',
                  ),
                ),

              if (_status == ScanStatus.error)
                Positioned.fill(
                  child: _buildResultCard(
                    color: const Color(0xFFD84315),
                    icon: Icons.warning_amber_rounded,
                    title: 'INVALID TICKET',
                    subtitle: _errorMessage ?? 'Verification Failed',
                    extra: 'Please verify the ticket code or check attendee permissions.',
                  ),
                ),

              // 5. Floating Control Panel (Top-Right, vertical column)
              if (_status == ScanStatus.scanning && _permissionAcknowledged)
                Positioned(
                  top: 16,
                  right: 16,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Torch Toggle Button (Lightning bolt)
                      _buildFloatingActionButton(
                        icon: Icon(
                          Icons.flash_on,
                          color: _torchEnabled ? context.accentColor : Colors.white70,
                          size: 24,
                        ),
                        onPressed: _toggleTorch,
                        tooltip: 'Toggle Flashlight',
                      ),
                      const SizedBox(height: 12),
                      // Feedback Toggle Button (Volume / Vibration / Off)
                      _buildFloatingActionButton(
                        icon: Icon(
                          _feedbackMode == FeedbackMode.sound
                              ? Icons.volume_up_rounded
                              : _feedbackMode == FeedbackMode.vibration
                                  ? Icons.vibration_rounded
                                  : Icons.volume_off_rounded,
                          color: Colors.white70,
                          size: 22,
                        ),
                        onPressed: _cycleFeedbackMode,
                        tooltip: 'Feedback Mode: ${_feedbackMode.name}',
                      ),
                      const SizedBox(height: 12),
                      // Switch Camera Button
                      _buildFloatingActionButton(
                        icon: const Icon(
                          Icons.flip_camera_ios_rounded,
                          color: Colors.white70,
                          size: 22,
                        ),
                        onPressed: _switchCamera,
                        tooltip: 'Switch Camera',
                      ),
                    ],
                  ),
                ),

              // 6. Manual Entry Panel at the bottom
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: SafeArea(
                  child: Padding(
                    padding: EdgeInsets.only(
                      left: 16,
                      right: 16,
                      bottom: bottomInset > 0 ? bottomInset + 8 : 16,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_status != ScanStatus.scanning && _status != ScanStatus.processing) ...[
                          TextButton.icon(
                            onPressed: _resetScanner,
                            icon: const Icon(Icons.refresh_rounded, color: Colors.black),
                            label: Text(
                              'Scan Next Ticket',
                              style: AppTypography.inter(
                                color: Colors.black,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            style: TextButton.styleFrom(
                              backgroundColor: context.accentColor,
                              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],
                        // Manual Entry Form
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: const Color(0xFF121212),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.white10),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'Manual Entry',
                                style: AppTypography.interTight(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white70,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Expanded(
                                    child: TextField(
                                      controller: _textController,
                                      style: const TextStyle(color: Colors.white),
                                      decoration: InputDecoration(
                                        hintText: 'Enter ticket code...',
                                        hintStyle: const TextStyle(color: Colors.white38),
                                        filled: true,
                                        fillColor: Colors.black,
                                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(12),
                                          borderSide: BorderSide.none,
                                        ),
                                      ),
                                      onSubmitted: (val) {
                                        if (val.trim().isNotEmpty) {
                                          _processTicketCode(val.trim());
                                        }
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  InkWell(
                                    onTap: () {
                                      final val = _textController.text.trim();
                                      if (val.isNotEmpty) {
                                        _processTicketCode(val);
                                      }
                                    },
                                    borderRadius: BorderRadius.circular(12),
                                    child: Container(
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: context.accentColor,
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: const Icon(Icons.arrow_forward_rounded, color: Colors.black),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildResultCard({
    required Color color,
    required IconData icon,
    required String title,
    required String subtitle,
    required String extra,
  }) {
    return Container(
      width: double.infinity,
      height: double.infinity,
      color: color,
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 72, color: Colors.white),
          const SizedBox(height: 16),
          Text(
            title,
            style: AppTypography.interTight(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: Colors.white,
              letterSpacing: 1.2,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: AppTypography.inter(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Text(
            extra,
            style: AppTypography.inter(
              fontSize: 14,
              color: Colors.white.withValues(alpha: 0.8),
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          Text(
            'Resuming in a few seconds...',
            style: AppTypography.inter(
              fontSize: 12,
              color: Colors.white.withValues(alpha: 0.5),
            ).copyWith(fontStyle: FontStyle.italic),
          ),
        ],
      ),
    );
  }

  Widget _buildFloatingActionButton({
    required Widget icon,
    required VoidCallback? onPressed,
    required String tooltip,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(28),
        child: Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.65),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white24, width: 1.5),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 8,
                spreadRadius: 1,
              ),
            ],
          ),
          child: Center(child: icon),
        ),
      ),
    );
  }
}

class BarcodeGuidePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    // Pattern representing custom bar widths and gaps
    final bars = [
      _Bar(width: 4, space: 6),
      _Bar(width: 10, space: 8),
      _Bar(width: 4, space: 10),
      _Bar(width: 16, space: 8),
      _Bar(width: 4, space: 6),
      _Bar(width: 12, space: 10),
      _Bar(width: 4, space: 8),
      _Bar(width: 18, space: 6),
      _Bar(width: 4, space: 10),
      _Bar(width: 12, space: 8),
      _Bar(width: 6, space: 6),
      _Bar(width: 14, space: 0),
    ];

    // Compute total width of the pattern to center it horizontally
    double totalWidth = 0;
    for (int i = 0; i < bars.length; i++) {
      totalWidth += bars[i].width;
      if (i < bars.length - 1) {
        totalWidth += bars[i].space;
      }
    }

    // Centering offset
    double startX = (size.width - totalWidth) / 2;

    for (int i = 0; i < bars.length; i++) {
      final bar = bars[i];
      canvas.drawRect(
        Rect.fromLTWH(startX, 0, bar.width, size.height),
        paint,
      );
      startX += bar.width + bar.space;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _Bar {
  final double width;
  final double space;
  const _Bar({required this.width, required this.space});
}
