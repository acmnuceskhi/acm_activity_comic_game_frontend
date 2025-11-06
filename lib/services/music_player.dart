// Web-only audio preloader/player. Uses dart:html AudioElement to preload and play sounds.
import 'dart:async';
import 'dart:html' as html;

class MusicPlayer {
  final Map<String, html.AudioElement> _cache = {};
  final Map<String, String> _urls = {}; // id -> url (for on-demand play)
  String? _currentId;

  Future<void> preload(Map<String, String> musics) async {
    final futures = <Future>[];
    musics.forEach((id, url) {
      _urls[id] = url; // remember URL for on-demand creation
      if (!_cache.containsKey(id)) {
        final audio = html.AudioElement(url)..preload = 'auto';
        // start loading
        audio.load();
        _cache[id] = audio;
        // wait for canplaythrough or error
        final completer = Completer();
        audio.onCanPlayThrough.first.then((_) => completer.complete());
        audio.onError.first.then((_) => completer.complete());
        futures.add(completer.future);
      }
    });
    await Future.wait(futures);
  }

  void play(String? id, {bool loop = true}) {
    if (id == null) return;
    if (_currentId == id) return; // continue playing
    stop();
    var audio = _cache[id];
    // If not preloaded yet, create on-demand if we have a URL
    if (audio == null) {
      final url = _urls[id];
      if (url != null && url.isNotEmpty) {
        audio = html.AudioElement(url)..preload = 'auto';
        audio.load();
        _cache[id] = audio;
      }
    }
    if (audio == null) return;
    audio.loop = loop;
    audio.play();
    _currentId = id;
  }

  void stop() {
    if (_currentId != null) {
      final a = _cache[_currentId!];
      try {
        a?.pause();
        a?.currentTime = 0;
      } catch (_) {}
      _currentId = null;
    }
  }

  void dispose() {
    _cache.values.forEach((a) {
      try {
        a.pause();
        a.src = '';
      } catch (_) {}
    });
    _cache.clear();
    _currentId = null;
  }
}

final globalMusicPlayer = MusicPlayer();
