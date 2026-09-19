import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/foundation.dart';

class ThudRelayService {
  static final ThudRelayService instance = ThudRelayService._internal();
  ThudRelayService._internal();

  WebSocket? _socket;
  bool _isConnected = false;
  String _roomId = 'thud-room-1';

  bool get isConnected => _isConnected;
  String get roomId => _roomId;

  /// Connect outbound over wss:// to Cloudflare Worker relay.
  Future<void> connect(String url, {String room = 'thud-room-1'}) async {
    _roomId = room;
    String cleanUrl = url.trim();
    if (cleanUrl.isEmpty) return;

    if (cleanUrl.startsWith('http://')) {
      cleanUrl = cleanUrl.replaceFirst('http://', 'ws://');
    } else if (cleanUrl.startsWith('https://')) {
      cleanUrl = cleanUrl.replaceFirst('https://', 'wss://');
    } else if (!cleanUrl.startsWith('ws://') && !cleanUrl.startsWith('wss://')) {
      cleanUrl = 'wss://$cleanUrl';
    }

    final fullUri = Uri.parse(
      '${cleanUrl.replaceAll(RegExp(r'/$'), '')}/thud?room=${Uri.encodeComponent(room)}',
    );

    await disconnect();

    try {
      _socket = await WebSocket.connect(fullUri.toString()).timeout(
        const Duration(seconds: 5),
      );
      _isConnected = true;
      debugPrint('[ThudRelay] Connected to Cloudflare Worker: $fullUri');

      _socket!.listen(
        (message) {
          // Received message (if any)
        },
        onError: (err) {
          debugPrint('[ThudRelay] Socket error: $err');
          _isConnected = false;
        },
        onDone: () {
          debugPrint('[ThudRelay] Connection closed.');
          _isConnected = false;
        },
      );
    } catch (e) {
      _isConnected = false;
      debugPrint('[ThudRelay] Connect failed: $e');
    }
  }

  /// Broadcast normalized hit coordinates (u, v) in [0, 1]^2 to Cloudflare relay.
  void sendHit({
    required Offset normalizedPos,
    required double deflectionDegrees,
    required int hitNumber,
  }) {
    if (_socket == null || !_isConnected) return;

    final payload = jsonEncode({
      'type': 'hit',
      'hitNumber': hitNumber,
      'u': double.parse(normalizedPos.dx.toStringAsFixed(4)),
      'v': double.parse(normalizedPos.dy.toStringAsFixed(4)),
      'deflectionDegrees': double.parse(deflectionDegrees.toStringAsFixed(1)),
      'timestampUs': DateTime.now().microsecondsSinceEpoch,
    });

    try {
      _socket!.add(payload);
      debugPrint('[ThudRelay] Broadcasted hit #$hitNumber: $payload');
    } catch (e) {
      debugPrint('[ThudRelay] Failed to send hit payload: $e');
      _isConnected = false;
    }
  }

  Future<void> disconnect() async {
    try {
      await _socket?.close();
    } catch (_) {}
    _socket = null;
    _isConnected = false;
  }
}
