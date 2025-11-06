import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';
import 'functions_api.dart';

class GameDataManager {
  final FunctionsApi api;
  GameDataManager({FunctionsApi? api}) : api = api ?? FunctionsApi();

  // Data fetched from backend
  List<Map<String, dynamic>> frames = [];
  // setId -> set data { id, index, questions: [ { id, text, imageUrl, answer } ] }
  final Map<String, Map<String, dynamic>> questionSets = {};
  int progressIndex = -1;
  bool finished = false;
  int version = 0;

  // Preloaded images cache: url -> bytes
  final Map<String, Uint8List> _imageBytes = {};
  final Set<String> _inFlight = <String>{};

  bool get isReady => frames.isNotEmpty || finished;

  // Fetch bulk game data with ID token
  Future<void> fetchInitialData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw StateError('Not authenticated');
    }
  final idToken = await user.getIdToken();
  final res = await api.getGameData(idToken: idToken!);
    if (res['success'] != true) {
      throw StateError('getGameData failed');
    }
    frames = List<Map<String, dynamic>>.from(
      (res['frames'] as List? ?? []).map((e) => Map<String, dynamic>.from(e)),
    );
    final qsRaw = res['questionSets'] as Map? ?? {};
    questionSets
      ..clear()
      ..addAll(qsRaw.map((k, v) => MapEntry(
            k.toString(),
            Map<String, dynamic>.from(v as Map),
          )));
    progressIndex = (res['progressIndex'] is num)
        ? (res['progressIndex'] as num).toInt()
        : -1;
    finished = res['finished'] == true;
    version = (res['version'] is num) ? (res['version'] as num).toInt() : 0;

    // Start preloading images prioritizing from progressIndex onward
    await _preloadAllImages();
  }

  Future<void> _preloadAllImages() async {
    // build ordered list of urls: frames then their elements then questions images
    final urls = <String>[];
    final orderedFrames = List<Map<String, dynamic>>.from(frames);
    orderedFrames.sort((a, b) {
      final ai = (a['index'] is num) ? (a['index'] as num).toInt() : 0;
      final bi = (b['index'] is num) ? (b['index'] as num).toInt() : 0;
      return ai.compareTo(bi);
    });

    // reorder to start from progressIndex
    int start = 0;
    for (int i = 0; i < orderedFrames.length; i++) {
      final idx = (orderedFrames[i]['index'] as num?)?.toInt() ?? -1;
      if (idx >= progressIndex) {
        start = i;
        break;
      }
    }
    final reordered = [
      ...orderedFrames.sublist(start),
      ...orderedFrames.sublist(0, start),
    ];

    for (final f in reordered) {
      final img = (f['imageUrl'] as String?) ?? '';
      if (img.isNotEmpty) urls.add(img);
      final elements = (f['elements'] is List)
          ? List<Map<String, dynamic>>.from(
              (f['elements'] as List).whereType<Map>().map(
                (e) => Map<String, dynamic>.from(e),
              ),
            )
          : <Map<String, dynamic>>[];
      for (final el in elements) {
        final u = (el['imageUrl'] as String?) ?? '';
        if (u.isNotEmpty) urls.add(u);
      }
      final setId = (f['questionSetId'] ?? f['questionSet'] ?? f['setId'])
          ?.toString();
      if (setId != null && setId.isNotEmpty) {
        final set = questionSets[setId];
        if (set != null) {
          final qs = (set['questions'] as List?) ?? [];
          for (final q in qs) {
            final u = (q['imageUrl'] as String?) ?? '';
            if (u.isNotEmpty) urls.add(u);
          }
        }
      }
    }

    // De-duplicate while preserving order
    final seen = <String>{};
    final orderedUnique = <String>[];
    for (final u in urls) {
      if (!seen.contains(u)) {
        seen.add(u);
        orderedUnique.add(u);
      }
    }

    // Fetch in small batches to avoid overwhelming network
    const batch = 6;
    for (int i = 0; i < orderedUnique.length; i += batch) {
      final slice = orderedUnique.sublist(
        i,
        (i + batch > orderedUnique.length) ? orderedUnique.length : i + batch,
      );
      await Future.wait(slice.map(_preloadUrlIfNeeded));
    }
  }

  Future<void> _preloadUrlIfNeeded(String url) async {
    if (_imageBytes.containsKey(url) || _inFlight.contains(url)) return;
    _inFlight.add(url);
    try {
      final r = await http.get(Uri.parse(url));
      if (r.statusCode == 200) {
        _imageBytes[url] = Uint8List.fromList(r.bodyBytes);
      }
    } catch (_) {
      // Ignore failures; rendering will fall back to network
    } finally {
      _inFlight.remove(url);
    }
  }

  Uint8List? getImageBytes(String? url) =>
      (url != null && url.isNotEmpty) ? _imageBytes[url] : null;

  // Local answer checking that mirrors server normalization
  bool isAnswerCorrect({
    required String questionSetId,
    required String questionId,
    required String userAnswer,
  }) {
    final set = questionSets[questionSetId];
    if (set == null) return false;
    final questions = (set['questions'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final q = questions.firstWhere(
      (e) => (e['id']?.toString() ?? '') == questionId,
      orElse: () => <String, dynamic>{},
    );
    if (q.isEmpty) return false;
    final correct = (q['answer']?.toString() ?? '');
    final normalizedGiven = userAnswer.trim().toLowerCase();
    final normalizedCorrect = correct.trim().toLowerCase();
    return normalizedGiven.isNotEmpty && normalizedGiven == normalizedCorrect;
  }

  // Fire-and-forget submit to persist progress on server; non-blocking
  Future<void> submitAnswerNonBlocking({
    required String questionSetId,
    required String questionId,
    required String answer,
  }) async {
    unawaited(() async {
      try {
        final user = FirebaseAuth.instance.currentUser;
        final idToken = (user != null) ? await user.getIdToken() : null;
        await api.submitAnswer(
          idToken: idToken,
          questionSetId: questionSetId,
          questionId: questionId,
          answer: answer,
        );
      } catch (_) {}
    }());
  }
}
