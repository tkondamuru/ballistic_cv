import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import '../models/sampled_object.dart';

class ActivitiesScreen extends StatelessWidget {
  final List<CameraDescription> cameras;
  final SampledObject object;
  final VoidCallback onTrack;
  final VoidCallback onThud;
  final String? selectedActivity;

  const ActivitiesScreen({
    super.key,
    required this.cameras,
    required this.object,
    required this.onTrack,
    required this.onThud,
    this.selectedActivity,
  });

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Your activities')),
    body: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Tracking Activity Card
          Card(
            color: selectedActivity == 'tracking'
                ? const Color(0xFFDCFCE7)
                : const Color(0xFFF1F5F9),
            surfaceTintColor: Colors.transparent,
            child: ListTile(
              textColor: const Color(0xFF111827),
              iconColor: const Color(0xFF334155),
              subtitleTextStyle: const TextStyle(
                color: Color(0xFF475569),
                fontSize: 14,
              ),
              leading: const Icon(Icons.motion_photos_on),
              title: const Text('Tracking'),
              subtitle: const Text(
                'Follow your object and draw its motion trail.',
              ),
              trailing: Icon(
                selectedActivity == 'tracking'
                    ? Icons.check_circle
                    : Icons.play_arrow,
                semanticLabel: selectedActivity == 'tracking'
                    ? 'Selected activity'
                    : 'Select activity',
              ),
              onTap: onTrack,
            ),
          ),
          const SizedBox(height: 12),

          // 2. Thud (Impact & Rebound) Activity Card
          Card(
            color: selectedActivity == 'thud'
                ? const Color(0xFFDCFCE7)
                : const Color(0xFFF1F5F9),
            surfaceTintColor: Colors.transparent,
            child: ListTile(
              textColor: const Color(0xFF111827),
              iconColor: const Color(0xFF334155),
              subtitleTextStyle: const TextStyle(
                color: Color(0xFF475569),
                fontSize: 14,
              ),
              leading: const Icon(Icons.sports_baseball),
              title: const Text('Thud'),
              subtitle: const Text(
                'Detect physical wall/desk impacts, shockwaves, and deflection angles.',
              ),
              trailing: Icon(
                selectedActivity == 'thud'
                    ? Icons.check_circle
                    : Icons.play_arrow,
                semanticLabel: selectedActivity == 'thud'
                    ? 'Selected activity'
                    : 'Select activity',
              ),
              onTap: onThud,
            ),
          ),
        ],
      ),
    ),
  );
}
