import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:ui' as ui;
import '../services/functions_api.dart';
import '../services/app_state.dart';
import '../services/music_player.dart';
import 'package:video_player/video_player.dart';
import 'comic_viewer_page.dart';
import '../route_observer.dart';

class CodeEntryPage extends StatefulWidget {
  const CodeEntryPage({super.key});

  @override
  State<CodeEntryPage> createState() => _CodeEntryPageState();
}

class _CodeEntryPageState extends State<CodeEntryPage>
    with SingleTickerProviderStateMixin, RouteAware {
  final _ctrl = TextEditingController();
  String? _error;
  bool _loading = false;
  final _api = FunctionsApi();
  late final AnimationController _animController;
  VideoPlayerController? _bgVideoController;
  bool _bgVideoReady = false;

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
    // start fetching config and initializing background video immediately
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initBackgroundFromConfig();
      // subscribe to route changes so we can resume video when returning
      final modal = ModalRoute.of(context);
      if (modal != null) routeObserver.subscribe(this, modal);
    });
  }

  Future<void> _initBackgroundFromConfig() async {
    try {
      print('DEBUG: initBackgroundFromConfig - start');
      final cfgRes = await _api.fetchConfig();
      print(
        'DEBUG: initBackgroundFromConfig - response: ${cfgRes.runtimeType}',
      );
      if (cfgRes['success'] == true) {
        final bg = cfgRes['backgroundImageUrl'] as String?;
        final bv = cfgRes['backgroundVideoUrl'] as String?;
        print(
          'DEBUG: initBackgroundFromConfig - image present=${bg != null && bg.isNotEmpty} video present=${bv != null && bv.isNotEmpty}',
        );
        if (bg != null && bg.isNotEmpty) {
          final as = Provider.of<AppState>(context, listen: false);
          await as.setBackgroundImageUrl(bg);
          print('DEBUG: initBackgroundFromConfig set backgroundImageUrl: $bg');
        }
        if (bv != null && bv.isNotEmpty) {
          print(
            'DEBUG: initBackgroundFromConfig - backgroundVideoUrl found: $bv',
          );
          if (_bgVideoController != null) {
            try {
              print(
                'DEBUG: disposing previous bg controller before init in initBackgroundFromConfig',
              );
              await _bgVideoController!.dispose();
            } catch (e) {
              print('DEBUG: error disposing previous controller: $e');
            }
          }
          try {
            _bgVideoReady = false;
            _bgVideoController = VideoPlayerController.network(bv);
            print(
              'DEBUG: initializing bgVideoController (initBackgroundFromConfig)',
            );
            await _bgVideoController!.initialize().timeout(
              const Duration(seconds: 12),
              onTimeout: () {
                throw Exception('Video initialization timed out');
              },
            );
            print(
              'DEBUG: bgVideoController initialized successfully in initBackgroundFromConfig',
            );
            _bgVideoController!.setLooping(true);
            _bgVideoController!.setVolume(0.0);
            await _bgVideoController!.play();
            _bgVideoReady = true;
            print(
              'DEBUG: Background video is now playing (initBackgroundFromConfig)',
            );
          } catch (e, st) {
            print(
              'DEBUG: Failed to init/play background video in initBackgroundFromConfig: $e\n$st',
            );
            try {
              await _bgVideoController?.dispose();
            } catch (_) {}
            _bgVideoController = null;
            _bgVideoReady = false;
          }
        }
      } else {
        print(
          'DEBUG: initBackgroundFromConfig returned success!=true: $cfgRes',
        );
      }
      print('DEBUG: initBackgroundFromConfig - end');
    } catch (e, st) {
      print('DEBUG: initBackgroundFromConfig failed: $e\n$st');
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _animController.dispose();
    if (_bgVideoController != null) {
      try {
        print('DEBUG: disposing background video controller');
        _bgVideoController!.dispose();
      } catch (e) {
        print('DEBUG: error disposing bg video controller: $e');
      }
    }
    super.dispose();
  }

  @override
  void didPopNext() {
    // Called when the top route has been popped and this route shows up again.
    // Re-init the background video so it resumes playing on the entry page.
    print('DEBUG: CodeEntryPage.didPopNext - reinitializing background video');
    // Fire off re-init but don't await here.
    _initBackgroundFromConfig();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Ensure we're subscribed if dependencies change and route is available
    final modal = ModalRoute.of(context);
    if (modal != null) routeObserver.subscribe(this, modal);
  }

  @override
  void deactivate() {
    // unsubscribe to avoid leaks
    try {
      routeObserver.unsubscribe(this);
    } catch (_) {}
    super.deactivate();
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
      // config is fetched on page load; no need to refetch here
      if (!mounted) return;
      // Ensure background video does not continue playing under the viewer.
      if (_bgVideoController != null) {
        try {
          print('DEBUG: stopping background video before navigation');
          await _bgVideoController!.pause();
        } catch (e) {
          print('DEBUG: error pausing bg video: $e');
        }
        try {
          await _bgVideoController!.dispose();
        } catch (e) {
          print('DEBUG: error disposing bg video before navigation: $e');
        }
        _bgVideoController = null;
        _bgVideoReady = false;
      }

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
          return Stack(
            children: [
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      const Color.fromARGB(255, 225, 49, 0), // light yellow
                      const Color.fromARGB(255, 255, 208, 0), // dirty yellow
                    ],
                    begin: begin,
                    end: end,
                  ),
                ),
              ),
              if (_bgVideoReady &&
                  _bgVideoController != null &&
                  _bgVideoController!.value.isInitialized)
                Positioned.fill(
                  child: FittedBox(
                    fit: BoxFit.cover,
                    child: SizedBox(
                      width: _bgVideoController!.value.size.width,
                      height: _bgVideoController!.value.size.height,
                      child: VideoPlayer(_bgVideoController!),
                    ),
                  ),
                ),
              Positioned.fill(child: child!),
            ],
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
                    Text(
                      'Enter Registration Code',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(
                          context,
                        ).colorScheme.primary, // Match background
                      ),
                    ),
                    const SizedBox(height: 20),
                    TextField(
                      controller: _ctrl,
                      decoration: InputDecoration(
                        labelText: 'Code',
                        labelStyle: TextStyle(
                          color: Theme.of(
                            context,
                          ).colorScheme.primary.withValues(alpha: 0.7),
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
                            color: Theme.of(
                              context,
                            ).colorScheme.primary.withValues(alpha: 0.3),
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(
                            color: Theme.of(context).colorScheme.primary,
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
                              color: Theme.of(
                                context,
                              ).colorScheme.primary.withValues(alpha: 0.8),
                            ),
                          ),
                        ),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Theme.of(
                              context,
                            ).colorScheme.primary,
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
