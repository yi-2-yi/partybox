import '../models/room_models.dart';

/// Output of applying a player action or tick to a game state.
class GameTransition<TState> {
  const GameTransition({
    required this.state,
    this.events = const [],
    this.isFinished = false,
  });

  final TState state;
  final List<GameEvent> events;
  final bool isFinished;
}

/// Plugin contract that every party game in PartyBox implements.
///
/// Keeping games behind [GamePlugin] lets [RoomController], the LAN host,
/// and the online relay server host Werewolf today and One Night / Guandan
/// tomorrow without changing networking or lobby code.
abstract class GamePlugin<TState> {
  GameType get gameType;

  int get minPlayers;
  int get maxPlayers;

  /// Default JSON-serializable configuration for this game.
  Map<String, dynamic> defaultConfig();

  /// Validates whether the room can start with [players] and [config].
  /// Returns null if valid, or a user-facing Chinese error message.
  String? validateStart(List<PlayerInfo> players, Map<String, dynamic> config);

  /// Initializes a fresh game state and initial events (e.g. role deal).
  GameTransition<TState> initGame(
    List<PlayerInfo> players,
    Map<String, dynamic> config,
  );

  /// Handles an in-game player action.
  /// Throws [GameRuleException] if the action is invalid for the player/phase.
  GameTransition<TState> handleAction(
    TState state,
    String playerId,
    String actionType,
    Map<String, dynamic> payload, {
    required String hostId,
  });

  /// Projects the authoritative [state] into a privacy-filtered JSON map
  /// safe to transmit to [playerId].
  Map<String, dynamic> projectStateForPlayer(
    TState state,
    String playerId,
  );
}

class GameRuleException implements Exception {
  const GameRuleException(this.message);
  final String message;

  @override
  String toString() => 'GameRuleException: $message';
}

/// Registry holding all installed game plugins.
class GamePluginRegistry {
  GamePluginRegistry(List<GamePlugin<dynamic>> plugins) {
    for (final p in plugins) {
      _plugins[p.gameType] = p;
    }
  }

  final Map<GameType, GamePlugin<dynamic>> _plugins = {};

  GamePlugin<dynamic> requirePlugin(GameType type) {
    final plugin = _plugins[type];
    if (plugin == null) {
      throw GameRuleException('暂不支持该游戏类型：${type.displayName}');
    }
    return plugin;
  }

  bool supports(GameType type) => _plugins.containsKey(type);
}
