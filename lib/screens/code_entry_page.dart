// ignore_for_file: avoid_print

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:provider/provider.dart';
import 'dart:ui' as ui;
import '../services/functions_api.dart';
import '../services/app_state.dart';
import '../services/music_player.dart';
import '../services/game_data_manager.dart';
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
  // String? _error; // no longer used
  bool _loading = false;
  final _api = FunctionsApi();
  // Google sign-in state
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();
  bool _signedIn = false;
  String? _userName;
  // String? _userEmail; // not displayed
  bool _isSigningIn = false;
  late final AnimationController _animController;
  VideoPlayerController? _bgVideoController;
  bool _bgVideoReady = false;
  String? idToken;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    )..repeat(reverse: true);
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

  // ...existing sign-in logic is implemented in _signInWithGoogleAndStart()

  Future<void> _signInWithGoogle() async {
    try {
      setState(() {
        _isSigningIn = true;
      });

      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) return; // user cancelled

      final googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final userCred = await _auth.signInWithCredential(credential);
      final user = userCred.user;
      final String? emailRaw = user?.email ?? googleUser.email;
      if (emailRaw == null) {
        try {
          await _auth.signOut();
        } catch (_) {}
        try {
          await _googleSignIn.signOut();
        } catch (_) {}
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to obtain email from Google account.'),
            ),
          );
        }
        return;
      }

  // final email = emailRaw.toLowerCase();
      setState(() {
        _signedIn = true;
        _userName = user?.displayName ?? googleUser.displayName ?? '';
      });

      // obtain ID token and call backend
      idToken = await user!.getIdToken();

      // persist uid locally
      // ignore: use_build_context_synchronously
      final as = Provider.of<AppState>(context, listen: false);
      await as.setUid(user.uid);
      print("UID: ${as.uid}");
    } catch (e, st) {
      if (kDebugMode) {
        print('CodeEntryPage._signInWithGoogleAndStart exception: $e');
        print(st);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sign-in failed. Please try again.')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSigningIn = false;
        });
      }
    }
  }

  Future<void> _start() async {
    if (_signedIn) {
      try {
        setState(() {
          _loading = true;
        });

  final as = Provider.of<AppState>(context, listen: false);
  // Use bulk game data endpoint + preloader
  final manager = GameDataManager();
        await manager.fetchInitialData();

        // preload music
        try {
          final mus = await _api.getMusicLibrary();
          if (mus['success'] == true && mus['musics'] is Map) {
            final map = Map<String, dynamic>.from(mus['musics']);
            final cast = <String, String>{};
            map.forEach((k, v) {
              if (v is String) cast[k] = v;
            });
            globalMusicPlayer.preload(cast);
          }
        } catch (e) {
          if (kDebugMode) {
            print('Failed to preload music library: $e');
          }
        }

        final frames = manager.frames;
        // Build questions list compatible with viewer's expectation
        final questions = <Map<String, dynamic>>[];
        for (final f in frames) {
          final setId = (f['questionSetId'] ?? f['questionSet'] ?? f['setId'])
              ?.toString();
          if (setId == null || setId.isEmpty) {
            questions.add({
              'frameIndex': f['index'],
              'setId': null,
              'question': null,
            });
            continue;
          }
          final set = manager.questionSets[setId];
          if (set == null) {
            questions.add({
              'frameIndex': f['index'],
              'setId': setId,
              'question': null,
            });
            continue;
          }
          // pick first question for deterministic UX; local check will use same
          final qs = (set['questions'] as List?) ?? [];
          Map<String, dynamic>? qObj;
          if (qs.isNotEmpty) {
            final q = Map<String, dynamic>.from(qs.first as Map);
            qObj = {
              'id': q['id']?.toString(),
              'text': q['text']?.toString() ?? '',
              'imageUrl': q['imageUrl'],
            };
          }
          questions.add({
            'frameIndex': f['index'],
            'setId': setId,
            'question': qObj,
          });
        }
        final finished = manager.finished;

        if (!mounted) return;
        if (_bgVideoController != null) {
          try {
            await _bgVideoController!.pause();
          } catch (_) {}
          try {
            await _bgVideoController!.dispose();
          } catch (_) {}
          _bgVideoController = null;
          _bgVideoReady = false;
        }
        if (mounted) {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => ComicViewerPage(
                uid: as.uid ?? '',
                initialFrames: frames,
                initialQuestions: questions,
                finished: finished,
        startIndex: ((manager.progressIndex + 1)
            .clamp(0, frames.isNotEmpty ? (frames.length - 1) : 0))
          .toInt(),
                manager: manager,
              ),
            ),
          );
        }
      } catch (e, st) {
        if (kDebugMode) {
          print('CodeEntryPage._signInWithGoogleAndStart exception: $e');
          print(st);
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Sign-in failed. Please try again.')),
          );
        }
      } finally {
        if (mounted) {
          setState(() {
            _loading = false;
          });
        }
      }
    }
  }

  Future<void> _signInAndStart() async {
    await _signInWithGoogle();
    print("calling start");
    await _start();
    print("start called.");
  }

  Future<void> _signOut() async {
    try {
      await _googleSignIn.signOut();
    } catch (_) {}
    try {
      await _auth.signOut();
    } catch (_) {}
    if (context.mounted) {
      // ignore: use_build_context_synchronously
      final as = Provider.of<AppState>(context, listen: false);
      await as.setUid(null);
    }

    if (mounted) {
      setState(() {
        _signedIn = false;
        _userName = null;
  // _userEmail = null;
      });
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _animController.dispose();
    if (_bgVideoController != null) {
      try {
        if (kDebugMode) {
          print('DEBUG: disposing background video controller');
        }
        _bgVideoController!.dispose();
      } catch (e) {
        if (kDebugMode) {
          print('DEBUG: error disposing bg video controller: $e');
        }
      }
    }
    super.dispose();
  }

  @override
  void didPopNext() {
    // Called when the top route has been popped and this route shows up again.
    // Re-init the background video so it resumes playing on the entry page.
    if (kDebugMode) {
      print(
        'DEBUG: CodeEntryPage.didPopNext - reinitializing background video',
      );
    }
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
              // show asset image while background video initializes
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
                      "Comic Game Title",
                      style: Theme.of(
                        context,
                      ).textTheme.displayLarge!.copyWith(color: Colors.white),
                    ),
                    const SizedBox(height: 12),
                    // Google Sign-in button
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        ElevatedButton.icon(
                          icon: const Icon(Icons.account_circle),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.black.withValues(
                              alpha: 0.5,
                            ),
                            padding: EdgeInsets.all(18),
                          ),
                          label: Text(
                            _isSigningIn
                                ? "Signing in.."
                                : _loading
                                ? "Starting..."
                                : _signedIn
                                ? 'Play as ${_userName}'
                                : 'Sign in with Google',
                          ),
                          onPressed: _isSigningIn
                              ? () {}
                              : _signedIn
                              ? _start
                              : _signInAndStart,
                        ),

                        if (_signedIn) SizedBox(width: 20),
                        if (_signedIn)
                          IconButton(
                            icon: Icon(
                              Icons.logout,
                              size: 20,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                            style: IconButton.styleFrom(
                              backgroundColor: Colors.black.withValues(
                                alpha: 0.5,
                              ),
                            ),
                            onPressed: _signOut,
                          ),
                      ],
                    ),
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
