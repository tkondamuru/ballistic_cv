import 'dart:async';
import 'package:flutter/material.dart';

class ZoomButton extends StatefulWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onStep;
  const ZoomButton({
    super.key,
    required this.label,
    required this.icon,
    this.onStep,
  });

  @override
  State<ZoomButton> createState() => _ZoomButtonState();
}

class _ZoomButtonState extends State<ZoomButton> with WidgetsBindingObserver {
  Timer? _repeat;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _stop();
  }

  void _stop() {
    _repeat?.cancel();
    _repeat = null;
  }

  void _start() {
    // GestureDetector supplies the hold delay; repeat only after it recognizes
    // a long press. A short press is handled once by the IconButton below.
    _stop();
    widget.onStep?.call();
    _repeat = Timer.periodic(const Duration(milliseconds: 120), (_) {
      widget.onStep?.call();
    });
  }

  @override
  void didUpdateWidget(covariant ZoomButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The parent disables the callback when a camera zoom limit is reached.
    if (widget.onStep == null) _stop();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    label: widget.label,
    child: GestureDetector(
      onLongPressStart: widget.onStep == null ? null : (_) => _start(),
      onLongPressEnd: (_) => _stop(),
      onLongPressCancel: _stop,
      child: IconButton(onPressed: widget.onStep, icon: Icon(widget.icon)),
    ),
  );
}
