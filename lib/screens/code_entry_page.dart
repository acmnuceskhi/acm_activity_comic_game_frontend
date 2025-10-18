import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/functions_api.dart';
import '../services/app_state.dart';
import '../services/music_player.dart';
import 'comic_viewer_page.dart';

class CodeEntryPage extends StatefulWidget {
  const CodeEntryPage({super.key});

  @override
  State<CodeEntryPage> createState() => _CodeEntryPageState();
}

class _CodeEntryPageState extends State<CodeEntryPage> {
  final _ctrl = TextEditingController();
  String? _error;
  bool _loading = false;
  final _api = FunctionsApi();

  @override
  void initState() {
    super.initState();
    // load initial code from provider (already loaded in main)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final as = Provider.of<AppState>(context, listen: false);
      if (as.code.isNotEmpty) _ctrl.text = as.code;
    });
  }

  Future<void> _submit() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final code = _ctrl.text.trim();
    try {
      final res = await _api.getNextFrames(code);
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
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ComicViewerPage(
            code: code,
            initialFrames: frames,
            initialQuestions: questions,
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
      appBar: AppBar(title: const Text('Enter Registration Code')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextField(
              controller: _ctrl,
              decoration: InputDecoration(labelText: 'Code', errorText: _error),
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _loading ? null : _submit,
              child: _loading
                  ? const CircularProgressIndicator()
                  : const Text('Continue'),
            ),
          ],
        ),
      ),
    );
  }
}
