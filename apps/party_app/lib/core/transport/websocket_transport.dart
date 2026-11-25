import 'dart:async';

import 'package:party_core/party_core.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'game_transport.dart';

/// WebSocket client transport used by both Online Mode and LAN Client Mode.
/// Supports automatic heartbeat pings and token-based session reconnection.
class WebSocketGameTransport implements GameTransport {
  WebSocketGameTransport({
    required this.wsUrl,
    required this.mode,
    required this.initialMessage,
  });

  final String wsUrl;
  final ConnectionMode mode;
  final ClientMessage initialMessage;

  final _snapshotsController = StreamController<RoomSnapshot>.broadcast();
  final _eventsController = StreamController<GameEvent>.broadcast();
  final _errorsController = StreamController<String>.broadcast();
  final _statusController = StreamController<TransportStatus>.broadcast();

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _sub;
  Timer? _pingTimer;
  Timer? _reconnectTimer;

  bool _closedByUser = false;
  TransportStatus _status = TransportStatus.disconnected;

  String? _roomCode;
  String? _playerId;
  String? _sessionToken;

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
        mode: mode,
        label: mode == ConnectionMode.online ? '联网模式' : '局域网/热点加入',
        lanWsUrl: mode == ConnectionMode.lanClient ? wsUrl : null,
        onlineServerUrl: mode == ConnectionMode.online ? wsUrl : null,
      );

  Future<void> connect() async {
    _setStatus(TransportStatus.connecting);
    await _openSocket(isReconnect: false);
  }

  Future<void> _openSocket({required bool isReconnect}) async {
    if (_closedByUser) return;
    try {
      final channel = WebSocketChannel.connect(Uri.parse(wsUrl));
      await channel.ready;
      _channel = channel;
      _setStatus(TransportStatus.connected);

      _sub = channel.stream.listen(
        _onRawMessage,
        onDone: _handleDrop,
        onError: (_) => _handleDrop(),
      );

      if (isReconnect &&
          _roomCode != null &&
          _playerId != null &&
          _sessionToken != null) {
        send(ClientMessage(
          type: ClientMessageType.reconnect,
          payload: {
            'roomCode': _roomCode,
            'playerId': _playerId,
            'sessionToken': _sessionToken,
          },
        ));
      } else {
        send(initialMessage);
      }

      _pingTimer?.cancel();
      _pingTimer = Timer.periodic(const Duration(seconds: 15), (_) {
        send(const ClientMessage(type: ClientMessageType.ping));
      });
    } catch (e) {
      if (!isReconnect) {
        _setStatus(TransportStatus.disconnected);
        _errorsController.add('连接服务器失败（$wsUrl）：请检查网络或地址是否正确。');
        rethrow;
      }
      _scheduleReconnect();
    }
  }

  void _onRawMessage(dynamic raw) {
    if (raw is! String) return;
    try {
      final msg = ServerMessage.decode(raw);
      switch (msg.type) {
        case ServerMessageType.roomSnapshot:
          final snap = RoomSnapshot.fromJson(msg.payload);
          _roomCode = snap.roomCode;
          _playerId = snap.yourPlayerId ?? _playerId;
          _sessionToken = snap.sessionToken ?? _sessionToken;
          if (!_snapshotsController.isClosed) {
            _snapshotsController.add(snap);
          }
        case ServerMessageType.gameEvent:
          final ev = GameEvent.fromJson(msg.payload);
          if (!_eventsController.isClosed) {
            _eventsController.add(ev);
          }
        case ServerMessageType.error:
          final text = msg.payload['message'] as String? ?? '发生未知错误';
          if (!_errorsController.isClosed) {
            _errorsController.add(text);
          }
        case ServerMessageType.pong:
          break;
      }
    } catch (_) {}
  }

  void _handleDrop() {
    _pingTimer?.cancel();
    if (_closedByUser) return;
    if (_roomCode != null && _playerId != null && _sessionToken != null) {
      _setStatus(TransportStatus.reconnecting);
      _scheduleReconnect();
    } else {
      _setStatus(TransportStatus.disconnected);
      if (!_errorsController.isClosed) {
        _errorsController.add('与房间断开连接。');
      }
    }
  }

  void _scheduleReconnect() {
    if (_closedByUser) return;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 2), () {
      _openSocket(isReconnect: true);
    });
  }

  @override
  void send(ClientMessage message) {
    try {
      _channel?.sink.add(message.encode());
    } catch (_) {}
  }

  void _setStatus(TransportStatus next) {
    _status = next;
    if (!_statusController.isClosed) {
      _statusController.add(next);
    }
  }

  @override
  Future<void> close() async {
    _closedByUser = true;
    _pingTimer?.cancel();
    _reconnectTimer?.cancel();
    try {
      send(const ClientMessage(type: ClientMessageType.leaveRoom));
    } catch (_) {}
    await _sub?.cancel();
    await _channel?.sink.close();
    await _snapshotsController.close();
    await _eventsController.close();
    await _errorsController.close();
    await _statusController.close();
  }
}
