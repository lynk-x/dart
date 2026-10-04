import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

/// Plays the two short call-lifecycle tones (join/end) heard by everyone
/// on a forum live call — mirrors the join/leave chime convention of
/// Zoom/Meet-style call apps. Deliberately limited to call start/end only,
/// not per-participant join/leave (would be a chime storm in a busy call
/// with several co-hosts) — see ForumAudioStreamCubit's 'start_stream'/
/// 'end_stream' handling, the only two call sites that trigger this.
///
/// A fresh [AudioPlayer] per play() call rather than one reused instance:
/// these tones are short and infrequent (at most once per call lifecycle
/// transition), so there's no instance-reuse state worth managing, and a
/// fresh player can't be left in a bad state by a previous play() that
/// overlapped or errored.
class CallSoundService {
  static Future<void> playJoin() => _play('audio/call_join.mp3');
  static Future<void> playEnd() => _play('audio/call_end.mp3');

  static Future<void> _play(String assetPath) async {
    try {
      final player = AudioPlayer();
      await player.play(AssetSource(assetPath));
      // Dispose once playback finishes rather than immediately — an
      // immediate dispose would cut the sound off before it's heard.
      player.onPlayerComplete.first.then((_) => player.dispose());
    } catch (e) {
      debugPrint('[CallSoundService] Could not play $assetPath: $e');
    }
  }
}
