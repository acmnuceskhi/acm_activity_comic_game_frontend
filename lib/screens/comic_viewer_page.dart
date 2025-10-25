import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
// import 'dart:math' as math; // not needed
import '../services/functions_api.dart';
import '../services/music_player.dart';
import 'package:vector_math/vector_math_64.dart' show Matrix4;
import 'package:provider/provider.dart';
import '../services/app_state.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:html' as html;

class ComicViewerPage extends StatefulWidget {
  final String code;
  final List<dynamic> initialFrames;
  final List<dynamic> initialQuestions;
  final bool finished;

  const ComicViewerPage({
    super.key,
    required this.code,
    required this.initialFrames,
    required this.initialQuestions,
    required this.finished,
  });

  @override
  State<ComicViewerPage> createState() => _ComicViewerPageState();
}

class _ComicViewerPageState extends State<ComicViewerPage>
    with SingleTickerProviderStateMixin {
  final FunctionsApi _api = FunctionsApi();
  late List<dynamic> frames;
  late List<dynamic> questions;

  // Web-specific debug overlay
  void _webDebug(String message) {
    if (kIsWeb) {
      html.window.console.log(message);
      // Also show in page for release debugging
      final div = html.document.createElement('div') as html.DivElement;
      div.style
        ..position = 'fixed'
        ..top = '40px'
        ..right = '0'
        ..backgroundColor = 'rgba(0,0,0,0.8)'
        ..color = 'white'
        ..padding = '8px'
        ..zIndex = '9999'
        ..fontSize = '12px'
        ..maxWidth = '400px'
        ..overflow = 'auto';
      div.text = message;
      html.document.body?.children.add(div);
    }
  }

  int idx = 0;
  bool _showingQuestion = false;
  bool _loading = false;
  bool _showFinishedScreen = false;
  final FocusNode _focusNode = FocusNode();
  // Animation fields for "page throw" effect
  late final AnimationController _animController;
  late final Animation<double> _anim;
  bool _isAnimating = false;
  // int _animFromIdx = 0; // unused
  // int _animTargetIdx = 0; // no longer used with translation-based rendering
  int _animDirection = 1; // 1 = next (from right), -1 = prev (from left)
  // frame measurement for element placement
  final GlobalKey _frameImageKey = GlobalKey();
  double _frameW = 0, _frameH = 0, _frameLeft = 0, _frameTop = 0;
  // cache intrinsic sizes for element images keyed by imageUrl
  final Map<String, Size> _elemIntrinsicCache = {};

  @override
  void initState() {
    super.initState();
    frames = List.from(widget.initialFrames);
    questions = List.from(widget.initialQuestions);
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
    );
    _anim = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOutCubic,
    );
    _animController.addListener(() {
      // rebuild during animation
      if (mounted) setState(() {});
    });
    // play music for initial frame if available
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (frames.isNotEmpty) {
        final mid = frames[0]['musicId'] as String?;
        globalMusicPlayer.play(mid);
      }
    });
  }

  @override
  void dispose() {
    // stop any playing music and dispose animation controller
    try {
      _animController.dispose();
    } catch (_) {}
    globalMusicPlayer.stop();
    _focusNode.dispose();
    super.dispose();
  }

  void _onKey(RawKeyEvent ev) {
    if (_showingQuestion || _loading)
      return; // disable keyboard navigation while answering
    if (ev is RawKeyDownEvent) {
      if (ev.logicalKey == LogicalKeyboardKey.arrowRight) {
        _handleNext();
      } else if (ev.logicalKey == LogicalKeyboardKey.arrowLeft) {
        _handlePrev();
      }
    }
  }

  void _handlePrev() {
    if (_showingQuestion || _loading)
      return; // prevent navigation while question dialog is open
    if (_showFinishedScreen) {
      // go back from the finished screen to the last page
      setState(() {
        _showFinishedScreen = false;
      });
      return;
    }
    if (idx > 0) {
      _animateTo(idx - 1, -1);
    }
  }

  Future<bool> _confirmBack() async {
    // first check
    final first = await showDialog<bool?>(
      context: context,
      barrierDismissible: true,
      builder: (c) => AlertDialog(
        title: const Text('Go back?'),
        content: const Text(
          'Do you want to go back? Your progress will be saved.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(c).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(c).pop(true),
            child: const Text('Yes'),
          ),
        ],
      ),
    );
    if (first != true) return false;

    // second, stronger confirmation
    final second = await showDialog<bool?>(
      context: context,
      barrierDismissible: true,
      builder: (c) => AlertDialog(
        title: const Text('Confirm go back'),
        content: const Text(
          'Returning will discard any unsaved progress. Continue?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(c).pop(false),
            child: const Text('No'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(c).pop(true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    return second == true;
  }

  Future<void> _handleBack() async {
    if (_loading) return; // avoid interfering while loading
    final ok = await _confirmBack();
    if (ok) {
      // stop music and dispose any animations if needed
      try {
        globalMusicPlayer.stop();
      } catch (_) {}
      if (mounted) Navigator.of(context).pop();
    }
  }

  Future<void> _handleNext() async {
    if (_showingQuestion || _loading) return;
    if (frames.isEmpty) return;
    final cur = frames[idx];
    final qSetId = cur['questionSetId'] as String?;
    if (qSetId != null && qSetId.isNotEmpty) {
      // current frame has a question -> show overlay to answer
      await _showQuestionOverlayForFrame(cur);
      return; // after overlay, refetch will update frames
    }

    // current frame has no question
    if (idx < frames.length - 1) {
      // not the last frame: advance normally
      _animateTo(idx + 1, 1);
      return;
    }

    // we're on the last frame and it has no question -> show finish screen
    if (idx == frames.length - 1) {
      setState(() {
        _showFinishedScreen = true;
      });
    }
  }

  void _animateTo(int toIdx, int direction) {
    if (_isAnimating) return;
    if (toIdx < 0 || toIdx >= frames.length) return;
    _isAnimating = true;
    _animDirection = direction;
    // start playing target music so it overlaps with the animation
    try {
      final mid = frames[toIdx]['musicId'] as String?;
      globalMusicPlayer.play(mid);
    } catch (_) {}
    _animController.forward(from: 0).then((_) {
      // commit the new index after animation
      if (mounted) {
        setState(() {
          idx = toIdx;
        });
      }
      _isAnimating = false;
    });
  }

  Future<void> _showQuestionOverlayForFrame(dynamic frame) async {
    dynamic qForFrame;
    for (final q in questions) {
      try {
        if (q['frameIndex'] == frame['index']) {
          qForFrame = q;
          break;
        }
      } catch (_) {}
    }
    if (qForFrame == null) return;
    final question = qForFrame['question'];
    final answerCtrl = TextEditingController();
    setState(() => _showingQuestion = true);
    final result = await showDialog<bool?>(
      context: context,
      barrierDismissible: false,
      builder: (c) {
        return AlertDialog(
          title: const Text('Question'),
          content: SizedBox(
            // limit height so dialog becomes scrollable on small screens
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(c).size.height * 0.7,
                maxWidth: 500,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (question != null && question['imageUrl'] != null)
                      Image.network(
                        question['imageUrl'],
                        loadingBuilder: (context, child, loadingProgress) {
                          if (loadingProgress == null) return child;
                          return const SizedBox(
                            height: 120,
                            child: Center(child: CircularProgressIndicator()),
                          );
                        },
                      ),
                    const SizedBox(height: 8),
                    Text(
                      question != null
                          ? (question['text']?.toString() ?? '')
                          : '',
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: answerCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Your answer',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(c).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(c).pop(true),
              child: const Text('Submit'),
            ),
          ],
        );
      },
    );

    if (result == true) {
      // show non-dismissible checking dialog
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (c) => const AlertDialog(
          title: Text('Checking your answer'),
          content: SizedBox(
            height: 60,
            child: Center(child: CircularProgressIndicator()),
          ),
        ),
      );

      try {
        final res = await _api.submitAnswer(
          code: widget.code,
          questionSetId: qForFrame['setId'],
          questionId: question['id'].toString(),
          answer: answerCtrl.text.trim(),
        );

        // close checking dialog
        try {
          Navigator.of(context).pop();
        } catch (_) {}

        // detailed logging for debugging
        print('submitAnswer response: $res');

        if (res['success'] == true && res['correct'] == true) {
          // show success dialog
          await showDialog<void>(
            context: context,
            barrierDismissible: true,
            builder: (c) => AlertDialog(
              title: const Text('Correct!'),
              content: const Text('Your answer is correct.'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(c).pop(),
                  child: const Text('Continue'),
                ),
              ],
            ),
          );
          // show a non-dismissible loading dialog while fetching new frames
          showDialog<void>(
            context: context,
            barrierDismissible: false,
            builder: (c) => const AlertDialog(
              title: Text('Loading new frames'),
              content: SizedBox(
                height: 60,
                child: Center(child: CircularProgressIndicator()),
              ),
            ),
          );
          try {
            await _refetchFrames();
          } finally {
            // close the loading dialog
            try {
              Navigator.of(context).pop();
            } catch (_) {}
          }
        } else {
          // incorrect or failure
          print('submitAnswer returned not-correct or failed: $res');
          if (mounted) {
            await showDialog<void>(
              context: context,
              barrierDismissible: true,
              builder: (c) => AlertDialog(
                title: const Text('Incorrect'),
                content: const Text('Your answer was incorrect.'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(c).pop(),
                    child: const Text('OK'),
                  ),
                ],
              ),
            );
          }
        }
      } catch (e, st) {
        // close checking dialog
        try {
          Navigator.of(context).pop();
        } catch (_) {}
        // log detailed error on console
        print('ComicViewerPage.submit exception: $e');
        print(st);
        if (mounted)
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }

    setState(() => _showingQuestion = false);
  }

  Future<void> _refetchFrames() async {
    final res = await _api.getNextFrames(widget.code);
    print('getNextFrames response: $res');
    try {
      final framesCount = (res['frames'] is List)
          ? (res['frames'] as List).length
          : 0;
      final finished = res['finished'] == true;
      print(
        'DEBUG: _refetchFrames fetched $framesCount frames, finished=$finished at ${DateTime.now().toIso8601String()}',
      );
    } catch (e) {
      print('DEBUG: _refetchFrames failed to parse response: $e');
    }
    if (res['success'] == true) {
      // prepare new frames/questions first
      final newFrames = List.from(res['frames'] ?? []);
      final newQuestions = List.from(res['questions'] ?? []);
      setState(() {
        frames = newFrames;
        questions = newQuestions;
        idx = 0;
        // Show the finish screen only if server says finished and there are no new frames
        if (res['finished'] == true && newFrames.isEmpty) {
          _showFinishedScreen = true;
        } else {
          _showFinishedScreen = false;
        }
      });
      // play music for the (new) current frame immediately after refetch
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (frames.isNotEmpty) {
          final mid = frames[idx]['musicId'] as String?;
          globalMusicPlayer.play(mid);
        }
      });
    }
  }

  Widget _buildFrame(
    dynamic f, {
    Key? imageKey,
    bool elementsPlay = true,
    double? pageWidth,
    double? pageHeight,
    double? pagePadding,
  }) {
    final imageUrl = f['imageUrl'] as String? ?? '';
    if (imageUrl.isEmpty) {
      return Container(
        color: Colors.black,
        alignment: Alignment.center,
        child: const Text('No image', style: TextStyle(color: Colors.white)),
      );
    }

    // if elements exist, overlay them
    final elements = (f['elements'] is List)
        ? List.from(f['elements'] as List)
        : [];

    return LayoutBuilder(
      builder: (context, constraints) {
        // pageWidth/pageHeight are preferred; fallback to available constraints
        final pageW = pageWidth ?? constraints.maxWidth;
        final pageH = pageHeight ?? constraints.maxHeight;
        final padding = pagePadding ?? (pageH * 0.04);

        final w = pageW - padding * 2;
        final h = pageH - padding * 2;
        // measure displayed frame size (BoxFit.contain) after layout
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final ctx = _frameImageKey.currentContext;
          if (ctx != null) {
            final size = ctx.size;
            if (size != null) {
              final newW = size.width;
              final newH = size.height;
              // image is centered inside the inner area; compute left/top relative to the page
              final newLeft = (pageW - newW) / 2.0;
              final newTop = (pageH - newH) / 2.0;
              if (newW != _frameW ||
                  newH != _frameH ||
                  newLeft != _frameLeft ||
                  newTop != _frameTop) {
                if (mounted)
                  setState(() {
                    _frameW = newW;
                    _frameH = newH;
                    _frameLeft = newLeft;
                    _frameTop = newTop;
                  });
              }
            }
          }
        });

        // compute base size for elements. If imageKey is provided we may have
        // accurate measured _frameW/_frameH; otherwise use constraints so overlay
        // elements are positioned using local layout values (prevents jumps).
        final base = (imageKey != null && _frameW > 0 && _frameH > 0)
            ? (_frameW < _frameH ? _frameW : _frameH)
            : (w < h ? w : h);

        // compute image displayed size for this layout (BoxFit.contain behavior)
        // If we have measured values for the real frame (imageKey != null) use them,
        // otherwise approximate using base
        final imgW = (imageKey != null && _frameW > 0) ? _frameW : base;
        final imgH = (imageKey != null && _frameH > 0) ? _frameH : base;
        final frameLeftLocal = (pageW - imgW) / 2.0;
        final frameTopLocal = (pageH - imgH) / 2.0;

        return Stack(
          clipBehavior: Clip.none,
          children: [
            // Page container centered with padding
            Positioned.fill(
              child: Center(
                child: Container(
                  width: pageW,
                  height: pageH,
                  padding: EdgeInsets.all(padding),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Stack(
                    children: [
                      Center(
                        child: Image.network(
                          imageUrl,
                          key: imageKey,
                          fit: BoxFit.contain,
                          frameBuilder:
                              (context, child, frame, wasSynchronouslyLoaded) {
                                if (wasSynchronouslyLoaded) return child;
                                if (frame == null) {
                                  return Center(
                                    child: Text(
                                      'loading...',
                                      style: GoogleFonts.comicNeue(
                                        textStyle: const TextStyle(
                                          color: Colors.black,
                                        ),
                                      ),
                                    ),
                                  );
                                }
                                return child;
                              },
                        ),
                      ),
                      // integrate page number into the page container (looks like part of the page)
                      Positioned(
                        bottom: 8,
                        left: pageW * 0.05,
                        right: pageW * 0.05,
                        child: Center(
                          child: Text(
                            (f['index'] != null)
                                ? 'Page ${(int.tryParse(f['index'].toString()) ?? 0) + 1}'
                                : '',
                            style: GoogleFonts.comicNeue(
                              textStyle: const TextStyle(
                                color: Colors.black87,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            // overlay elements
            for (final elRaw in elements)
              if (elRaw is Map<String, dynamic>)
                _buildElementOverlay(
                  elRaw,
                  base,
                  elementsPlay,
                  imgW,
                  imgH,
                  frameLeftLocal,
                  frameTopLocal,
                ),
          ],
        );
      },
    );
  }

  Widget _buildElementOverlay(
    Map<String, dynamic> el,
    double base,
    bool elementsPlay,
    double imgW,
    double imgH,
    double frameLeftLocal,
    double frameTopLocal,
  ) {
    // ensure we have intrinsic size cached (async). Use imageUrl as key.
    final imageUrl = el['imageUrl'] as String? ?? '';
    if (imageUrl.isNotEmpty && !_elemIntrinsicCache.containsKey(imageUrl)) {
      _resolveIntrinsicForUrl(imageUrl);
    }
    // normalized position
    final pos = el['position'] as Map<String, dynamic>? ?? {'x': 0.5, 'y': 0.5};
    final nx = (pos['x'] is num) ? (pos['x'] as num).toDouble() : 0.5;
    final ny = (pos['y'] is num) ? (pos['y'] as num).toDouble() : 0.5;
    final elemScale = (el['scale'] is num)
        ? (el['scale'] as num).toDouble()
        : 0.2;

    final maxDim = (elemScale * base).clamp(8.0, base);

    double elemW, elemH;
    final intrinsic = (_elemIntrinsicCache[imageUrl]);
    if (intrinsic != null && intrinsic.width > 0 && intrinsic.height > 0) {
      final aspect = intrinsic.width / intrinsic.height;
      if (aspect >= 1.0) {
        elemW = maxDim;
        elemH = maxDim / aspect;
      } else {
        elemH = maxDim;
        elemW = maxDim * aspect;
      }
    } else {
      elemW = maxDim;
      elemH = maxDim;
    }

    final centerX = (nx * imgW).clamp(elemW / 2.0, imgW - elemW / 2.0);
    final centerY = (ny * imgH).clamp(elemH / 2.0, imgH - elemH / 2.0);
    final left = frameLeftLocal + centerX - elemW / 2.0;
    final top = frameTopLocal + centerY - elemH / 2.0;

    return Positioned(
      left: left,
      top: top,
      width: elemW,
      height: elemH,
      child: _AnimatedElement(
        frameImageUrl: frames.isNotEmpty
            ? frames[idx]['imageUrl'] as String? ?? ''
            : '',
        element: el,
        frameW: _frameW,
        frameH: _frameH,
        elemW: elemW,
        elemH: elemH,
        play: elementsPlay,
      ),
    );
  }

  void _resolveIntrinsicForUrl(String url) {
    if (url.isEmpty) return;
    final provider = NetworkImage(url);
    final stream = provider.resolve(const ImageConfiguration());
    stream.addListener(
      ImageStreamListener(
        (info, _) {
          final iw = info.image.width.toDouble();
          final ih = info.image.height.toDouble();
          final prev = _elemIntrinsicCache[url];
          if (prev == null || prev.width != iw || prev.height != ih) {
            if (mounted) {
              setState(() {
                _elemIntrinsicCache[url] = Size(iw, ih);
              });
            }
          }
        },
        onError: (e, s) {
          // ignore resolution errors; fallback will be used
          debugPrint('Failed to resolve intrinsic for $url: $e');
        },
      ),
    );
  }

  // overlay method removed: rendering now uses translation-based stacking

  @override
  Widget build(BuildContext context) {
    // Manage focus so that on mobile the dialog's TextField can receive
    // focus without the page-level RawKeyboardListener stealing it.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_showingQuestion) {
        // If a question dialog is open, remove focus from the page-level
        // listener so the dialog's text field can open the keyboard.
        if (_focusNode.hasFocus) _focusNode.unfocus();
      } else {
        // On non-dialog states acquire focus so keyboard events work on
        // desktop/web. We only request focus when not already focused.
        if (!_focusNode.hasFocus) _focusNode.requestFocus();
      }
    });

    return RawKeyboardListener(
      focusNode: _focusNode,
      onKey: _onKey,
      child: Scaffold(
        body: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final height = constraints.maxHeight;

            if (frames.isEmpty || _showFinishedScreen) {
              // If the backend indicated finished or local flag is set, show finish UI
              if (widget.finished || _showFinishedScreen) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'The End!',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      ElevatedButton(
                        onPressed: () async {
                          try {
                            setState(() {
                              _loading = true;
                            });
                            final r = await _api.resetProgress(widget.code);
                            print('resetProgress response: $r');
                            if (r['success'] == true) {
                              setState(() {
                                _showFinishedScreen = false;
                              });
                              await _refetchFrames();
                            } else {
                              if (mounted) {
                                showDialog<void>(
                                  context: context,
                                  builder: (c) => AlertDialog(
                                    title: const Text('Error'),
                                    content: Text(
                                      r['message']?.toString() ??
                                          'Failed to reset',
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.of(c).pop(),
                                        child: const Text('OK'),
                                      ),
                                    ],
                                  ),
                                );
                              }
                            }
                          } catch (e) {
                            print('resetProgress failed: $e');
                            if (mounted) {
                              showDialog<void>(
                                context: context,
                                builder: (c) => AlertDialog(
                                  title: const Text('Error'),
                                  content: Text('Failed to reset progress: $e'),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.of(c).pop(),
                                      child: const Text('OK'),
                                    ),
                                  ],
                                ),
                              );
                            }
                          } finally {
                            if (mounted)
                              setState(() {
                                _loading = false;
                              });
                          }
                        },
                        child: const Text('Play Again'),
                      ),
                    ],
                  ),
                );
              }
              return const Center(child: Text('No frames'));
            }

            return Stack(
              alignment: Alignment.center,
              clipBehavior: Clip.none,
              children: [
                // background image (from admin-configured URL) if present
                SizedBox.expand(
                  child: Builder(
                    builder: (ctx) {
                      final bg = Provider.of<AppState>(ctx).backgroundImageUrl;

                      if (bg == null || bg.isEmpty) {
                        return const SizedBox.shrink();
                      }

                      return Stack(
                        children: [
                          Positioned.fill(
                            child: Image.network(
                              bg,
                              fit: BoxFit.cover,
                              width: double.infinity,
                              height: double.infinity,
                              loadingBuilder:
                                  (context, child, loadingProgress) {
                                    if (loadingProgress == null) {
                                      return child;
                                    }
                                    return Container(
                                      color: Colors.black87,
                                      child: const Center(
                                        child: CircularProgressIndicator(),
                                      ),
                                    );
                                  },
                              errorBuilder: (context, error, stackTrace) {
                                return Container(
                                  color: Colors.black87,
                                  alignment: Alignment.center,
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        'Background Failed: ${error.toString()}',
                                        style: const TextStyle(
                                          color: Colors.red,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
                for (var i = 0; i < frames.length; i++)
                  // each frame is a positioned full-size child translated horizontally
                  Positioned.fill(
                    child: Transform.translate(
                      offset: Offset(
                        // compute offset multiplier: (i - idx) shifted by animation progress
                        (((i - idx) -
                                (_isAnimating
                                    ? _anim.value * _animDirection
                                    : 0.0)) *
                            width),
                        0,
                      ),
                      child: Builder(
                        builder: (ctx) {
                          // compute a small rotation for incoming/outgoing pages
                          const maxAngle = 0.12; // radians (~6.9deg)
                          double angle = 0.0;
                          if (_isAnimating) {
                            final p = _anim.value; // 0 -> 1
                            if (i == idx) {
                              // outgoing page: rotate outwards
                              angle = -_animDirection * p * maxAngle;
                            } else if (i == idx + _animDirection) {
                              // incoming page: rotate from angle -> 0
                              angle = _animDirection * (1.0 - p) * maxAngle;
                            }
                          }

                          // compute page dimensions relative to screen height
                          final pageHeight =
                              height * 0.92; // 92% of screen height
                          final pageWidth = (pageHeight * 0.66).clamp(
                            0.0,
                            width * 0.95,
                          );
                          final pagePadding =
                              pageHeight *
                              0.04; // moderate padding relative to height

                          return Transform.rotate(
                            angle: angle,
                            alignment: Alignment.center,
                            child: SizedBox(
                              width: width,
                              height: height,
                              child: _buildFrame(
                                frames[i],
                                // only keep the measured key on the currently settled frame
                                imageKey: (!_isAnimating && i == idx)
                                    ? _frameImageKey
                                    : null,
                                // only allow elements to play after translation finished and this is the active frame
                                elementsPlay: (!_isAnimating && i == idx),
                                pageWidth: pageWidth,
                                pageHeight: pageHeight,
                                pagePadding: pagePadding,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),

                // small bottom-corner buttons for mobile (thumb-reachable)
                // translucent top-left back button
                Positioned(
                  left: 12,
                  top: 12,
                  child: Material(
                    color: Colors.black45,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: InkWell(
                      onTap: _handleBack,
                      borderRadius: BorderRadius.circular(8),
                      child: const Padding(
                        padding: EdgeInsets.all(8.0),
                        child: Icon(Icons.arrow_back, color: Colors.white),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 12,
                  bottom: 12,
                  child: Visibility(
                    visible: MediaQuery.of(context).size.width < 600,
                    child: Material(
                      color: Colors.black45,
                      shape: const CircleBorder(),
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: _handlePrev,
                        child: const SizedBox(
                          width: 56,
                          height: 56,
                          child: Icon(
                            Icons.arrow_left,
                            color: Colors.white,
                            size: 32,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  right: 12,
                  bottom: 12,
                  child: Visibility(
                    visible: MediaQuery.of(context).size.width < 600,
                    child: Material(
                      color: Colors.black45,
                      shape: const CircleBorder(),
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: _handleNext,
                        child: const SizedBox(
                          width: 56,
                          height: 56,
                          child: Icon(
                            Icons.arrow_right,
                            color: Colors.white,
                            size: 32,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                if (_loading) const Center(child: CircularProgressIndicator()),
              ],
            );
          },
        ),
      ),
    );
  }
}

// Widget that plays element animations (Matrix4 sequences) and renders the transformed element image.

class _AnimatedElement extends StatefulWidget {
  final String frameImageUrl;
  final Map<String, dynamic> element;
  final double frameW;
  final double frameH;
  final double elemW;
  final double elemH;
  final bool play;

  const _AnimatedElement({
    required this.frameImageUrl,
    required this.element,
    required this.frameW,
    required this.frameH,
    required this.elemW,
    required this.elemH,
    this.play = true,
    Key? key,
  }) : super(key: key);

  @override
  State<_AnimatedElement> createState() => _AnimatedElementState();
}

class _AnimatedElementState extends State<_AnimatedElement>
    with SingleTickerProviderStateMixin {
  late List<Map<String, dynamic>> _animations;
  int _index = 0;
  late AnimationController _controller;
  Matrix4 _current = Matrix4.identity();
  Matrix4 _start = Matrix4.identity();
  Matrix4 _target = Matrix4.identity();
  double? _elemIntrinsicW;
  double? _elemIntrinsicH;
  // frame measurement fields not needed in this element player (kept in parent)

  @override
  void initState() {
    super.initState();
    final raw = widget.element['animation'];
    if (raw is List) {
      _animations = raw
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    } else {
      _animations = [];
    }
    _controller = AnimationController(vsync: this);
    _resolveElementIntrinsic();
    if (_animations.isNotEmpty && widget.play) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _playNext());
    }
  }

  void _resolveElementIntrinsic() {
    final imgUrl = widget.element['imageUrl'] as String?;
    if (imgUrl == null || imgUrl.isEmpty) return;
    final provider = NetworkImage(imgUrl);
    final stream = provider.resolve(const ImageConfiguration());
    stream.addListener(
      ImageStreamListener(
        (info, _) {
          final iw = info.image.width.toDouble();
          final ih = info.image.height.toDouble();
          if (_elemIntrinsicW != iw || _elemIntrinsicH != ih) {
            if (mounted)
              setState(() {
                _elemIntrinsicW = iw;
                _elemIntrinsicH = ih;
              });
          }
        },
        onError: (e, s) =>
            debugPrint('Failed to resolve element image size: $e'),
      ),
    );
  }

  @override
  void didUpdateWidget(covariant _AnimatedElement oldWidget) {
    super.didUpdateWidget(oldWidget);
    // If play toggles from false -> true, restart the element animation sequence
    if (!oldWidget.play && widget.play) {
      _startPlaying();
    }
    // If play was true and now false, stop current animation
    if (oldWidget.play && !widget.play) {
      try {
        _controller.stop();
      } catch (_) {}
    }
  }

  void _startPlaying() {
    if (_animations.isEmpty) return;
    // reset to start
    _index = 0;
    _current = Matrix4.identity();
    _start = Matrix4.identity();
    _target = Matrix4.identity();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _playNext();
    });
  }

  Matrix4 _matrixFromList(List<dynamic> l) {
    final nums = l.map((e) => (e as num).toDouble()).toList();
    return Matrix4(
      nums[0],
      nums[1],
      nums[2],
      nums[3],
      nums[4],
      nums[5],
      nums[6],
      nums[7],
      nums[8],
      nums[9],
      nums[10],
      nums[11],
      nums[12],
      nums[13],
      nums[14],
      nums[15],
    );
  }

  void _playNext() {
    if (_index >= _animations.length) return;
    final a = _animations[_index];
    final dur = (a['duration'] is num)
        ? (a['duration'] as num).toDouble()
        : ((a['seconds'] is num) ? (a['seconds'] as num).toDouble() : 1.0);
    final matRaw = a['matrix'];
    final txFrac = (a['translateX'] is num)
        ? (a['translateX'] as num).toDouble()
        : 0.0;
    final tyFrac = (a['translateY'] is num)
        ? (a['translateY'] as num).toDouble()
        : 0.0;

    // measure frame size if needed; try to read from ancestor frame image via widget.frameImageUrl measurement is optional
    final imgW = (widget.frameW > 0) ? widget.frameW : 320.0;
    final imgH = (widget.frameH > 0) ? widget.frameH : 320.0;
    final tx = txFrac * imgW;
    final ty = tyFrac * imgH;

    if (matRaw is List && matRaw.length == 16) {
      _start = _current.clone();
      _target = _matrixFromList(matRaw);
      if (tx != 0.0 || ty != 0.0) _target.translate(tx, ty);

      _controller.duration = Duration(milliseconds: (dur * 1000).round());
      _controller.reset();
      _controller.addListener(_tick);
      _controller.forward().whenComplete(() {
        _controller.removeListener(_tick);
        _current = _target.clone();
        _index++;
        if (_index < _animations.length) {
          Future.delayed(const Duration(milliseconds: 100), _playNext);
        }
      });
    } else if ((tx != 0.0 || ty != 0.0)) {
      _start = _current.clone();
      _target = Matrix4.identity();
      _target.translate(tx, ty);
      _controller.duration = Duration(milliseconds: (dur * 1000).round());
      _controller.reset();
      _controller.addListener(_tick);
      _controller.forward().whenComplete(() {
        _controller.removeListener(_tick);
        _current = _target.clone();
        _index++;
        if (_index < _animations.length) {
          Future.delayed(const Duration(milliseconds: 100), _playNext);
        }
      });
    } else {
      _index++;
      if (_index < _animations.length)
        Future.delayed(const Duration(milliseconds: 100), _playNext);
    }
  }

  void _tick() {
    final t = _controller.value;
    setState(() {
      _current = Matrix4.identity();
      for (var r = 0; r < 4; r++) {
        for (var c = 0; c < 4; c++) {
          final s = _start.entry(r, c);
          final e = _target.entry(r, c);
          _current.setEntry(r, c, s + (e - s) * t);
        }
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // compute display size based on intrinsic aspect (mirror admin logic)
    final base = widget.elemW; // parent passed maxDim
    double displayW = base;
    double displayH = base;
    if (_elemIntrinsicW != null &&
        _elemIntrinsicH != null &&
        _elemIntrinsicW! > 0 &&
        _elemIntrinsicH! > 0) {
      final aspect = _elemIntrinsicW! / _elemIntrinsicH!;
      if (aspect >= 1.0) {
        displayW = base;
        displayH = base / aspect;
      } else {
        displayH = base;
        displayW = base * aspect;
      }
    }

    return Transform(
      transform: _current,
      alignment: Alignment.center,
      child: Image.network(
        widget.element['imageUrl'] as String? ?? '',
        width: displayW,
        height: displayH,
        fit: BoxFit.contain,
      ),
    );
  }
}
