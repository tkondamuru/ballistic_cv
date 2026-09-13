import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import '../models/sampled_object.dart';
import 'tracker_screen.dart';

class ActivitiesScreen extends StatelessWidget {
  final List<CameraDescription> cameras;
  final SampledObject object;
  const ActivitiesScreen({
    super.key,
    required this.cameras,
    required this.object,
  });
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(object.name)),
    body: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Choose an activity',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 16),
          Card(
                        color: const Color(0xFFF1F5F9),
                        surfaceTintColor: Colors.transparent,
            child: ListTile(
                          textColor: const Color(0xFF111827),
                          iconColor: const Color(0xFF334155),
                          subtitleTextStyle: const TextStyle(color: Color(0xFF475569), fontSize: 14),
              leading: const Icon(Icons.motion_photos_on),
              title: const Text('Tracking'),
              subtitle: const Text(
                'Follow your object and draw its motion trail.',
              ),
              trailing: const Icon(Icons.play_arrow),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => TrackerScreen(
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
