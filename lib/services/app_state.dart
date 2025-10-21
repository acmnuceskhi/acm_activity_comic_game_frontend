import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/widgets.dart';

class AppState extends ChangeNotifier {
  String _code = '';
  String? _backgroundImageUrl;

  String? get backgroundImageUrl => _backgroundImageUrl;

  String get code => _code;

  Future<void> load() async {
    final sp = await SharedPreferences.getInstance();
    _code = sp.getString('code') ?? '';
    _backgroundImageUrl = sp.getString('backgroundImageUrl');
    notifyListeners();
  }

  Future<void> setCode(String c) async {
    _code = c;
    final sp = await SharedPreferences.getInstance();
    await sp.setString('code', c);
    notifyListeners();
  }

  Future<void> setBackgroundImageUrl(String? url, {bool persist = true}) async {
    _backgroundImageUrl = (url != null && url.isNotEmpty) ? url : null;
    if (persist) {
      final sp = await SharedPreferences.getInstance();
      if (_backgroundImageUrl != null) {
        await sp.setString('backgroundImageUrl', _backgroundImageUrl!);
      } else {
        await sp.remove('backgroundImageUrl');
      }
    }
    notifyListeners();
    // Optionally prefetch the image into Flutter's image cache
    if (_backgroundImageUrl != null) {
      try {
        precacheImage(
          NetworkImage(_backgroundImageUrl!),
          WidgetsBinding.instance.renderViewElement!,
        );
      } catch (_) {}
    }
  }

  // Note: fetching the remote config requires cloud_firestore in the app.
  // To avoid introducing new dependencies automatically, the app can call
  // `refreshBackgroundFromFirestore()` from a place where Firestore is
  // available (for example, during app initialization). This method is
  // implemented in the frontend where Firestore is already used.
}
