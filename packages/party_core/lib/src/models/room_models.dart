/// Supported party games in PartyBox.
/// New games (One Night, Guandan, etc.) can register via [GamePluginRegistry].
enum GameType {
  werewolf,
  oneNight,
  guandan;

  String get displayName => switch (this) {
        GameType.werewolf => '狼人杀',
        GameType.oneNight => '一夜终极狼人',
        GameType.guandan => '掼蛋',
      };

  static GameType fromName(String name) {
    return GameType.values.firstWhere(
      (e) => e.name == name,
      orElse: () => GameType.werewolf,
    );
  }
}

/// Network mode for a PartyBox room.
enum ConnectionMode {
  online,
  lanHost,
  lanClient,
  localDemo;

  static ConnectionMode fromName(String name) {
    return ConnectionMode.values.firstWhere(
      (e) => e.name == name,
      orElse: () => ConnectionMode.online,
    );
  }
}

/// Lifecycle stage of a room.
enum RoomStatus {
  lobby,
  playing,
  finished;

  static RoomStatus fromName(String name) {
    return RoomStatus.values.firstWhere(
      (e) => e.name == name,
      orElse: () => RoomStatus.lobby,
    );
  }
}

/// Represents a player seated in a PartyBox room.
class PlayerInfo {
  const PlayerInfo({
    required this.id,
    required this.name,
    required this.seatNumber,
    this.isHost = false,
    this.isReady = false,
    this.isConnected = true,
    this.isBot = false,
    this.avatarIndex = 0,
  });

  final String id;
  final String name;
  final int seatNumber;
  final bool isHost;
  final bool isReady;
  final bool isConnected;
  final bool isBot;
  final int avatarIndex;

  PlayerInfo copyWith({
    String? id,
    String? name,
    int? seatNumber,
    bool? isHost,
    bool? isReady,
    bool? isConnected,
    bool? isBot,
    int? avatarIndex,
  }) {
    return PlayerInfo(
      id: id ?? this.id,
      name: name ?? this.name,
      seatNumber: seatNumber ?? this.seatNumber,
      isHost: isHost ?? this.isHost,
      isReady: isReady ?? this.isReady,
      isConnected: isConnected ?? this.isConnected,
      isBot: isBot ?? this.isBot,
      avatarIndex: avatarIndex ?? this.avatarIndex,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'seatNumber': seatNumber,
        'isHost': isHost,
        'isReady': isReady,
        'isConnected': isConnected,
        'isBot': isBot,
        'avatarIndex': avatarIndex,
      };

  factory PlayerInfo.fromJson(Map<String, dynamic> json) => PlayerInfo(
        id: json['id'] as String,
        name: json['name'] as String,
        seatNumber: json['seatNumber'] as int,
        isHost: json['isHost'] as bool? ?? false,
        isReady: json['isReady'] as bool? ?? false,
        isConnected: json['isConnected'] as bool? ?? true,
        isBot: json['isBot'] as bool? ?? false,
        avatarIndex: json['avatarIndex'] as int? ?? 0,
      );
}

/// Event emitted by the game engine for narrator TTS, sound effects, or toasts.
class GameEvent {
  const GameEvent({
    required this.id,
    required this.type,
    required this.message,
    this.narrationText,
    this.targetPlayerIds,
    this.payload = const {},
  });

  final String id;
  final String type;
  final String message;

  /// Optional Chinese TTS script for the in-person smart moderator.
  final String? narrationText;

  /// If null, broadcast to everyone; otherwise only send to listed players.
  final List<String>? targetPlayerIds;

  final Map<String, dynamic> payload;

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        'message': message,
        if (narrationText != null) 'narrationText': narrationText,
        if (targetPlayerIds != null) 'targetPlayerIds': targetPlayerIds,
        if (payload.isNotEmpty) 'payload': payload,
      };

  factory GameEvent.fromJson(Map<String, dynamic> json) => GameEvent(
        id: json['id'] as String,
        type: json['type'] as String,
        message: json['message'] as String,
        narrationText: json['narrationText'] as String?,
        targetPlayerIds: (json['targetPlayerIds'] as List?)?.cast<String>(),
        payload: Map<String, dynamic>.from(json['payload'] as Map? ?? {}),
      );
}

/// Player-scoped snapshot of a room and its active game state.
class RoomSnapshot {
  const RoomSnapshot({
    required this.roomId,
    required this.roomCode,
    required this.gameType,
    required this.status,
    required this.hostId,
    required this.players,
    required this.gameConfig,
    this.gameState,
    this.yourPlayerId,
    this.sessionToken,
    this.revision = 0,
  });

  final String roomId;
  final String roomCode;
  final GameType gameType;
  final RoomStatus status;
  final String hostId;
  final List<PlayerInfo> players;
  final Map<String, dynamic> gameConfig;

  /// Projected (privacy-filtered) state for [yourPlayerId].
  final Map<String, dynamic>? gameState;

  final String? yourPlayerId;
  final String? sessionToken;
  final int revision;

  PlayerInfo? get me {
    if (yourPlayerId == null) return null;
    for (final p in players) {
      if (p.id == yourPlayerId) return p;
    }
    return null;
  }

  bool get isHost => yourPlayerId != null && yourPlayerId == hostId;

  Map<String, dynamic> toJson() => {
        'roomId': roomId,
        'roomCode': roomCode,
        'gameType': gameType.name,
        'status': status.name,
        'hostId': hostId,
        'players': players.map((p) => p.toJson()).toList(),
        'gameConfig': gameConfig,
        if (gameState != null) 'gameState': gameState,
        if (yourPlayerId != null) 'yourPlayerId': yourPlayerId,
        if (sessionToken != null) 'sessionToken': sessionToken,
        'revision': revision,
      };

  factory RoomSnapshot.fromJson(Map<String, dynamic> json) => RoomSnapshot(
        roomId: json['roomId'] as String,
        roomCode: json['roomCode'] as String,
        gameType: GameType.fromName(json['gameType'] as String),
        status: RoomStatus.fromName(json['status'] as String),
        hostId: json['hostId'] as String,
        players: (json['players'] as List)
            .map((e) => PlayerInfo.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        gameConfig: Map<String, dynamic>.from(json['gameConfig'] as Map? ?? {}),
        gameState: json['gameState'] == null
            ? null
            : Map<String, dynamic>.from(json['gameState'] as Map),
        yourPlayerId: json['yourPlayerId'] as String?,
        sessionToken: json['sessionToken'] as String?,
        revision: json['revision'] as int? ?? 0,
      );
}
