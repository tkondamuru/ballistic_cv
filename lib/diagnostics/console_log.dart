import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// iOS release Dart logs are not always forwarded by device launch tools.
/// Mirror diagnostic lines to native stderr for devicectl --console.
void consoleLog(String message) {
  if (!Platform.isIOS) {
    debugPrint(message);
    return;
  }
  unawaited(
    const MethodChannel(
      'ballistic/console',
    ).invokeMethod<void>('line', message).catchError((Object error) {
      debugPrint(message);
    }),
  );
}
