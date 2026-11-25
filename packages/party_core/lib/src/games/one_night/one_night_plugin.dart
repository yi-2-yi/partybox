import 'dart:math';

import '../../engine/game_plugin.dart';
import '../../models/room_models.dart';
import 'one_night_engine.dart';
import 'one_night_models.dart';

/// Adapts [OneNightEngine] to PartyBox's multi-game [GamePlugin] interface.
class OneNightPlugin extends GamePlugin<OneNightState> {
  OneNightPlugin({Random? random}) : _engine = OneNightEngine(random: random);

  final OneNightEngine _engine;

  @override
  GameType get gameType => GameType.oneNight;

  @override
  int get minPlayers => 3;

  @override
  int get maxPlayers => 10;

  @override
  Map<String, dynamic> defaultConfig() => OneNightConfig.preset5().toJson();

  @override
  String? validateStart(List<PlayerInfo> players, Map<String, dynamic> config) {
    return _engine.validateStart(players, OneNightConfig.fromJson(config));
  }

  @override
  GameTransition<OneNightState> initGame(
    List<PlayerInfo> players,
    Map<String, dynamic> config,
  ) {
    return _engine.initGame(players, OneNightConfig.fromJson(config));
  }

  @override
  GameTransition<OneNightState> handleAction(
    OneNightState state,
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
    OneNightState state,
    String playerId,
  ) {
    return _engine.projectStateForPlayer(state, playerId);
  }
}
