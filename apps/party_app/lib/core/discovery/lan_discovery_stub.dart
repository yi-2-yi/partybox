import 'dart:async';

import 'lan_models.dart';

/// Web fallback stub (browsers do not expose raw UDP sockets).
class LanDiscoveryService {
  Stream<List<DiscoveredLanRoom>> get roomsStream => const Stream.empty();
  List<DiscoveredLanRoom> get currentRooms => const [];
  bool get isSupported => false;

  Future<void> startScanning() async {}
  Future<void> stopScanning() async {}
  Future<void> dispose() async {}
}

Future<String> detectLocalLanIp() async => '127.0.0.1';
