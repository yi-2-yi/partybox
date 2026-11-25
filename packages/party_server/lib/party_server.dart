import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:party_core/party_core.dart';

class _ClientSession {
  _ClientSession(this.socket);

  final WebSocket socket;
  String? roomCode;
  String? playerId;
}

class _ManagedRoom {
  _ManagedRoom(this.controller);

  final RoomController controller;
  final Map<String, _ClientSession> socketsByPlayerId = {};
}

/// Online multi-room WebSocket server for PartyBox.
///
/// Reuses [RoomController] and [GamePluginRegistry] from `party_core`, so online
/// rooms run the exact same game rules as LAN/hotspot host rooms.
class PartyServer {
  PartyServer({
    GamePluginRegistry? registry,
    Random? random,
  })  : _registry = registry ?? GamePluginRegistry([WerewolfPlugin()]),
        _random = random ?? Random();

  final GamePluginRegistry _registry;
  final Random _random;
  final Map<String, _ManagedRoom> _rooms = {};

  HttpServer? _server;

  int get port => _server?.port ?? 0;
  int get activeRoomCount => _rooms.length;

  Future<void> start({
    dynamic address = '0.0.0.0',
    int port = 8080,
  }) async {
    _server = await HttpServer.bind(address, port);
    _server!.listen(_handleHttpRequest);
  }

  Future<void> stop() async {
    final roomsToClose = _rooms.values.toList();
    _rooms.clear();
    for (final room in roomsToClose) {
      final sessions = room.socketsByPlayerId.values.toList();
      room.socketsByPlayerId.clear();
      for (final session in sessions) {
        try {
          await session.socket.close();
        } catch (_) {}
      }
    }
    await _server?.close(force: true);
    _server = null;
  }

  Future<void> _handleHttpRequest(HttpRequest request) async {
    request.response.headers.set('Access-Control-Allow-Origin', '*');

    if (request.uri.path == '/health') {
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({
          'status': 'ok',
          'service': 'party_server',
          'rooms': _rooms.length,
        }));
      await request.response.close();
      return;
    }

    if (request.uri.path == '/ws' && WebSocketTransformer.isUpgradeRequest(request)) {
      final socket = await WebSocketTransformer.upgrade(request);
      _attachSocket(socket);
      return;
    }

    request.response
      ..statusCode = HttpStatus.notFound
      ..write('PartyBox Server: connect via WebSocket at /ws or GET /health');
    await request.response.close();
  }

  void _attachSocket(WebSocket socket) {
    final session = _ClientSession(socket);
    socket.listen(
      (raw) {
        if (raw is! String) return;
        _handleMessage(session, raw);
      },
      onDone: () => _handleDisconnect(session),
      onError: (_) => _handleDisconnect(session),
    );
  }

  void _handleMessage(_ClientSession session, String raw) {
    try {
      final msg = ClientMessage.decode(raw);
      switch (msg.type) {
        case ClientMessageType.ping:
          _send(session.socket, ServerMessage.pong());
        case ClientMessageType.createRoom:
          _handleCreateRoom(session, msg.payload);
        case ClientMessageType.joinRoom:
          _handleJoinRoom(session, msg.payload);
        case ClientMessageType.reconnect:
          _handleReconnect(session, msg.payload);
        case ClientMessageType.leaveRoom:
          _handleLeaveRoom(session);
        case ClientMessageType.updateConfig:
          _withRoom(session, (managed, playerId) {
            final config = Map<String, dynamic>.from(
              msg.payload['config'] as Map? ?? {},
            );
            managed.controller.updateConfig(playerId, config);
            _broadcastSnapshots(managed);
          });
        case ClientMessageType.toggleReady:
          _withRoom(session, (managed, playerId) {
            managed.controller.toggleReady(playerId);
            _broadcastSnapshots(managed);
          });
        case ClientMessageType.addBot:
          _withRoom(session, (managed, playerId) {
            if (managed.controller.hostId != playerId) {
              throw const GameRuleException('只有房主可以添加机器人。');
            }
            final count = (msg.payload['count'] as num?)?.toInt() ?? 1;
            for (var i = 0; i < count; i++) {
              final nextNum = managed.controller.players.length + 1;
              managed.controller.joinPlayer(
                name: 'AI玩家$nextNum',
                isBot: true,
              );
            }
            _broadcastSnapshots(managed);
          });
        case ClientMessageType.removeBot:
          _withRoom(session, (managed, playerId) {
            managed.controller.removeBot(
              playerId,
              botId: msg.payload['botId'] as String?,
            );
            _broadcastSnapshots(managed);
          });
        case ClientMessageType.startGame:
          _withRoom(session, (managed, playerId) {
            final events = managed.controller.startGame(playerId);
            _broadcastSnapshots(managed);
            _broadcastEvents(managed, events);
          });
        case ClientMessageType.returnToLobby:
          _withRoom(session, (managed, playerId) {
            managed.controller.returnToLobby(playerId);
            _broadcastSnapshots(managed);
          });
        case ClientMessageType.gameAction:
          _withRoom(session, (managed, playerId) {
            final actionType = msg.payload['actionType'] as String? ?? '';
            final actionPayload = Map<String, dynamic>.from(
              msg.payload['data'] as Map? ?? {},
            );
            final events = managed.controller.handleGameAction(
              playerId,
              actionType,
              actionPayload,
            );
            _broadcastSnapshots(managed);
            _broadcastEvents(managed, events);
          });
        default:
          _send(session.socket, ServerMessage.error('未知消息类型：${msg.type}'));
      }
    } on GameRuleException catch (e) {
      _send(session.socket, ServerMessage.error(e.message, code: 'rule_error'));
    } catch (e) {
      _send(session.socket, ServerMessage.error('消息解析失败：$e', code: 'bad_request'));
    }
  }

  void _handleCreateRoom(_ClientSession session, Map<String, dynamic> payload) {
    final gameType = GameType.fromName(
      payload['gameType'] as String? ?? GameType.werewolf.name,
    );
    final playerName = payload['name'] as String? ?? '房主';
    final preferredPlayerId = payload['playerId'] as String?;

    final roomCode = _allocateRoomCode();
    final controller = RoomController(
      roomId: 'room_$roomCode',
      roomCode: roomCode,
      gameType: gameType,
      registry: _registry,
      random: _random,
    );
    final managed = _ManagedRoom(controller);
    _rooms[roomCode] = managed;

    final join = controller.joinPlayer(
      name: playerName,
      preferredPlayerId: preferredPlayerId,
    );
    session.roomCode = roomCode;
    session.playerId = join.playerId;
    managed.socketsByPlayerId[join.playerId] = session;

    _send(
      session.socket,
      ServerMessage.snapshot(
        controller.snapshotForPlayer(join.playerId, includeToken: true),
      ),
    );
  }

  void _handleJoinRoom(_ClientSession session, Map<String, dynamic> payload) {
    final roomCode = (payload['roomCode'] as String? ?? '').trim().toUpperCase();
    final managed = _rooms[roomCode];
    if (managed == null) {
      throw GameRuleException('未找到房间号「$roomCode」，请确认后重试。');
    }

    final join = managed.controller.joinPlayer(
      name: payload['name'] as String? ?? '玩家',
      preferredPlayerId: payload['playerId'] as String?,
    );
    session.roomCode = roomCode;
    session.playerId = join.playerId;
    managed.socketsByPlayerId[join.playerId] = session;

    _send(
      session.socket,
      ServerMessage.snapshot(
        managed.controller.snapshotForPlayer(join.playerId, includeToken: true),
      ),
    );
    _broadcastSnapshots(managed, excludePlayerId: join.playerId);
  }

  void _handleReconnect(_ClientSession session, Map<String, dynamic> payload) {
    final roomCode = (payload['roomCode'] as String? ?? '').trim().toUpperCase();
    final playerId = payload['playerId'] as String? ?? '';
    final sessionToken = payload['sessionToken'] as String? ?? '';

    final managed = _rooms[roomCode];
    if (managed == null) {
      throw const GameRuleException('房间已关闭，无法重连。');
    }

    managed.controller.reconnectPlayer(
      playerId: playerId,
      sessionToken: sessionToken,
    );
    session.roomCode = roomCode;
    session.playerId = playerId;
    managed.socketsByPlayerId[playerId] = session;

    _send(
      session.socket,
      ServerMessage.snapshot(
        managed.controller.snapshotForPlayer(playerId, includeToken: true),
      ),
    );
    _broadcastSnapshots(managed, excludePlayerId: playerId);
  }

  void _handleLeaveRoom(_ClientSession session) {
    final roomCode = session.roomCode;
    final playerId = session.playerId;
    if (roomCode == null || playerId == null) return;
    final managed = _rooms[roomCode];
    if (managed == null) return;

    managed.socketsByPlayerId.remove(playerId);
    managed.controller.leavePlayer(playerId);
    session.roomCode = null;
    session.playerId = null;

    if (managed.controller.players.every((p) => p.isBot || !p.isConnected) &&
        managed.controller.status == RoomStatus.lobby) {
      _rooms.remove(roomCode);
      return;
    }
    _broadcastSnapshots(managed);
  }

  void _handleDisconnect(_ClientSession session) {
    final roomCode = session.roomCode;
    final playerId = session.playerId;
    if (roomCode == null || playerId == null) return;
    final managed = _rooms[roomCode];
    if (managed == null) return;

    if (managed.socketsByPlayerId[playerId] == session) {
      managed.socketsByPlayerId.remove(playerId);
      managed.controller.markDisconnected(playerId);
      _broadcastSnapshots(managed);
    }
  }

  void _withRoom(
    _ClientSession session,
    void Function(_ManagedRoom managed, String playerId) fn,
  ) {
    final roomCode = session.roomCode;
    final playerId = session.playerId;
    if (roomCode == null || playerId == null) {
      throw const GameRuleException('请先创建或加入房间。');
    }
    final managed = _rooms[roomCode];
    if (managed == null) {
      throw const GameRuleException('房间已不存在。');
    }
    fn(managed, playerId);
  }

  void _broadcastSnapshots(_ManagedRoom managed, {String? excludePlayerId}) {
    for (final entry in managed.socketsByPlayerId.entries) {
      if (entry.key == excludePlayerId) continue;
      final snapshot = managed.controller.snapshotForPlayer(entry.key);
      _send(entry.value.socket, ServerMessage.snapshot(snapshot));
    }
  }

  void _broadcastEvents(_ManagedRoom managed, List<GameEvent> events) {
    for (final event in events) {
      final targets = event.targetPlayerIds;
      for (final entry in managed.socketsByPlayerId.entries) {
        if (targets == null || targets.contains(entry.key)) {
          _send(entry.value.socket, ServerMessage.event(event));
        }
      }
    }
  }

  void _send(WebSocket socket, ServerMessage message) {
    if (socket.readyState == WebSocket.open) {
      try {
        socket.add(message.encode());
      } catch (_) {
        // Client disconnected concurrently; disconnect handler will clean up.
      }
    }
  }

  String _allocateRoomCode() {
    for (var attempt = 0; attempt < 1000; attempt++) {
      final code = (1000 + _random.nextInt(9000)).toString();
      if (!_rooms.containsKey(code)) return code;
    }
    return (100000 + _random.nextInt(900000)).toString();
  }
}
