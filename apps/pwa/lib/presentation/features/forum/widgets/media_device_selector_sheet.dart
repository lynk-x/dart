import 'package:flutter/material.dart';
import 'package:lynk_core/core.dart';
import '../services/stream_service.dart';

/// Opens a modal bottom sheet allowing users to select hardware audio/video devices and stream resolution.
void showMediaDeviceSelectorSheet(BuildContext context) {
  ForumVideoStreamService().getAvailableDevices().then((devices) {
    if (!context.mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF121418),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        String selectedCamera = 'Built-in Front Camera';
        String selectedAudioInput = 'Default Microphone';
        String selectedAudioOutput = 'Default Speaker';
        String streamQuality = 'Auto (Adaptive HD)';

        return StatefulBuilder(
          builder: (context, setModalState) {
            final videoDevices =
                devices.where((d) => d.kind == 'videoinput').toList();
            final audioInputDevices =
                devices.where((d) => d.kind == 'audioinput').toList();
            final audioOutputDevices =
                devices.where((d) => d.kind == 'audiooutput').toList();

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

            final selectedCamVal =
                cameraItems.any((item) => item.value == selectedCamera)
                    ? selectedCamera
                    : cameraItems.first.value;

            final selectedAudioVal =
                audioInputItems.any((item) => item.value == selectedAudioInput)
                    ? selectedAudioInput
                    : audioInputItems.first.value;

            final selectedOutputVal = audioOutputItems
                    .any((item) => item.value == selectedAudioOutput)
                ? selectedAudioOutput
                : audioOutputItems.first.value;

            return SafeArea(
              child: Padding(
                padding: EdgeInsets.only(
                  left: 20,
                  right: 20,
                  top: 20,
                  bottom: MediaQuery.of(context).viewInsets.bottom + 16,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Settings',
                          style: AppTypography.interTight(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.white54),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Flexible(
                      child: SingleChildScrollView(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildDropdownRow(
                              context,
                              label: 'Camera Device',
                              icon: Icons.videocam_rounded,
                              value: selectedCamVal,
                              items: cameraItems,
                              onChanged: (val) {
                                if (val != null) {
                                  setModalState(() => selectedCamera = val);
                                }
                              },
                            ),
                            const SizedBox(height: 12),
                            _buildDropdownRow(
                              context,
                              label: 'Microphone Input',
                              icon: Icons.mic_rounded,
                              value: selectedAudioVal,
                              items: audioInputItems,
                              onChanged: (val) {
                                if (val != null) {
                                  setModalState(() => selectedAudioInput = val);
                                }
                              },
                            ),
                            const SizedBox(height: 12),
                            _buildDropdownRow(
                              context,
                              label: 'Audio Output',
                              icon: Icons.volume_up_rounded,
                              value: selectedOutputVal,
                              items: audioOutputItems,
                              onChanged: (val) {
                                if (val != null) {
                                  setModalState(() => selectedAudioOutput = val);
                                }
                              },
                            ),
                            const SizedBox(height: 12),
                            _buildDropdownRow(
                              context,
                              label: 'Stream Resolution',
                              icon: Icons.high_quality_rounded,
                              value: streamQuality,
                              items: qualityItems,
                              onChanged: (val) {
                                if (val != null) {
                                  setModalState(() => streamQuality = val);
                                }
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(context),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: context.accentColor,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text(
                          'Apply Settings',
                          style: AppTypography.interTight(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: Colors.black,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  });
}

Widget _buildDropdownRow<T>(
  BuildContext context, {
  required String label,
  required IconData icon,
  required T? value,
  required List<DropdownMenuItem<T>> items,
  required ValueChanged<T?> onChanged,
}) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Icon(icon, size: 16, color: context.accentColor),
          const SizedBox(width: 6),
          Text(
            label,
            style: AppTypography.interTight(
              fontSize: 13,
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
          color: const Color(0xFF1E222A),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white12),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<T>(
            value: value,
            items: items,
            onChanged: onChanged,
            dropdownColor: const Color(0xFF1E222A),
            style: AppTypography.interTight(color: Colors.white, fontSize: 13),
            isExpanded: true,
            icon: const Icon(Icons.arrow_drop_down, color: Colors.white54),
          ),
        ),
      ),
    ],
  );
}
