import 'package:camera/camera.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'debug_screen.dart';
import 'package:flutter/material.dart';
import '../models/sampled_object.dart';
import 'activities_screen.dart';
import 'objects_screen.dart';
import 'thud_screen.dart';
import 'tracker_screen.dart';

class HomeScreen extends StatefulWidget {
  final List<CameraDescription> cameras;
  const HomeScreen({super.key, required this.cameras});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tab = 0;
  SampledObject? _object;
  bool _switching = false;
  bool _loading = true;
  String? _activity;
  SharedPreferences? _preferences;

  @override
  void initState() {
    super.initState();
    _restore();
  }

  Future<void> _restore() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final objects = await ObjectLibrary.load();
      final selectedId = preferences.getString('selected_object_id');
      final matches = objects.where((object) => object.id == selectedId);
      if (!mounted) return;
      _preferences = preferences;
      _object = matches.isEmpty ? null : matches.first;
      final savedAct = preferences.getString('selected_activity');
      _activity = (savedAct == 'tracking' || savedAct == 'thud') ? savedAct : null;
      _tab = _object != null && _activity != null ? 2 : 0;
    } catch (error) {
      debugPrint('Could not restore selection: $error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _saveSelection() async {
    try {
      final preferences = _preferences ?? await SharedPreferences.getInstance();
      final objectId = _object?.id;
      final activity = _activity;
      final objectSaved = objectId == null
          ? await preferences.remove('selected_object_id')
          : await preferences.setString('selected_object_id', objectId);
      final activitySaved = activity == null
          ? await preferences.remove('selected_activity')
          : await preferences.setString('selected_activity', activity);
      if (!objectSaved || !activitySaved) {
        throw StateError('Selection write failed');
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not remember your selection for next time.'),
          ),
        );
      }
    }
  }

  final _tracker = GlobalKey<TrackerScreenState>();
  final _thud = GlobalKey<ThudScreenState>();

  Future<void> _selectTab(int tab) async {
    if (_switching || tab == _tab) return;
    _switching = true;
    try {
      if (_tab == 2) {
        if (_tracker.currentState != null) {
          if (!await _tracker.currentState!.leaveActivity()) return;
        }
        if (_thud.currentState != null) {
          if (!await _thud.currentState!.leaveActivity()) return;
        }
      }
      if (mounted) setState(() => _tab = tab);
    } finally {
      _switching = false;
    }
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_tab == 3) return const DebugScreen();
    final object = _object;
    if (_tab == 0) {
      return ObjectsScreen(
        cameras: widget.cameras,
        selectedObjectId: _object?.id,
        onSelect: (object) {
          setState(() {
            _object = object;
            _tab = _activity == null ? 1 : 2;
          });
          _saveSelection();
        },
        onObjectsChanged: (objects) {
          if (!objects.any((object) => object.id == _object?.id)) {
            setState(() => _object = null);
            _saveSelection();
          }
        },
      );
    }
    if (object == null) {
      return Scaffold(
        appBar: AppBar(title: Text(_tab == 1 ? 'Your activities' : 'Play')),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Select an object to get started.'),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => _selectTab(0),
                child: const Text('Choose object'),
              ),
            ],
          ),
        ),
      );
    }
    if (_tab == 1) {
      return ActivitiesScreen(
        cameras: widget.cameras,
        object: object,
        selectedActivity: _activity,
        onTrack: () {
          setState(() => _activity = 'tracking');
          _saveSelection();
          _selectTab(2);
        },
        onThud: () {
          setState(() => _activity = 'thud');
          _saveSelection();
          _selectTab(2);
        },
      );
    }
    if (_activity == null) {
      return Center(
        child: FilledButton(
          onPressed: () => _selectTab(1),
          child: const Text('Choose activity'),
        ),
      );
    }
    if (_activity == 'thud') {
      return ThudScreen(
        key: _thud,
        cameras: widget.cameras,
        hsvProfile: object.profile,
        objectName: object.name,
        objectId: object.id,
        embedded: true,
      );
    }
    return TrackerScreen(
      key: _tracker,
      cameras: widget.cameras,
      hsvProfile: object.profile,
      objectName: object.name,
      objectId: object.id,
      embedded: true,
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: _body(),
    bottomNavigationBar: NavigationBar(
      selectedIndex: _tab,
      onDestinationSelected: _loading ? null : _selectTab,
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.category_outlined),
          label: 'Objects',
        ),
        NavigationDestination(icon: Icon(Icons.grid_view), label: 'Activities'),
        NavigationDestination(
          icon: Icon(Icons.play_circle_outline),
          label: 'Play',
        ),
        NavigationDestination(
          icon: Icon(Icons.bug_report_outlined),
          label: 'Debug',
        ),
      ],
    ),
  );
}
