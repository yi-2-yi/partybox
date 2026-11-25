import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:party_core/party_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../audio/narrator_service.dart';
import '../transport/game_transport.dart';
import '../transport/lan_host_transport.dart';
import '../transport/local_demo_transport.dart';
import '../transport/websocket_transport.dart';

/// Top-level reactive controller managing the user's profile, active room
/// transport, snapshot state, narrator TTS, and error banners.
class AppController extends ChangeNotifier {
  AppController({NarratorService? narrator})
      : narrator = narrator ?? NarratorService();

  static const _kNicknameKey = 'partybox_nickname';
  static const _kServerUrlKey = 'partybox_server_url';

  final NarratorService narrator;

  String nickname = '玩家小明';
  String onlineServerUrl = 'ws://127.0.0.1:8080/ws';
  bool ttsEnabled = true;

  GameTransport? _transport;
  StreamSubscription<RoomSnapshot>? _snapSub;
  StreamSubscription<GameEvent>? _eventSub;
  StreamSubscription<String>? _errorSub;
  StreamSubscription<TransportStatus>? _statusSub;

  RoomSnapshot? snapshot;
  TransportStatus connectionStatus = TransportStatus.disconnected;
  String? lastError;
  GameEvent? latestEvent;
  bool isBusy = false;

  TransportEndpointInfo? get endpointInfo => _transport?.endpointInfo;
  bool get inRoom => snapshot != null;

  Future<void> loadPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      nickname = prefs.getString(_kNicknameKey) ?? nickname;
      onlineServerUrl = prefs.getString(_kServerUrlKey) ?? onlineServerUrl;
      notifyListeners();
    } catch (_) {}
  }

  Future<void> updateNickname(String value) async {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return;
    nickname = trimmed;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kNicknameKey, trimmed);
    } catch (_) {}
  }

  Future<void> updateOnlineServerUrl(String value) async {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return;
    onlineServerUrl = trimmed;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kServerUrlKey, trimmed);
    } catch (_) {}
  }

  void toggleTts() {
    ttsEnabled = !ttsEnabled;
    narrator.enabled = ttsEnabled;
    if (!ttsEnabled) {
      narrator.stop();
    }
    notifyListeners();
  }

  void clearError() {
    lastError = null;
    notifyListeners();
  }

  Future<void> startLocalDemo({WerewolfConfig? preset}) async {
    await _resetConnection();
    isBusy = true;
    lastError = null;
    notifyListeners();

    try {
      final transport = LocalDemoTransport(
        playerName: nickname,
        gameType: GameType.werewolf,
        werewolfConfig: preset ?? WerewolfConfig.preset6(),
      );
      _attachTransport(transport);
    } catch (e) {
      lastError = e.toString();
    } finally {
      isBusy = false;
      notifyListeners();
    }
  }

  Future<void> startGuandanDemo({GuandanConfig? config}) async {
    await _resetConnection();
    isBusy = true;
    lastError = null;
    notifyListeners();

    try {
      final transport = LocalDemoTransport(
        playerName: nickname,
        gameType: GameType.guandan,
        guandanConfig: config ?? const GuandanConfig(),
      );
      _attachTransport(transport);
    } catch (e) {
      lastError = e.toString();
    } finally {
      isBusy = false;
      notifyListeners();
    }
  }

  Future<void> startOneNightDemo({OneNightConfig? preset}) async {
    await _resetConnection();
    isBusy = true;
    lastError = null;
    notifyListeners();

    try {
      final transport = LocalDemoTransport(
        playerName: nickname,
        gameType: GameType.oneNight,
        oneNightConfig: preset ?? OneNightConfig.preset5(),
      );
      _attachTransport(transport);
    } catch (e) {
      lastError = e.toString();
    } finally {
      isBusy = false;
      notifyListeners();
    }
  }

  Future<void> startLanHost({GameType gameType = GameType.werewolf}) async {
    await _resetConnection();
    isBusy = true;
    lastError = null;
    notifyListeners();

    try {
      final transport = await createLanHostTransport(
        hostName: nickname,
        gameType: gameType,
      );
      _attachTransport(transport);
    } catch (e) {
      lastError = e.toString().replaceFirst('UnsupportedError: ', '');
    } finally {
      isBusy = false;
      notifyListeners();
    }
  }

  Future<void> joinLanRoom(String wsUrl) async {
    await _resetConnection();
    isBusy = true;
    lastError = null;
    notifyListeners();

    try {
      final normalized = _normalizeWsUrl(wsUrl, defaultPort: 8765);
      final transport = WebSocketGameTransport(
        wsUrl: normalized,
        mode: ConnectionMode.lanClient,
        initialMessage: ClientMessage(
          type: ClientMessageType.joinRoom,
          payload: {'name': nickname},
        ),
      );
      _attachTransport(transport);
      await transport.connect();
    } catch (e) {
      await _resetConnection();
      lastError = '连接局域网房间失败，请确认双方在同一 Wi-Fi 或手机热点下，且地址正确。';
    } finally {
      isBusy = false;
      notifyListeners();
    }
  }

  Future<void> createOnlineRoom({
    required String serverUrl,
    GameType gameType = GameType.werewolf,
  }) async {
    await updateOnlineServerUrl(serverUrl);
    await _resetConnection();
    isBusy = true;
    lastError = null;
    notifyListeners();

    try {
      final normalized = _normalizeWsUrl(serverUrl, defaultPort: 8080);
      final transport = WebSocketGameTransport(
        wsUrl: normalized,
        mode: ConnectionMode.online,
        initialMessage: ClientMessage(
          type: ClientMessageType.createRoom,
          payload: {
            'gameType': gameType.name,
            'name': nickname,
          },
        ),
      );
      _attachTransport(transport);
      await transport.connect();
    } catch (_) {
      await _resetConnection();
      lastError = '无法连接到联网服务器（$serverUrl），请确认服务器已启动或切换局域网/热点模式。';
    } finally {
      isBusy = false;
      notifyListeners();
    }
  }

  Future<void> joinOnlineRoom({
    required String serverUrl,
    required String roomCode,
  }) async {
    await updateOnlineServerUrl(serverUrl);
    await _resetConnection();
    isBusy = true;
    lastError = null;
    notifyListeners();

    try {
      final normalized = _normalizeWsUrl(serverUrl, defaultPort: 8080);
      final transport = WebSocketGameTransport(
        wsUrl: normalized,
        mode: ConnectionMode.online,
        initialMessage: ClientMessage(
          type: ClientMessageType.joinRoom,
          payload: {
            'roomCode': roomCode.trim(),
            'name': nickname,
          },
        ),
      );
      _attachTransport(transport);
      await transport.connect();
    } catch (_) {
      await _resetConnection();
      lastError = '加入联网房间失败，请检查服务器地址和房间号。';
    } finally {
      isBusy = false;
      notifyListeners();
    }
  }

  void updateConfig(WerewolfConfig config) {
    _transport?.send(ClientMessage(
      type: ClientMessageType.updateConfig,
      payload: {'config': config.toJson()},
    ));
  }

  void updateGuandanConfig(GuandanConfig config) {
    _transport?.send(ClientMessage(
      type: ClientMessageType.updateConfig,
      payload: {'config': config.toJson()},
    ));
  }

  void updateOneNightConfig(OneNightConfig config) {
    _transport?.send(ClientMessage(
      type: ClientMessageType.updateConfig,
      payload: {'config': config.toJson()},
    ));
  }

  void toggleReady() {
    _transport?.send(const ClientMessage(type: ClientMessageType.toggleReady));
  }

  void addBot({int count = 1}) {
    _transport?.send(ClientMessage(
      type: ClientMessageType.addBot,
      payload: {'count': count},
    ));
  }

  void removeBot() {
    _transport?.send(const ClientMessage(type: ClientMessageType.removeBot));
  }

  void startGame() {
    _transport?.send(const ClientMessage(type: ClientMessageType.startGame));
  }

  void returnToLobby() {
    _transport?.send(const ClientMessage(type: ClientMessageType.returnToLobby));
  }

  void sendGameAction(String actionType, [Map<String, dynamic> data = const {}]) {
    _transport?.send(ClientMessage(
      type: ClientMessageType.gameAction,
      payload: {
        'actionType': actionType,
        'data': data,
      },
    ));
  }

  Future<void> leaveRoom() async {
    await narrator.stop();
    await _resetConnection();
    notifyListeners();
  }

  void _attachTransport(GameTransport transport) {
    _transport = transport;
    connectionStatus = transport.status;

    _snapSub = transport.snapshots.listen((snap) {
      snapshot = snap;
      lastError = null;
      notifyListeners();
    });

    _eventSub = transport.events.listen((ev) {
      latestEvent = ev;
      // In-person smart moderator: speak TTS on Host / Demo device by default
      // so multiple phones don't echo at the same table.
      final shouldSpeak = ttsEnabled &&
          ev.narrationText != null &&
          (snapshot?.isHost == true ||
              endpointInfo?.mode == ConnectionMode.localDemo);
      if (shouldSpeak) {
        narrator.speak(ev.narrationText!);
      }
      notifyListeners();
    });

    _errorSub = transport.errors.listen((msg) {
      lastError = msg;
      notifyListeners();
    });

    _statusSub = transport.statusStream.listen((st) {
      connectionStatus = st;
      notifyListeners();
    });
  }

  Future<void> _resetConnection() async {
    await _snapSub?.cancel();
    await _eventSub?.cancel();
    await _errorSub?.cancel();
    await _statusSub?.cancel();
    _snapSub = null;
    _eventSub = null;
    _errorSub = null;
    _statusSub = null;

    await _transport?.close();
    _transport = null;
    snapshot = null;
    latestEvent = null;
    connectionStatus = TransportStatus.disconnected;
  }

  String _normalizeWsUrl(String raw, {required int defaultPort}) {
    var trimmed = raw.trim();
    if (!trimmed.startsWith('ws://') && !trimmed.startsWith('wss://')) {
      trimmed = 'ws://$trimmed';
    }
    final uri = Uri.parse(trimmed);
    final port = uri.hasPort ? uri.port : defaultPort;
    final path = uri.path.isEmpty || uri.path == '/' ? '/ws' : uri.path;
    return uri.replace(port: port, path: path).toString();
  }

  @override
  void dispose() {
    _resetConnection();
    super.dispose();
  }
}
