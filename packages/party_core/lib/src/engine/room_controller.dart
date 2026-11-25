import 'dart:math';

import '../models/room_models.dart';
import 'game_plugin.dart';

/// Result returned when a player joins or reconnects to a room.
class JoinResult {
  const JoinResult({
    required this.playerId,
    required this.sessionToken,
    required this.reconnected,
  });

  final String playerId;
  final String sessionToken;
  final bool reconnected;
}

/// Authoritative room state machine shared by the LAN Host and Online Server.
///
/// Manages room lifecycle, player seating, readiness, reconnection tokens,
/// host migration, and delegates active gameplay to the registered [GamePlugin].
class RoomController {
  RoomController({
    required this.roomId,
    required this.roomCode,
    required this.gameType,
    required this.registry,
    Random? random,
  })  : _random = random ?? Random(),
        _gameConfig = registry.requirePlugin(gameType).defaultConfig();

  final String roomId;
  final String roomCode;
  final GameType gameType;
  final GamePluginRegistry registry;
  final Random _random;

  RoomStatus _status = RoomStatus.lobby;
  String _hostId = '';
  final List<PlayerInfo> _players = [];
  final Map<String, String> _sessionTokens = {};
  Map<String, dynamic> _gameConfig;
  dynamic _gameState;
  int _revision = 0;

  RoomStatus get status => _status;
  String get hostId => _hostId;
  List<PlayerInfo> get players => List.unmodifiable(_players);
  Map<String, dynamic> get gameConfig => Map.unmodifiable(_gameConfig);
  dynamic get rawGameState => _gameState;
  int get revision => _revision;

  GamePlugin<dynamic> get _plugin => registry.requirePlugin(gameType);

  JoinResult joinPlayer({
    required String name,
    String? preferredPlayerId,
    int? avatarIndex,
    bool isBot = false,
  }) {
    final trimmedName = name.trim().isEmpty ? '玩家${_players.length + 1}' : name.trim();

    // Allow seamless reconnection if playerId already exists in this room.
    if (preferredPlayerId != null) {
      final existingIdx = _players.indexWhere((p) => p.id == preferredPlayerId);
      if (existingIdx != -1) {
        _players[existingIdx] = _players[existingIdx].copyWith(
          isConnected: true,
          name: trimmedName,
        );
        _revision++;
        return JoinResult(
          playerId: preferredPlayerId,
          sessionToken: _sessionTokens[preferredPlayerId]!,
          reconnected: true,
        );
      }
    }

    if (_status != RoomStatus.lobby) {
      throw const GameRuleException('游戏已经开始，暂不支持中途加入新玩家。');
    }
    if (_players.length >= _plugin.maxPlayers) {
      throw GameRuleException('房间已满（最多 ${_plugin.maxPlayers} 人）。');
    }

    final playerId = preferredPlayerId ?? _generateId('p');
    final token = _generateId('tok');
    final seatNumber = _nextAvailableSeat();
    final isFirst = _players.isEmpty;
    if (isFirst) {
      _hostId = playerId;
    }

    _players.add(
      PlayerInfo(
        id: playerId,
        name: trimmedName,
        seatNumber: seatNumber,
        isHost: isFirst,
        isReady: isFirst || isBot,
        isConnected: true,
        isBot: isBot,
        avatarIndex: avatarIndex ?? (seatNumber - 1) % 8,
      ),
    );
    _sessionTokens[playerId] = token;
    _revision++;

    return JoinResult(
      playerId: playerId,
      sessionToken: token,
      reconnected: false,
    );
  }

  JoinResult reconnectPlayer({
    required String playerId,
    required String sessionToken,
  }) {
    final stored = _sessionTokens[playerId];
    if (stored == null || stored != sessionToken) {
      throw const GameRuleException('重连凭证无效或已过期。');
    }
    final idx = _players.indexWhere((p) => p.id == playerId);
    if (idx == -1) {
      throw const GameRuleException('玩家已不在房间内。');
    }
    _players[idx] = _players[idx].copyWith(isConnected: true);
    _revision++;
    return JoinResult(
      playerId: playerId,
      sessionToken: stored,
      reconnected: true,
    );
  }

  void markDisconnected(String playerId) {
    final idx = _players.indexWhere((p) => p.id == playerId);
    if (idx == -1) return;
    _players[idx] = _players[idx].copyWith(isConnected: false);
    _revision++;
  }

  void leavePlayer(String playerId) {
    if (_status == RoomStatus.playing) {
      // Keep seated during active game so they can reconnect.
      markDisconnected(playerId);
      return;
    }
    _players.removeWhere((p) => p.id == playerId);
    _sessionTokens.remove(playerId);
    if (_hostId == playerId) {
      final nextHost = _players.where((p) => !p.isBot).firstOrNull ?? _players.firstOrNull;
      _hostId = nextHost?.id ?? '';
      for (var i = 0; i < _players.length; i++) {
        _players[i] = _players[i].copyWith(isHost: _players[i].id == _hostId);
      }
    }
    _revision++;
  }

  void removeBot(String hostPlayerId, {String? botId}) {
    _requireHost(hostPlayerId);
    if (_status != RoomStatus.lobby) {
      throw const GameRuleException('游戏进行中无法移除测试机器人。');
    }
    final target = botId != null
        ? _players.where((p) => p.id == botId && p.isBot).firstOrNull
        : _players.where((p) => p.isBot).lastOrNull;
    if (target == null) return;
    _players.removeWhere((p) => p.id == target.id);
    _sessionTokens.remove(target.id);
    _revision++;
  }

  void toggleReady(String playerId) {
    if (_status != RoomStatus.lobby) {
      throw const GameRuleException('当前不在大厅准备阶段。');
    }
    final idx = _players.indexWhere((p) => p.id == playerId);
    if (idx == -1) {
      throw const GameRuleException('未找到玩家。');
    }
    _players[idx] = _players[idx].copyWith(isReady: !_players[idx].isReady);
    _revision++;
  }

  void updateConfig(String hostPlayerId, Map<String, dynamic> newConfig) {
    _requireHost(hostPlayerId);
    if (_status != RoomStatus.lobby) {
      throw const GameRuleException('游戏开始后无法修改板子配置。');
    }
    _gameConfig = Map<String, dynamic>.from(newConfig);
    _revision++;
  }

  List<GameEvent> startGame(String hostPlayerId) {
    _requireHost(hostPlayerId);
    if (_status == RoomStatus.playing) {
      throw const GameRuleException('游戏已经在进行中。');
    }

    final unready = _players.where((p) => !p.isHost && !p.isReady).toList();
    if (unready.isNotEmpty) {
      throw GameRuleException(
        '还有 ${unready.length} 名玩家未准备（${unready.first.name} 等）。',
      );
    }

    final error = _plugin.validateStart(_players, _gameConfig);
    if (error != null) {
      throw GameRuleException(error);
    }

    final transition = _plugin.initGame(_players, _gameConfig);
    _gameState = transition.state;
    _status = transition.isFinished ? RoomStatus.finished : RoomStatus.playing;
    _revision++;
    return transition.events;
  }

  List<GameEvent> handleGameAction(
    String playerId,
    String actionType,
    Map<String, dynamic> payload,
  ) {
    if (_status != RoomStatus.playing || _gameState == null) {
      throw const GameRuleException('当前没有正在进行的对局。');
    }

    final transition = _plugin.handleAction(
      _gameState,
      playerId,
      actionType,
      payload,
      hostId: _hostId,
    );
    _gameState = transition.state;
    if (transition.isFinished) {
      _status = RoomStatus.finished;
    }
    _revision++;
    return transition.events;
  }

  void returnToLobby(String hostPlayerId) {
    _requireHost(hostPlayerId);
    _status = RoomStatus.lobby;
    _gameState = null;
    for (var i = 0; i < _players.length; i++) {
      final p = _players[i];
      _players[i] = p.copyWith(isReady: p.isHost || p.isBot);
    }
    _revision++;
  }

  RoomSnapshot snapshotForPlayer(String playerId, {bool includeToken = false}) {
    Map<String, dynamic>? projected;
    if (_gameState != null) {
      projected = _plugin.projectStateForPlayer(_gameState, playerId);
    }
    return RoomSnapshot(
      roomId: roomId,
      roomCode: roomCode,
      gameType: gameType,
      status: _status,
      hostId: _hostId,
      players: List<PlayerInfo>.from(_players),
      gameConfig: Map<String, dynamic>.from(_gameConfig),
      gameState: projected,
      yourPlayerId: playerId,
      sessionToken: includeToken ? _sessionTokens[playerId] : null,
      revision: _revision,
    );
  }

  void _requireHost(String playerId) {
    if (playerId != _hostId) {
      throw const GameRuleException('只有房主可以执行此操作。');
    }
  }

  int _nextAvailableSeat() {
    final used = _players.map((p) => p.seatNumber).toSet();
    var seat = 1;
    while (used.contains(seat)) {
      seat++;
    }
    return seat;
  }

  String _generateId(String prefix) {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final buf = StringBuffer('${prefix}_');
    for (var i = 0; i < 10; i++) {
      buf.write(chars[_random.nextInt(chars.length)]);
    }
    return buf.toString();
  }
}
