import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'lan_models.dart';

const int kPartyLanDiscoveryPort = 45876;

/// Broadcasts a LAN host room beacon over UDP so other phones on the same Wi-Fi
/// or mobile hotspot find the room automatically without internet.
class LanRoomBeacon {
  LanRoomBeacon({
    required this.roomCode,
    required this.hostName,
    required this.wsPort,
    required this.gameName,
    required this.playerCountProvider,
    required this.maxPlayers,
  });

  final String roomCode;
  final String hostName;
  final int wsPort;
  final String gameName;
  final int Function() playerCountProvider;
  final int maxPlayers;

  RawDatagramSocket? _socket;
  Timer? _timer;

  Future<void> start() async {
    try {
      _socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      _socket!.broadcastEnabled = true;
      _sendBeacon();
      _timer = Timer.periodic(const Duration(seconds: 2), (_) => _sendBeacon());
    } catch (_) {
      // If UDP broadcast is blocked by OS/router, QR code & manual IP still work.
    }
  }

  void _sendBeacon() {
    if (_socket == null) return;
    final payload = jsonEncode({
      'app': 'partybox',
      'roomCode': roomCode,
      'hostName': hostName,
      'port': wsPort,
      'gameName': gameName,
      'playerCount': playerCountProvider(),
      'maxPlayers': maxPlayers,
    });
    final bytes = utf8.encode(payload);
    try {
      _socket!.send(
        bytes,
        InternetAddress('255.255.255.255'),
        kPartyLanDiscoveryPort,
      );
    } catch (_) {}
  }

  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    _socket?.close();
    _socket = null;
  }
}

/// Listens for PartyBox UDP beacons on the local Wi-Fi or mobile hotspot.
class LanDiscoveryService {
  final _rooms = <String, DiscoveredLanRoom>{};
  final _controller = StreamController<List<DiscoveredLanRoom>>.broadcast();
  RawDatagramSocket? _socket;
  Timer? _pruneTimer;

  Stream<List<DiscoveredLanRoom>> get roomsStream => _controller.stream;
  List<DiscoveredLanRoom> get currentRooms => _rooms.values.toList();
  bool get isSupported => true;

  Future<void> startScanning() async {
    await stopScanning();
    try {
      _socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        kPartyLanDiscoveryPort,
        reuseAddress: true,
        reusePort: false,
      );
      _socket!.broadcastEnabled = true;
      _socket!.listen((event) {
        if (event != RawSocketEvent.read) return;
        final datagram = _socket?.receive();
        if (datagram == null) return;
        _handleDatagram(datagram);
      });
      _pruneTimer = Timer.periodic(const Duration(seconds: 3), (_) => _prune());
    } catch (_) {
      // Graceful fallback if UDP port is already bound or restricted.
    }
  }

  void _handleDatagram(Datagram datagram) {
    try {
      final map = jsonDecode(utf8.decode(datagram.data)) as Map<String, dynamic>;
      if (map['app'] != 'partybox') return;
      final room = DiscoveredLanRoom(
        roomCode: map['roomCode'] as String? ?? 'LAN',
        hostName: map['hostName'] as String? ?? '房主',
        ip: datagram.address.address,
        port: (map['port'] as num?)?.toInt() ?? 8765,
        gameName: map['gameName'] as String? ?? '狼人杀',
        playerCount: (map['playerCount'] as num?)?.toInt() ?? 1,
        maxPlayers: (map['maxPlayers'] as num?)?.toInt() ?? 12,
        lastSeen: DateTime.now(),
      );
      _rooms[room.key] = room;
      if (!_controller.isClosed) {
        _controller.add(_rooms.values.toList());
      }
    } catch (_) {}
  }

  void _prune() {
    final cutoff = DateTime.now().subtract(const Duration(seconds: 8));
    final before = _rooms.length;
    _rooms.removeWhere((_, room) => room.lastSeen.isBefore(cutoff));
    if (_rooms.length != before && !_controller.isClosed) {
      _controller.add(_rooms.values.toList());
    }
  }

  Future<void> stopScanning() async {
    _pruneTimer?.cancel();
    _pruneTimer = null;
    _socket?.close();
    _socket = null;
  }

  Future<void> dispose() async {
    await stopScanning();
    await _controller.close();
  }
}

/// Detects the best private LAN/hotspot IPv4 address for sharing via QR code.
Future<String> detectLocalLanIp() async {
  try {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
    );
    String? fallback;
    for (final iface in interfaces) {
      final name = iface.name.toLowerCase();
      for (final addr in iface.addresses) {
        final ip = addr.address;
        if (ip.startsWith('169.254.')) continue;
        // Prefer Wi-Fi / Hotspot private ranges (192.168.x.x / 172.20.x.x / 10.x.x.x)
        if (name.contains('wlan') ||
            name.contains('en0') ||
            name.contains('ap') ||
            name.contains('wi-fi') ||
            ip.startsWith('192.168.') ||
            ip.startsWith('172.20.')) {
          return ip;
        }
        fallback ??= ip;
      }
    }
    return fallback ?? '127.0.0.1';
  } catch (_) {
    return '127.0.0.1';
  }
}
