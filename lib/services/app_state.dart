import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppState extends ChangeNotifier {
  String _code = '';

  String get code => _code;

  Future<void> load() async {
    final sp = await SharedPreferences.getInstance();
    _code = sp.getString('code') ?? '';
    notifyListeners();
  }

  Future<void> setCode(String c) async {
    _code = c;
    final sp = await SharedPreferences.getInstance();
    await sp.setString('code', c);
    notifyListeners();
  }
}
