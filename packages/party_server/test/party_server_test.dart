import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:party_core/party_core.dart';
import 'package:party_server/party_server.dart';
import 'package:test/test.dart';

class _TestClient {
  _TestClient._(this.socket) {
    _sub = socket.listen((raw) {
      if (raw is! String) return;
      final msg = ServerMessage.decode(raw);
      if (msg.type == ServerMessageType.roomSnapshot) {
        latestSnapshot = RoomSnapshot.fromJson(msg.payload);
        if (latestSnapshot!.sessionToken != null) {
          savedSessionToken = latestSnapshot!.sessionToken;
        }
        _controller.add(latestSnapshot!);
      }
    });
  }

  final WebSocket socket;
  late final StreamSubscription<dynamic> _sub;
  final _controller = StreamController<RoomSnapshot>.broadcast();
  RoomSnapshot? latestSnapshot;
  String? savedSessionToken;

  static Future<_TestClient> connect(int port) async {
    final ws = await WebSocket.connect('ws://127.0.0.1:$port/ws');
    return _TestClient._(ws);
  }

  void send(ClientMessage msg) => socket.add(msg.encode());

  Future<RoomSnapshot> waitFor(bool Function(RoomSnapshot s) predicate) async {
    if (latestSnapshot != null && predicate(latestSnapshot!)) {
      return latestSnapshot!;
    }
    return _controller.stream
        .firstWhere(predicate)
        .timeout(const Duration(seconds: 5));
  }

  Future<void> close() async {
    await _sub.cancel();
    await socket.close();
    await _controller.close();
  }
}

void main() {
  test('6 real WebSocket clients create room, play Werewolf, and reconnect seamlessly', () async {
    final server = PartyServer(
      registry: GamePluginRegistry([WerewolfPlugin(random: Random(7))]),
      random: Random(7),
    );
    await server.start(address: InternetAddress.loopbackIPv4, port: 0);
    addTearDown(server.stop);

    final clients = <_TestClient>[];
    addTearDown(() async {
      for (final c in clients) {
        await c.close();
      }
    });

    // Host creates room
    final host = await _TestClient.connect(server.port);
    clients.add(host);
    host.send(const ClientMessage(
      type: ClientMessageType.createRoom,
      payload: {'gameType': 'werewolf', 'name': '房主小明'},
    ));
    final hostSnap = await host.waitFor((s) => s.yourPlayerId != null);
    final roomCode = hostSnap.roomCode;
    expect(roomCode.length, 4);

    // 5 friends join and ready up
    for (var i = 2; i <= 6; i++) {
      final c = await _TestClient.connect(server.port);
      clients.add(c);
      c.send(ClientMessage(
        type: ClientMessageType.joinRoom,
        payload: {'roomCode': roomCode, 'name': '朋友$i'},
      ));
      await c.waitFor((s) => s.yourPlayerId != null);
      c.send(const ClientMessage(type: ClientMessageType.toggleReady));
    }

    await host.waitFor(
      (s) => s.players.length == 6 && s.players.every((p) => p.isReady),
    );

    // Start game
    host.send(const ClientMessage(type: ClientMessageType.startGame));
    for (final c in clients) {
      final snap = await c.waitFor((s) => s.status == RoomStatus.playing);
      expect(snap.gameState!['phase'], 'roleReveal');
      expect(snap.gameState!['me']['role'], isNotNull);
    }

    // Client 2 disconnects and reconnects using sessionToken
    final p2Snap = clients[1].latestSnapshot!;
    final p2Id = p2Snap.yourPlayerId!;
    final p2Token = clients[1].savedSessionToken!;
    await clients[1].close();

    await host.waitFor(
      (s) => !s.players.firstWhere((p) => p.id == p2Id).isConnected,
    );

    final p2Reconnected = await _TestClient.connect(server.port);
    clients[1] = p2Reconnected;
    p2Reconnected.send(ClientMessage(
      type: ClientMessageType.reconnect,
      payload: {
        'roomCode': roomCode,
        'playerId': p2Id,
        'sessionToken': p2Token,
      },
    ));
    final recSnap = await p2Reconnected.waitFor((s) => s.status == RoomStatus.playing);
    expect(recSnap.yourPlayerId, p2Id);
    expect(recSnap.gameState!['me']['role'], p2Snap.gameState!['me']['role']);

    // All confirm roles -> nightWolf
    for (final c in clients) {
      c.send(const ClientMessage(
        type: ClientMessageType.gameAction,
        payload: {'actionType': WerewolfActionType.confirmRole, 'data': {}},
      ));
    }
    final nightSnap = await host.waitFor(
      (s) => s.gameState?['phase'] == 'nightWolf',
    );
    expect(nightSnap.gameState!['dayNumber'], 1);
  });

  test('4 real WebSocket clients create and play a Guandan room over PartyServer', () async {
    final server = PartyServer(
      registry: GamePluginRegistry([
        WerewolfPlugin(random: Random(7)),
        GuandanPlugin(random: Random(7)),
      ]),
      random: Random(7),
    );
    await server.start(address: InternetAddress.loopbackIPv4, port: 0);
    addTearDown(server.stop);

    final clients = <_TestClient>[];
    addTearDown(() async {
      for (final c in clients) {
        await c.close();
      }
    });

    final host = await _TestClient.connect(server.port);
    clients.add(host);
    host.send(const ClientMessage(
      type: ClientMessageType.createRoom,
      payload: {'gameType': 'guandan', 'name': '红1'},
    ));
    final hostSnap = await host.waitFor((s) => s.yourPlayerId != null);
    expect(hostSnap.gameType, GameType.guandan);

    for (var i = 2; i <= 4; i++) {
      final c = await _TestClient.connect(server.port);
      clients.add(c);
      c.send(ClientMessage(
        type: ClientMessageType.joinRoom,
        payload: {'roomCode': hostSnap.roomCode, 'name': '玩家$i'},
      ));
      await c.waitFor((s) => s.yourPlayerId != null);
      c.send(const ClientMessage(type: ClientMessageType.toggleReady));
    }

    await host.waitFor(
      (s) => s.players.length == 4 && s.players.every((p) => p.isReady),
    );

    host.send(const ClientMessage(type: ClientMessageType.startGame));
    for (final c in clients) {
      final snap = await c.waitFor((s) => s.status == RoomStatus.playing);
      expect((snap.gameState!['myHand'] as List).length, 27);
    }

    // Current turn player plays their smallest single card
    final leadClient = clients.firstWhere(
      (c) => c.latestSnapshot!.gameState!['isMyTurn'] == true,
    );
    final hand = (leadClient.latestSnapshot!.gameState!['myHand'] as List)
        .cast<Map<String, dynamic>>();
    final cardId = hand.last['id'] as String;
    leadClient.send(ClientMessage(
      type: ClientMessageType.gameAction,
      payload: {
        'actionType': GuandanActionType.playCards,
        'data': {'cardIds': [cardId]},
      },
    ));

    final afterPlay = await host.waitFor(
      (s) => s.gameState?['lastPlay'] != null,
    );
    expect(afterPlay.gameState!['lastPlay']['type'], 'single');
  });

  test('5 real WebSocket clients create and play One Night Ultimate Werewolf over PartyServer', () async {
    final server = PartyServer(
      registry: GamePluginRegistry([
        WerewolfPlugin(random: Random(7)),
        GuandanPlugin(random: Random(7)),
        OneNightPlugin(random: Random(7)),
      ]),
      random: Random(7),
    );
    await server.start(address: InternetAddress.loopbackIPv4, port: 0);
    addTearDown(server.stop);

    final clients = <_TestClient>[];
    addTearDown(() async {
      for (final c in clients) {
        await c.close();
      }
    });

    final host = await _TestClient.connect(server.port);
    clients.add(host);
    host.send(const ClientMessage(
      type: ClientMessageType.createRoom,
      payload: {'gameType': 'oneNight', 'name': '房主'},
    ));
    final hostSnap = await host.waitFor((s) => s.yourPlayerId != null);
    expect(hostSnap.gameType, GameType.oneNight);

    for (var i = 2; i <= 5; i++) {
      final c = await _TestClient.connect(server.port);
      clients.add(c);
      c.send(ClientMessage(
        type: ClientMessageType.joinRoom,
        payload: {'roomCode': hostSnap.roomCode, 'name': '朋友$i'},
      ));
      await c.waitFor((s) => s.yourPlayerId != null);
      c.send(const ClientMessage(type: ClientMessageType.toggleReady));
    }

    await host.waitFor(
      (s) => s.players.length == 5 && s.players.every((p) => p.isReady),
    );

    host.send(const ClientMessage(type: ClientMessageType.startGame));
    for (final c in clients) {
      final snap = await c.waitFor((s) => s.status == RoomStatus.playing);
      expect(snap.gameState!['phase'], 'roleReveal');
      expect(snap.gameState!['me']['initialRole'], isNotNull);
    }

    for (final c in clients) {
      c.send(const ClientMessage(
        type: ClientMessageType.gameAction,
        payload: {'actionType': OneNightActionType.confirmRole, 'data': {}},
      ));
    }
    final nightSnap = await host.waitFor(
      (s) => s.gameState?['phase'] == 'nightStep',
    );
    expect(nightSnap.gameState!['activeWakeRole'], isNotNull);
  });
}
