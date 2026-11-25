import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:party_core/party_core.dart';

import '../discovery/lan_discovery_io.dart';
import 'game_transport.dart';

class _LanPeer {
  _LanPeer(this.socket);
  final WebSocket socket;
  String? playerId;
}

/// Embedded LAN / Mobile Hotspot game host that runs directly inside the Host's
/// Android, iOS, or Windows device with zero external internet required.
class LanHostGameTransport implements GameTransport {
  LanHostGameTransport._({
    required this.controller,
    required this.hostPlayerId,
    required this.server,
    required this.lanWsUrl,
    required this.beacon,
  });

  final RoomController controller;
  final String hostPlayerId;
  final HttpServer server;
  final String lanWsUrl;
  final LanRoomBeacon beacon;

  final Map<String, _LanPeer> _peers = {};
  final _snapshotsController = StreamController<RoomSnapshot>.broadcast();
  final _eventsController = StreamController<GameEvent>.broadcast();
  final _errorsController = StreamController<String>.broadcast();
  final _statusController = StreamController<TransportStatus>.broadcast();
  TransportStatus _status = TransportStatus.connected;

  @override
  Stream<RoomSnapshot> get snapshots => _snapshotsController.stream;

  @override
  Stream<GameEvent> get events => _eventsController.stream;

  @override
  Stream<String> get errors => _errorsController.stream;

  @override
  Stream<TransportStatus> get statusStream => _statusController.stream;

  @override
  TransportStatus get status => _status;

  @override
  TransportEndpointInfo get endpointInfo => TransportEndpointInfo(
        mode: ConnectionMode.lanHost,
        label: '局域网/热点主机',
        lanWsUrl: lanWsUrl,
      );

  static Future<LanHostGameTransport> start({
    required String hostName,
    required GameType gameType,
    int port = 8765,
  }) async {
    final random = Random();
    final roomCode = (1000 + random.nextInt(9000)).toString();
    final registry = GamePluginRegistry([
      WerewolfPlugin(),
      GuandanPlugin(),
      OneNightPlugin(),
    ]);
    final controller = RoomController(
      roomId: 'lan_$roomCode',
      roomCode: roomCode,
      gameType: gameType,
      registry: registry,
    );
    final hostJoin = controller.joinPlayer(name: hostName);

    HttpServer server;
    try {
      server = await HttpServer.bind(InternetAddress.anyIPv4, port);
    } catch (_) {
      server = await HttpServer.bind(InternetAddress.anyIPv4, 0);
    }

    final localIp = await detectLocalLanIp();
    final wsUrl = 'ws://$localIp:${server.port}/ws';
    final beacon = LanRoomBeacon(
      roomCode: roomCode,
      hostName: hostName,
      wsPort: server.port,
      gameName: gameType.displayName,
      playerCountProvider: () => controller.players.length,
      maxPlayers: registry.requirePlugin(gameType).maxPlayers,
    );

    final transport = LanHostGameTransport._(
      controller: controller,
      hostPlayerId: hostJoin.playerId,
      server: server,
      lanWsUrl: wsUrl,
      beacon: beacon,
    );

    server.listen(transport._handleHttpRequest);
    await beacon.start();

    // Emit initial host snapshot on next microtask so listeners receive it.
    scheduleMicrotask(() {
      transport._emitHostSnapshot(includeToken: true);
    });

    return transport;
  }

  Future<void> _handleHttpRequest(HttpRequest request) async {
    request.response.headers.set('Access-Control-Allow-Origin', '*');

    if (request.uri.path == '/health') {
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({
          'status': 'ok',
          'mode': 'lan_host',
          'roomCode': controller.roomCode,
          'players': controller.players.length,
        }));
      await request.response.close();
      return;
    }

    if (request.uri.path == '/ws' && WebSocketTransformer.isUpgradeRequest(request)) {
      final socket = await WebSocketTransformer.upgrade(request);
      final peer = _LanPeer(socket);
      socket.listen(
        (raw) {
          if (raw is! String) return;
          _handlePeerMessage(peer, raw);
        },
        onDone: () => _handlePeerDisconnect(peer),
        onError: (_) => _handlePeerDisconnect(peer),
      );
      return;
    }

    request.response
      ..statusCode = HttpStatus.ok
      ..headers.contentType = ContentType.text
      ..write('PartyBox LAN Host (Room ${controller.roomCode})');
    await request.response.close();
  }

  void _handlePeerMessage(_LanPeer peer, String raw) {
    try {
      final msg = ClientMessage.decode(raw);
      switch (msg.type) {
        case ClientMessageType.ping:
          _sendSocket(peer.socket, ServerMessage.pong());
        case ClientMessageType.joinRoom:
          final join = controller.joinPlayer(
            name: msg.payload['name'] as String? ?? '玩家',
            preferredPlayerId: msg.payload['playerId'] as String?,
          );
          peer.playerId = join.playerId;
          _peers[join.playerId] = peer;
          _sendSocket(
            peer.socket,
            ServerMessage.snapshot(
              controller.snapshotForPlayer(join.playerId, includeToken: true),
            ),
          );
          _broadcastAll(excludePeerId: join.playerId);
        case ClientMessageType.reconnect:
          final pid = msg.payload['playerId'] as String? ?? '';
          final token = msg.payload['sessionToken'] as String? ?? '';
          controller.reconnectPlayer(playerId: pid, sessionToken: token);
          peer.playerId = pid;
          _peers[pid] = peer;
          _sendSocket(
            peer.socket,
            ServerMessage.snapshot(
              controller.snapshotForPlayer(pid, includeToken: true),
            ),
          );
          _broadcastAll(excludePeerId: pid);
        default:
          final pid = peer.playerId;
          if (pid == null) {
            throw const GameRuleException('请先加入房间。');
          }
          _applyRoomAction(pid, msg);
      }
    } on GameRuleException catch (e) {
      _sendSocket(peer.socket, ServerMessage.error(e.message));
    } catch (e) {
      _sendSocket(peer.socket, ServerMessage.error('请求处理失败：$e'));
    }
  }

  void _handlePeerDisconnect(_LanPeer peer) {
    final pid = peer.playerId;
    if (pid == null) return;
    if (_peers[pid] == peer) {
      _peers.remove(pid);
      controller.markDisconnected(pid);
      _broadcastAll();
    }
  }

  @override
  void send(ClientMessage message) {
    try {
      _applyRoomAction(hostPlayerId, message);
    } on GameRuleException catch (e) {
      if (!_errorsController.isClosed) {
        _errorsController.add(e.message);
      }
    } catch (e) {
      if (!_errorsController.isClosed) {
        _errorsController.add('操作失败：$e');
      }
    }
  }

  void _applyRoomAction(String playerId, ClientMessage msg) {
    List<GameEvent> emittedEvents = const [];
    switch (msg.type) {
      case ClientMessageType.toggleReady:
        controller.toggleReady(playerId);
      case ClientMessageType.updateConfig:
        final cfg = Map<String, dynamic>.from(msg.payload['config'] as Map? ?? {});
        controller.updateConfig(playerId, cfg);
      case ClientMessageType.addBot:
        if (playerId != controller.hostId) {
          throw const GameRuleException('只有房主可以添加测试机器人。');
        }
        final count = (msg.payload['count'] as num?)?.toInt() ?? 1;
        for (var i = 0; i < count; i++) {
          final n = controller.players.length + 1;
          controller.joinPlayer(name: 'AI玩家$n', isBot: true);
        }
      case ClientMessageType.removeBot:
        controller.removeBot(playerId, botId: msg.payload['botId'] as String?);
      case ClientMessageType.startGame:
        emittedEvents = controller.startGame(playerId);
      case ClientMessageType.returnToLobby:
        controller.returnToLobby(playerId);
      case ClientMessageType.gameAction:
        final actionType = msg.payload['actionType'] as String? ?? '';
        final data = Map<String, dynamic>.from(msg.payload['data'] as Map? ?? {});
        emittedEvents = controller.handleGameAction(playerId, actionType, data);
      case ClientMessageType.leaveRoom:
        controller.leavePlayer(playerId);
      case ClientMessageType.ping:
        return;
      default:
        throw GameRuleException('不支持的操作：${msg.type}');
    }

    _broadcastAll();
    _broadcastEvents(emittedEvents);
  }

  void _emitHostSnapshot({bool includeToken = false}) {
    if (!_snapshotsController.isClosed) {
      _snapshotsController.add(
        controller.snapshotForPlayer(hostPlayerId, includeToken: includeToken),
      );
    }
  }

  void _broadcastAll({String? excludePeerId}) {
    _emitHostSnapshot();
    for (final entry in _peers.entries) {
      if (entry.key == excludePeerId) continue;
      _sendSocket(
        entry.value.socket,
        ServerMessage.snapshot(controller.snapshotForPlayer(entry.key)),
      );
    }
  }

  void _broadcastEvents(List<GameEvent> events) {
    for (final ev in events) {
      final targets = ev.targetPlayerIds;
      if (targets == null || targets.contains(hostPlayerId)) {
        if (!_eventsController.isClosed) {
          _eventsController.add(ev);
        }
      }
      for (final entry in _peers.entries) {
        if (targets == null || targets.contains(entry.key)) {
          _sendSocket(entry.value.socket, ServerMessage.event(ev));
        }
      }
    }
  }

  void _sendSocket(WebSocket socket, ServerMessage message) {
    if (socket.readyState == WebSocket.open) {
      try {
        socket.add(message.encode());
      } catch (_) {}
    }
  }

  @override
  Future<void> close() async {
    _status = TransportStatus.disconnected;
    await beacon.stop();
    final peers = _peers.values.toList();
    _peers.clear();
    for (final p in peers) {
      try {
        await p.socket.close();
      } catch (_) {}
    }
    await server.close(force: true);
    await _snapshotsController.close();
    await _eventsController.close();
    await _errorsController.close();
    await _statusController.close();
  }
}

Future<GameTransport> createLanHostTransport({
  required String hostName,
  required GameType gameType,
  int port = 8765,
}) {
  return LanHostGameTransport.start(
    hostName: hostName,
    gameType: gameType,
    port: port,
  );
}
