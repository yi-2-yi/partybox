import 'dart:math';

import '../../engine/game_plugin.dart';
import '../../models/room_models.dart';
import 'guandan_engine.dart';
import 'guandan_models.dart';

/// Adapts [GuandanEngine] to PartyBox's multi-game [GamePlugin] interface.
class GuandanPlugin extends GamePlugin<GuandanState> {
  GuandanPlugin({Random? random}) : _engine = GuandanEngine(random: random);

  final GuandanEngine _engine;

  @override
  GameType get gameType => GameType.guandan;

  @override
  int get minPlayers => 4;

  @override
  int get maxPlayers => 4;

  @override
  Map<String, dynamic> defaultConfig() => const GuandanConfig().toJson();

  @override
  String? validateStart(List<PlayerInfo> players, Map<String, dynamic> config) {
    return _engine.validateStart(players, GuandanConfig.fromJson(config));
  }

  @override
  GameTransition<GuandanState> initGame(
    List<PlayerInfo> players,
    Map<String, dynamic> config,
  ) {
    return _engine.initGame(players, GuandanConfig.fromJson(config));
  }

  @override
  GameTransition<GuandanState> handleAction(
    GuandanState state,
    String playerId,
    String actionType,
    Map<String, dynamic> payload, {
    required String hostId,
  }) {
    return _engine.handleAction(
      state,
      playerId,
      actionType,
      payload,
      hostId: hostId,
    );
  }

  @override
  Map<String, dynamic> projectStateForPlayer(
    GuandanState state,
    String playerId,
  ) {
    return _engine.projectStateForPlayer(state, playerId);
  }
}
