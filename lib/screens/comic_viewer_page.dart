import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

class _ComicViewerPageState extends State<ComicViewerPage> {
  final FunctionsApi _api = FunctionsApi();
  late List<dynamic> frames;
  late List<dynamic> questions;
  int idx = 0;
  bool _showingQuestion = false;
  bool _loading = false;
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    frames = List.from(widget.initialFrames);
    questions = List.from(widget.initialQuestions);
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
    // stop any playing music when leaving the viewer
    try {
      globalMusicPlayer.stop();
    } catch (_) {}
    _focusNode.dispose();
    super.dispose();
  }

  void _onKey(RawKeyEvent ev) {
    if (_showingQuestion || _loading) return; // disable keyboard navigation while answering
    if (ev is RawKeyDownEvent) {
      if (ev.logicalKey == LogicalKeyboardKey.arrowRight) {
        _handleNext();
      } else if (ev.logicalKey == LogicalKeyboardKey.arrowLeft) {
        _handlePrev();
      }
    }
  }

  void _handlePrev() {
    if (_showingQuestion || _loading) return; // prevent navigation while question dialog is open
    if (idx > 0) setState(() => idx--);
    // play music for the new frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (idx >= 0 && idx < frames.length) {
        final mid = frames[idx]['musicId'] as String?;
        globalMusicPlayer.play(mid);
      }
    });
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
      setState(() => idx++);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final mid = frames[idx]['musicId'] as String?;
        globalMusicPlayer.play(mid);
      });
    }
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
                Image.network(question['imageUrl']),
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

        if (res != null && res['success'] == true && res['correct'] == true) {
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
    if (res != null && res['success'] == true) {
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
            Positioned.fill(
              child: frames.isEmpty
                  ? const Center(child: Text('No frames'))
                  : _buildFrame(frames[idx]),
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
