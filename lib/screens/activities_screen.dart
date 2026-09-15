import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import '../models/sampled_object.dart';
import 'thud_screen.dart';

class ActivitiesScreen extends StatelessWidget {
  final List<CameraDescription> cameras;
  final SampledObject object;
  final VoidCallback onTrack;
  final bool selected;
  const ActivitiesScreen({
    super.key,
    required this.cameras,
    required this.object,
    required this.onTrack,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Your activities')),
    body: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Card(
            color: selected ? const Color(0xFFDCFCE7) : const Color(0xFFF1F5F9),
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
                selected ? Icons.check_circle : Icons.play_arrow,
                semanticLabel: selected
                    ? 'Selected activity'
                    : 'Select activity',
              ),
              onTap: onTrack,
            ),
          ),
          const SizedBox(height: 12),

          // 2. Thud (Impact & Rebound) Activity Card
          Card(
            color: const Color(0xFFF1F5F9),
            surfaceTintColor: Colors.transparent,
            child: ListTile(
              textColor: const Color(0xFF111827),
              iconColor: const Color(0xFF334155),
              subtitleTextStyle: const TextStyle(color: Color(0xFF475569), fontSize: 14),
              leading: const Icon(Icons.sports_baseball),
              title: const Text('Thud'),
              subtitle: const Text(
                'Detect physical wall/desk impacts, shockwaves, and deflection angles.',
              ),
              trailing: const Icon(Icons.play_arrow),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ThudScreen(
                    cameras: cameras,
                    hsvProfile: object.profile,
                    objectName: object.name,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
