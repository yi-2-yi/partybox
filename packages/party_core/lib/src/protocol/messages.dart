import 'dart:convert';

import '../models/room_models.dart';

/// Client-to-server WebSocket message types.
class ClientMessageType {
  static const createRoom = 'create_room';
  static const joinRoom = 'join_room';
  static const reconnect = 'reconnect';
  static const leaveRoom = 'leave_room';
  static const updateConfig = 'update_config';
  static const toggleReady = 'toggle_ready';
  static const addBot = 'add_bot';
  static const removeBot = 'remove_bot';
  static const startGame = 'start_game';
  static const returnToLobby = 'return_to_lobby';
  static const gameAction = 'game_action';
  static const ping = 'ping';
}

/// Server-to-client WebSocket message types.
class ServerMessageType {
  static const roomSnapshot = 'room_snapshot';
  static const gameEvent = 'game_event';
  static const error = 'error';
  static const pong = 'pong';
}

class ClientMessage {
  const ClientMessage({
    required this.type,
    this.payload = const {},
  });

  final String type;
  final Map<String, dynamic> payload;

  String encode() => jsonEncode({
        'type': type,
        'payload': payload,
      });

  factory ClientMessage.decode(String raw) {
    final map = jsonDecode(raw) as Map<String, dynamic>;
    return ClientMessage(
      type: map['type'] as String,
      payload: Map<String, dynamic>.from(map['payload'] as Map? ?? {}),
    );
  }
}

class ServerMessage {
  const ServerMessage({
    required this.type,
    this.payload = const {},
  });

  final String type;
  final Map<String, dynamic> payload;

  String encode() => jsonEncode({
        'type': type,
        'payload': payload,
      });

  factory ServerMessage.decode(String raw) {
    final map = jsonDecode(raw) as Map<String, dynamic>;
    return ServerMessage(
      type: map['type'] as String,
      payload: Map<String, dynamic>.from(map['payload'] as Map? ?? {}),
    );
  }

  static ServerMessage snapshot(RoomSnapshot snapshot) => ServerMessage(
        type: ServerMessageType.roomSnapshot,
        payload: snapshot.toJson(),
      );

  static ServerMessage event(GameEvent event) => ServerMessage(
        type: ServerMessageType.gameEvent,
        payload: event.toJson(),
      );

  static ServerMessage error(String message, {String? code}) => ServerMessage(
        type: ServerMessageType.error,
        payload: {
          'message': message,
          if (code != null) 'code': code,
        },
      );

  static ServerMessage pong() => const ServerMessage(type: ServerMessageType.pong);
}
