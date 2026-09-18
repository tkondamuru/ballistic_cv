import 'dart:io';
import 'package:flutter/material.dart';
import '../capture/frame_capture.dart';
import '../capture/trajectory_recorder.dart';
import 'frame_review_screen.dart';

class DebugScreen extends StatefulWidget {
  const DebugScreen({super.key});
  @override
  State<DebugScreen> createState() => _DebugScreenState();
}

class _DebugScreenState extends State<DebugScreen> {
  final FrameCapture _capture = FrameCapture();
  @override
  void initState() {
    super.initState();
    _capture.addListener(_captureChanged);
    if (Platform.isIOS) {
      _capture.load();
      TrajectoryRecorder.instance.refresh();
    }
  }

  void _captureChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _capture.removeListener(_captureChanged);
    _capture.dispose();
    super.dispose();
  }

  Future<void> _deleteCapture() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete scanned frames?'),
        content: const Text(
          'This removes the entire capture set and enables a new capture. Saved objects are kept.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete capture'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) await _capture.delete();
  }

  Future<void> _stopTrajectory() async {
    int? count;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Save tracking session'),
        content: TextField(
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Actual hits (optional)',
          ),
          onChanged: (text) => count = int.tryParse(text),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await TrajectoryRecorder.instance.stop(
        actualHits: count != null && count! >= 0 ? count : null,
      );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Debug')),
    body: ListView(
      children: [
        if (Platform.isIOS)
          ListenableBuilder(
            listenable: TrajectoryRecorder.instance,
            builder: (context, _) {
              final recorder = TrajectoryRecorder.instance;
              return Card(
                margin: const EdgeInsets.all(16),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Tracking recordings',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Start here, then open Thud in Play. Records coordinates and hits without images, up to 10 minutes. Return here to stop and share. Saves automatically if the app goes inactive.',
                      ),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: recorder.busy
                            ? null
                            : recorder.session != null
                            ? _stopTrajectory
                            : recorder.start,
                        icon: Icon(
                          recorder.session != null
                              ? Icons.stop
                              : Icons.fiber_manual_record,
                        ),
                        label: Text(
                          recorder.session != null
                              ? 'Stop and save recording'
                              : 'Start tracking recording',
                        ),
                      ),
                      if (recorder.recording)
                        const Text('Recording — open Play → Thud'),
                      if (recorder.error != null) Text(recorder.error!),
                      for (final file in recorder.files)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            file['name'] as String,
                            style: const TextStyle(fontSize: 12),
                          ),
                          subtitle: Text(
                            '${((file['bytes'] as num) / 1024).toStringAsFixed(1)} KB · coordinate log',
                          ),
                          trailing: IconButton(
                            tooltip: 'Share or save to Files',
                            icon: const Icon(Icons.ios_share),
                            onPressed: () =>
                                recorder.share(file['name'] as String),
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),

        if (_capture.saved != null)
          Card(
            color: const Color(0xFFF1F5F9),
            surfaceTintColor: Colors.transparent,
            margin: const EdgeInsets.all(16),
            child: ListTile(
              textColor: Colors.black87,
              iconColor: Colors.black87,
              leading: const Icon(Icons.view_carousel),
              title: const Text('Scanned frames'),
              subtitle: Text(
                '${_capture.saved!.name} · ${_capture.saved!.frames.length} frames · '
                '${(_capture.saved!.data['summary'] as Map?)?['skipped'] ?? 0} skipped',
              ),
              onTap: _capture.busy
                  ? null
                  : () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            FrameReviewScreen(capture: _capture.saved!),
                      ),
                    ),
              trailing: IconButton(
                tooltip: 'Delete scanned frames',
                color: Colors.black87,
                onPressed: _capture.busy ? null : _deleteCapture,
                icon: const Icon(Icons.delete_outline),
              ),
            ),
          ),
        if (_capture.message != null)
          ListTile(
            title: Text(_capture.message!),
            trailing: TextButton(
              onPressed: _capture.busy ? null : _deleteCapture,
              child: const Text('Delete capture'),
            ),
          ),
        if (_capture.busy) const Center(child: CircularProgressIndicator()),
        if (!_capture.busy &&
            _capture.saved == null &&
            _capture.message == null)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              Platform.isIOS
                  ? 'No scanned frames yet. Use Scan 10s in Play, then review or delete the capture here.'
                  : 'Frame capture is currently available on iPhone.',
              textAlign: TextAlign.center,
            ),
          ),
      ],
    ),
  );
}
