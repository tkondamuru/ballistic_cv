import 'package:flutter_test/flutter_test.dart';
import 'package:ballistic_cv/services/thud_relay_service.dart';

void main() {
  test('ThudRelayService singleton state management', () {
    final relay = ThudRelayService.instance;
    expect(relay.isConnected, false);
    expect(relay.roomId, 'thud-room-1');
  });
}
