import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import '../models/hsv_profile.dart';
import '../models/sampled_object.dart';
import 'calibrator_screen.dart';

class ObjectsScreen extends StatefulWidget {
  final List<CameraDescription> cameras;
  final String? selectedObjectId;
  final ValueChanged<SampledObject> onSelect;
  final ValueChanged<List<SampledObject>> onObjectsChanged;
  const ObjectsScreen({
    super.key,
    required this.cameras,
    this.selectedObjectId,
    required this.onSelect,
    required this.onObjectsChanged,
  });
  @override
  State<ObjectsScreen> createState() => _ObjectsScreenState();
}

class _ObjectsScreenState extends State<ObjectsScreen> {
  List<SampledObject> _objects = [];
  bool _busy = true;
  String? _error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final objects = await ObjectLibrary.load();
      if (mounted) {
        setState(() {
          _objects = objects;
          _busy = false;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Could not load objects: $e';
          _busy = false;
        });
      }
    }
  }

  Future<void> _add() async {
    var name = '';
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Name your object'),
        content: TextField(
          onChanged: (value) => name = value,
          autofocus: true,
          maxLength: 40,
          decoration: const InputDecoration(hintText: 'Orange ball'),
          onSubmitted: (value) {
            if (value.trim().isNotEmpty) Navigator.pop(context, value.trim());
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              if (name.trim().isNotEmpty) Navigator.pop(context, name.trim());
            },
            child: const Text('Take samples'),
          ),
        ],
      ),
    );
    if (result == null || !mounted) return;
    final profile = await Navigator.of(context).push<HsvProfile>(
      MaterialPageRoute(
        builder: (_) => CalibratorScreen(cameras: widget.cameras),
      ),
    );
    if (profile == null || !mounted) return;
    await _persist([
      ..._objects,
      SampledObject(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        name: result,
        profile: profile,
      ),
    ]);
  }

  Future<void> _persist(List<SampledObject> objects) async {
    setState(() {
      _busy = true;
    });
    try {
      await ObjectLibrary.save(objects);
      widget.onObjectsChanged(objects);
      if (mounted) {
        setState(() {
          _objects = objects;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Could not save changes: $e';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Your objects')),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: _busy || _error != null ? null : _add,
      icon: const Icon(Icons.add),
      label: const Text('New object'),
    ),
    body: _busy
        ? const Center(child: CircularProgressIndicator())
        : Column(
            children: [
              if (_error != null)
                ListTile(
                  title: Text(_error!),
                  trailing: TextButton(
                    onPressed: _load,
                    child: const Text('Retry'),
                  ),
                ),
              if (_objects.isEmpty)
                const Expanded(
                  child: Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'Add an object and capture three color samples.\nThen select it to choose an activity.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                )
              else
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.only(bottom: 100),
                    itemCount: _objects.length,
                    itemBuilder: (context, index) {
                      final object = _objects[index];
                      final selected = object.id == widget.selectedObjectId;
                      return Card(
                        color: selected
                            ? const Color(0xFFDCFCE7)
                            : const Color(0xFFF1F5F9),
                        surfaceTintColor: Colors.transparent,
                        margin: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 6,
                        ),
                        child: ListTile(
                          textColor: const Color(0xFF111827),
                          iconColor: const Color(0xFF334155),
                          subtitleTextStyle: const TextStyle(
                            color: Color(0xFF475569),
                            fontSize: 14,
                          ),
                          leading: CircleAvatar(
                            backgroundColor: HSVColor.fromAHSV(
                              1,
                              object.profile.hMed * 2.0,
                              object.profile.sMed / 255,
                              object.profile.vMed / 255,
                            ).toColor(),
                          ),
                          title: Text(object.name),
                          subtitle: Text(
                            selected ? '✓ Selected' : 'Choose activity',
                          ),
                          onTap: () => widget.onSelect(object),
                          trailing: IconButton(
                            tooltip: 'Delete ${object.name}',
                            color: const Color(0xFF334155),
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () async {
                              final remove = await showDialog<bool>(
                                context: context,
                                builder: (context) => AlertDialog(
                                  title: Text('Delete ${object.name}?'),
                                  content: const Text(
                                    'This removes its saved color samples.',
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.pop(context, false),
                                      child: const Text('Cancel'),
                                    ),
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.pop(context, true),
                                      child: const Text('Delete'),
                                    ),
                                  ],
                                ),
                              );
                              if (remove == true && mounted) {
                                await _persist(
                                  _objects
                                      .where((e) => e.id != object.id)
                                      .toList(),
                                );
                              }
                            },
                          ),
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
  );
}
