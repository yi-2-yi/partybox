import 'package:flutter_tts/flutter_tts.dart';

/// Smart Chinese moderator voice narrator using device TTS.
/// Fails silently on platforms/tests without TTS support.
class NarratorService {
  NarratorService({this.enabled = true});

  final FlutterTts _tts = FlutterTts();
  bool enabled;
  bool _initialized = false;

  Future<void> _ensureInit() async {
    if (_initialized) return;
    _initialized = true;
    try {
      await _tts.setLanguage('zh-CN');
      await _tts.setSpeechRate(0.48);
      await _tts.setVolume(1.0);
      await _tts.setPitch(1.0);
    } catch (_) {
      // Ignore in widget tests or platforms without TTS.
    }
  }

  Future<void> speak(String text) async {
    if (!enabled || text.trim().isEmpty) return;
    await _ensureInit();
    try {
      await _tts.stop();
      await _tts.speak(text);
    } catch (_) {
      // Ignore gracefully.
    }
  }

  Future<void> stop() async {
    if (!_initialized) return;
    try {
      await _tts.stop();
    } catch (_) {}
  }
}
