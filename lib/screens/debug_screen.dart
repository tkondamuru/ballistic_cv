import 'dart:io';
import 'package:flutter/material.dart';
import '../capture/frame_capture.dart';
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
    if (Platform.isIOS) _capture.load();
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

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Debug')),
    body: ListView(
      children: [
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
