import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

/// Plays the incoming-call chime on a loop, like a phone ringing. Auto-stops
/// after [ringFor] (a missed call) unless it's answered or declined first.
/// Shared by both ends: the clone (master dialling in) and the master POS (a
/// clone dialling in).
class RingtoneService {
  // Relative to the `assets/` root — see pubspec `flutter: assets:`.
  static const String _asset = 'audio/7eleven_door.mp3';
  static const Duration ringFor = Duration(seconds: 30);

  // Confirmed safe: the master's incoming-call crash was the modal dialog
  // route, not the audio engine (the crash reproduced with audio disabled).
  static const bool _playEnabled = true;

  // Created lazily so no native audio engine is touched until the first ring.
  AudioPlayer? _player;
  Timer? _timeout;
  bool _ringing = false;

  bool get isRinging => _ringing;

  /// Start ringing on a loop. [onTimeout] fires if the chime rings the full
  /// [ringFor] without being stopped — callers use it to mark the call missed.
  Future<void> start({VoidCallback? onTimeout}) async {
    if (_ringing) return;
    _ringing = true;
    _timeout?.cancel();
    _timeout = Timer(ringFor, () {
      stop();
      onTimeout?.call();
    });
    if (!_playEnabled) return;
    // Audio is best-effort — a playback failure must never break call flow.
    try {
      final p = _player ??= AudioPlayer();
      await p.setReleaseMode(ReleaseMode.loop);
      await p.stop(); // reset if a prior ring is still tearing down
      await p.play(AssetSource(_asset), volume: 1.0);
    } catch (_) {}
  }

  Future<void> stop() async {
    _timeout?.cancel();
    _timeout = null;
    if (!_ringing) return;
    _ringing = false;
    try {
      await _player?.stop();
    } catch (_) {}
  }

  void dispose() {
    _timeout?.cancel();
    _player?.dispose();
  }
}
