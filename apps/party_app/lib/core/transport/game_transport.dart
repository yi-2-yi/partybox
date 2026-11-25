import 'package:party_core/party_core.dart';

enum TransportStatus {
  disconnected,
  connecting,
  connected,
  reconnecting,
}

/// Shareable metadata about the active connection (for QR codes / room codes).
class TransportEndpointInfo {
  const TransportEndpointInfo({
    required this.mode,
    required this.label,
    this.lanWsUrl,
    this.onlineServerUrl,
  });

  final ConnectionMode mode;
  final String label;

  /// Non-null in LAN Host mode, e.g. `ws://192.168.43.1:8765/ws`
  final String? lanWsUrl;
  final String? onlineServerUrl;
}

/// Unified client transport contract shared across Online, LAN Host, LAN Client,
/// and Local Demo modes.
abstract class GameTransport {
  Stream<RoomSnapshot> get snapshots;
  Stream<GameEvent> get events;
  Stream<String> get errors;
  Stream<TransportStatus> get statusStream;

  TransportStatus get status;
  TransportEndpointInfo get endpointInfo;

  void send(ClientMessage message);

  Future<void> close();
}
