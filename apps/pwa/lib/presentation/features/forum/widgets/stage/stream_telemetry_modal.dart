import 'package:flutter/material.dart';
import 'package:lynk_core/core.dart';
import '../../services/stream_service.dart';

/// Modal dialog displaying live video stream telemetry and diagnostics.
class StageTelemetryModal {
  static void show(
    BuildContext context, {
    required ForumVideoStreamService videoService,
    required int sessionDurationSeconds,
    required String Function(int) formatDuration,
  }) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF121418),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return ValueListenableBuilder<TelemetryData>(
          valueListenable: videoService.telemetryNotifier,
          builder: (context, telemetry, _) {
            return Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.analytics_rounded, color: context.accentColor, size: 22),
                      const SizedBox(width: 8),
                      Text(
                        'Stream Diagnostics & Telemetry',
                        style: AppTypography.interTight(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white70),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _buildTelemetryRow('Session Uptime', formatDuration(sessionDurationSeconds), Icons.timer_outlined),
                  _buildTelemetryRow('Network Latency', '${telemetry.rttMs} ms (RTT Edge)', Icons.speed_rounded),
                  _buildTelemetryRow('Video Resolution', '${telemetry.height}p (${telemetry.width}x${telemetry.height} @ ${telemetry.fps} FPS)', Icons.hd_rounded),
                  _buildTelemetryRow('Video Bitrate', '${telemetry.bitrateMbps} Mbps (${telemetry.codec})', Icons.graphic_eq_rounded),
                  _buildTelemetryRow('Audio Bitrate', '128 kbps (Opus 48kHz Stereo)', Icons.mic_outlined),
                  _buildTelemetryRow('Packet Loss', '${telemetry.packetLossPercent}%', Icons.network_check_rounded),
                  _buildTelemetryRow('Stream Security', 'DTLS-SRTP (End-to-End Encrypted)', Icons.lock_outline_rounded),
                  const SizedBox(height: 16),
                ],
              ),
            );
          },
        );
      },
    );
  }

  static Widget _buildTelemetryRow(String label, String value, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: [
          Icon(icon, color: Colors.white54, size: 16),
          const SizedBox(width: 10),
          Text(
            label,
            style: AppTypography.interTight(
              fontSize: 13,
              color: Colors.white70,
            ),
          ),
          const Spacer(),
          Text(
            value,
            style: AppTypography.interTight(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}
