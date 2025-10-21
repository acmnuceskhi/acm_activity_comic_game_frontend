import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:ui' as ui;
import '../services/functions_api.dart';
import '../services/app_state.dart';
import '../services/music_player.dart';
import 'comic_viewer_page.dart';

class CodeEntryPage extends StatefulWidget {
  const CodeEntryPage({super.key});

  @override
  State<CodeEntryPage> createState() => _CodeEntryPageState();
}

class _CodeEntryPageState extends State<CodeEntryPage>
    with SingleTickerProviderStateMixin {
  final _ctrl = TextEditingController();
  String? _error;
  bool _loading = false;
  final _api = FunctionsApi();
  late final AnimationController _animController;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    )..repeat(reverse: true);
    // load initial code from provider (already loaded in main)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final as = Provider.of<AppState>(context, listen: false);
      if (as.code.isNotEmpty) _ctrl.text = as.code;
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _animController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final code = _ctrl.text.trim();
    try {
      final res = await _api.getNextFrames(code);
      // debug: log cached background URL and fetched frames info
      try {
        final appState = Provider.of<AppState>(context, listen: false);
        print(
          'DEBUG: AppState.backgroundImageUrl=${appState.backgroundImageUrl}',
        );
      } catch (e) {
        print('DEBUG: failed to read AppState background url: $e');
      }
      if (res['success'] != true) {
        // log response for debugging
        print('getNextFrames returned success!=true for code=$code: $res');
        setState(() {
          _error = res['message']?.toString() ?? 'Invalid code';
          _loading = false;
        });
        return;
      }
      // persist to provider (which saves to shared_preferences)
      final as = Provider.of<AppState>(context, listen: false);
      await as.setCode(code);

      // preload music library in background (web-only)
      try {
        final mus = await _api.getMusicLibrary();
        if (mus['success'] == true && mus['musics'] is Map) {
          final map = Map<String, dynamic>.from(mus['musics']);
          final cast = <String, String>{};
          map.forEach((k, v) {
            if (v is String) cast[k] = v;
          });
          // don't await heavy preload on UI thread; start in background
          globalMusicPlayer.preload(cast);
        }
      } catch (e) {
        print('Failed to preload music library: $e');
      }

      // navigate to viewer with received frames
      final frames = res['frames'] as List<dynamic>? ?? [];
      final questions = res['questions'] as List<dynamic>? ?? [];
      final finished = res['finished'] == true;
      print(
        'DEBUG: getNextFrames fetched ${frames.length} frames, finished=$finished at ${DateTime.now().toIso8601String()}',
      );
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ComicViewerPage(
            code: code,
            initialFrames: frames,
            initialQuestions: questions,
            finished: finished,
          ),
        ),
      );
    } catch (e) {
      // log for console
      print('CodeEntryPage._submit exception: $e');
      try {
        throw e;
      } catch (e, st) {
        print(st);
      }
      setState(() {
        _error = 'Request failed: $e';
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      body: AnimatedBuilder(
        animation: _animController,
        builder: (context, child) {
          final v = _animController.value;
          final begin = Alignment.lerp(
            Alignment.topLeft,
            Alignment.topRight,
            v,
          )!;
          final end = Alignment.lerp(
            Alignment.bottomRight,
            Alignment.bottomLeft,
            v,
          )!;
          return Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  const Color(0xFFFFF7CC), // light yellow
                  const Color(0xFFD4C649), // dirty yellow
                ],
                begin: begin,
                end: end,
              ),
            ),
            child: child,
          );
        },
        child: Center(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 6.0, sigmaY: 6.0),
              child: Container(
                width: MediaQuery.of(context).size.width * 0.85 < 600
                    ? MediaQuery.of(context).size.width * 0.85
                    : 600,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(
                    0xFF2C2A1F,
                  ).withValues(alpha: 0.85), // Dark complementary color
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.14),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.25),
                      blurRadius: 12,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Enter Registration Code',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFFD4C649), // Match background
                      ),
                    ),
                    const SizedBox(height: 20),
                    TextField(
                      controller: _ctrl,
                      decoration: InputDecoration(
                        labelText: 'Code',
                        labelStyle: TextStyle(
                          color: const Color(0xFFD4C649).withValues(alpha: 0.7),
                        ),
                        errorText: _error,
                        filled: true,
                        fillColor: Colors.white.withValues(alpha: 0.06),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide.none,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(
                            color: const Color(
                              0xFFD4C649,
                            ).withValues(alpha: 0.3),
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(
                            color: Color(0xFFD4C649),
                          ),
                        ),
                      ),
                      style: const TextStyle(color: Colors.white),
                      onSubmitted: (_) => _submit(),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        TextButton(
                          onPressed: () async {
                            Uri url = Uri.parse(
                              'https://www.activities.acmnuceskhi.com/',
                            );
                            await launchUrl(url);
                          },
                          child: Text(
                            'Register new code',
                            style: TextStyle(
                              decoration: TextDecoration.underline,
                              color: const Color(
                                0xFFD4C649,
                              ).withValues(alpha: 0.8),
                            ),
                          ),
                        ),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFD4C649),
                            foregroundColor: const Color(0xFF2C2A1F),
                            elevation: 4,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 12,
                            ),
                          ),
                          onPressed: _loading ? null : _submit,
                          child: _loading
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      Color(0xFF2C2A1F),
                                    ),
                                  ),
                                )
                              : const Text(
                                  'Continue',
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                        ),
                      ],
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Text(_error!, style: const TextStyle(color: Colors.red)),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
