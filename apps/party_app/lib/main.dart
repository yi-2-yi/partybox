import 'package:material_ui/material_ui.dart';
import 'package:party_core/party_core.dart';

import 'core/state/app_controller.dart';
import 'core/theme/party_theme.dart';
import 'features/games/guandan/guandan_table_page.dart';
import 'features/games/one_night/one_night_table_page.dart';
import 'features/games/werewolf/werewolf_table_page.dart';
import 'features/home/home_page.dart';
import 'features/lobby/lobby_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const PartyBoxApp());
}

class PartyBoxApp extends StatefulWidget {
  const PartyBoxApp({super.key, this.controller});

  final AppController? controller;

  @override
  State<PartyBoxApp> createState() => _PartyBoxAppState();
}

class _PartyBoxAppState extends State<PartyBoxApp> {
  late final AppController _controller;
  late final bool _ownsController;
  String? _shownError;

  @override
  void initState() {
    super.initState();
    _ownsController = widget.controller == null;
    _controller = widget.controller ?? AppController();
    _controller.loadPreferences();
  }

  @override
  void dispose() {
    if (_ownsController) {
      _controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PartyBox · 聚会桌游盒',
      debugShowCheckedModeBanner: false,
      theme: buildPartyTheme(),
      home: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final error = _controller.lastError;
          if (error != null && error != _shownError) {
            _shownError = error;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              ScaffoldMessenger.of(context)
                ..hideCurrentSnackBar()
                ..showSnackBar(
                  SnackBar(
                    content: Text(error),
                    backgroundColor: PartyColors.wolfRed,
                  ),
                );
              _controller.clearError();
              _shownError = null;
            });
          }

          final snap = _controller.snapshot;
          if (snap == null) {
            return HomePage(controller: _controller);
          }
          if (snap.status == RoomStatus.lobby || snap.gameState == null) {
            return LobbyPage(controller: _controller);
          }
          if (snap.gameType == GameType.guandan) {
            return GuandanTablePage(controller: _controller);
          }
          if (snap.gameType == GameType.oneNight) {
            return OneNightTablePage(controller: _controller);
          }
          return WerewolfTablePage(controller: _controller);
        },
      ),
    );
  }
}
