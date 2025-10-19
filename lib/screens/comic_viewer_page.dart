import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
// import 'dart:math' as math; // not needed
import '../services/functions_api.dart';
import '../services/music_player.dart';

class ComicViewerPage extends StatefulWidget {
  final String code;
  final List<dynamic> initialFrames;
  final List<dynamic> initialQuestions;

  const ComicViewerPage({
    super.key,
    required this.code,
    required this.initialFrames,
    required this.initialQuestions,
  });

  @override
  State<ComicViewerPage> createState() => _ComicViewerPageState();
}

class _ComicViewerPageState extends State<ComicViewerPage>
    with SingleTickerProviderStateMixin {
  final FunctionsApi _api = FunctionsApi();
  late List<dynamic> frames;
  late List<dynamic> questions;
  int idx = 0;
  bool _showingQuestion = false;
  bool _loading = false;
  final FocusNode _focusNode = FocusNode();
  // Animation fields for "page throw" effect
  late final AnimationController _animController;
  late final Animation<double> _anim;
  bool _isAnimating = false;
  // int _animFromIdx = 0; // unused
  int _animTargetIdx = 0;
  int _animDirection = 1; // 1 = next (from right), -1 = prev (from left)

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
    if (idx > 0) {
      _animateTo(idx - 1, -1);
    }
  }

  Future<void> _handleNext() async {
    if (_showingQuestion || _loading) return;
    if (frames.isEmpty) return;
    final cur = frames[idx];
    final qSetId = cur['questionSetId'] as String?;
    if (qSetId != null && qSetId.isNotEmpty) {
      // show overlay to answer
      await _showQuestionOverlayForFrame(cur);
      return; // after overlay, do not auto-advance automatically; refetch will update frames
    }
    if (idx < frames.length - 1) {
      _animateTo(idx + 1, 1);
    }
  }

  void _animateTo(int toIdx, int direction) {
    if (_isAnimating) return;
    if (toIdx < 0 || toIdx >= frames.length) return;
    _isAnimating = true;
    _animTargetIdx = toIdx;
    _animDirection = direction;
    // start playing target music so it overlaps with the animation
    try {
      final mid = frames[toIdx]['musicId'] as String?;
      globalMusicPlayer.play(mid);
    } catch (_) {}
    _animController
        .forward(from: 0)
        .then((_) {
          // commit the new index after animation
          if (mounted) {
            setState(() {
              idx = toIdx;
            });
          }
        })
        .whenComplete(() {
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
          content: Column(
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
                question != null ? (question['text']?.toString() ?? '') : '',
              ),
              const SizedBox(height: 8),
              TextField(
                controller: answerCtrl,
                decoration: const InputDecoration(labelText: 'Your answer'),
              ),
            ],
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
      // submit
      setState(() => _loading = true);
      try {
        final res = await _api.submitAnswer(
          code: widget.code,
          questionSetId: qForFrame['setId'],
          questionId: question['id'].toString(),
          answer: answerCtrl.text.trim(),
        );

        // detailed logging for debugging
        print('submitAnswer response: $res');

        if (res['success'] == true && res['correct'] == true) {
          // refetch frames
          await _refetchFrames();
        } else {
          // incorrect or failure
          print('submitAnswer returned not-correct or failed: $res');
          if (mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('Incorrect answer')));
          }
        }
      } catch (e, st) {
        // log detailed error on console
        print('ComicViewerPage.submit exception: $e');
        print(st);
        if (mounted)
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Error: $e')));
      } finally {
        setState(() {
          _loading = false;
        });
      }
    }

    setState(() => _showingQuestion = false);
  }

  Future<void> _refetchFrames() async {
    final res = await _api.getNextFrames(widget.code);
    print('getNextFrames response: $res');
    if (res['success'] == true) {
      setState(() {
        frames = List.from(res['frames'] ?? []);
        questions = List.from(res['questions'] ?? []);
        idx = 0;
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

  Widget _buildFrame(dynamic f) {
    final imageUrl = f['imageUrl'] as String? ?? '';
    return Container(
      color: Colors.black,
      alignment: Alignment.center,
      child: imageUrl.isEmpty
          ? const Text('No image', style: TextStyle(color: Colors.white))
          : Image.network(
              imageUrl,
              fit: BoxFit.contain,
              width: double.infinity,
              height: double.infinity,
              loadingBuilder: (context, child, loadingProgress) {
                if (loadingProgress == null) return child;
                return const Center(child: CircularProgressIndicator());
              },
            ),
    );
  }

  // Builds the animated overlay for the incoming page during the "throw" animation.
  Widget _buildAnimatedOverlay(dynamic f) {
    // animation value from 0.0 -> 1.0
    final t = _anim.value;
    // rotation: slight rotation depending on direction
    final rot = (_animDirection * (1 - t) * 0.12); // radians
    // translation: move from offscreen to center
    final width = MediaQuery.of(context).size.width;
    final dxStart = _animDirection * width;
    final dx = dxStart * (1 - t);

    return Transform.translate(
      offset: Offset(dx, 0),
      child: Transform.rotate(
        angle: rot,
        child: Opacity(opacity: t.clamp(0.0, 1.0), child: _buildFrame(f)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return RawKeyboardListener(
      focusNode: _focusNode..requestFocus(),
      onKey: _onKey,
      child: Scaffold(
        appBar: AppBar(title: Text('Comic Viewer - ${widget.code}')),
        body: Stack(
          children: [
            // base frame (current)
            Positioned.fill(
              child: frames.isEmpty
                  ? const Center(child: Text('No frames'))
                  : _buildFrame(frames[idx]),
            ),
            // animated incoming page overlay
            if (_isAnimating && frames.length > _animTargetIdx)
              Positioned.fill(
                child: _buildAnimatedOverlay(frames[_animTargetIdx]),
              ),
            // left/right buttons for small screens
            Positioned(
              left: 8,
              top: 0,
              bottom: 0,
              child: Visibility(
                visible: MediaQuery.of(context).size.width < 600,
                child: IconButton(
                  iconSize: 48,
                  color: Colors.white,
                  icon: const Icon(Icons.arrow_left),
                  onPressed: _handlePrev,
                ),
              ),
            ),
            Positioned(
              right: 8,
              top: 0,
              bottom: 0,
              child: Visibility(
                visible: MediaQuery.of(context).size.width < 600,
                child: IconButton(
                  iconSize: 48,
                  color: Colors.white,
                  icon: const Icon(Icons.arrow_right),
                  onPressed: _handleNext,
                ),
              ),
            ),
            if (_loading) const Center(child: CircularProgressIndicator()),
          ],
        ),
      ),
    );
  }
}
