import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config.dart';

class FunctionsApi {
  final String getNextUrl;
  final String submitUrl;
  final String getMusicLibraryUrl;
  final String fetchConfigUrl;
  final String resetProgressUrl;
  final String getGameDataUrl;

  FunctionsApi({
    String? getNextUrl,
    String? submitUrl,
    String? fetchConfigUrl,
    String? resetProgressUrl,
  String? getGameDataUrl,
  }) : getNextUrl = getNextUrl ?? Config.getNextFramesUrl,
       submitUrl = submitUrl ?? Config.submitAnswerUrl,
       getMusicLibraryUrl = Config.getMusicLibraryUrl,
       fetchConfigUrl = fetchConfigUrl ?? Config.fetchConfigUrl,
     resetProgressUrl = resetProgressUrl ?? Config.resetProgressUrl,
     getGameDataUrl = getGameDataUrl ?? Config.getGameDataUrl;

  Future<Map<String, dynamic>> getNextFrames(String code) async {
    final uri = Uri.parse(getNextUrl).replace(queryParameters: {'code': code});
    try {
      final r = await http.get(uri);
      if (r.statusCode != 200) {
        // log details for debugging
        print('FunctionsApi.getNextFrames ERROR: HTTP ${r.statusCode}');
        print('URL: $uri');
        print('Response body: ${r.body}');
        throw Exception('getNextFrames failed: HTTP ${r.statusCode}');
      }
      return jsonDecode(r.body) as Map<String, dynamic>;
    } catch (e, st) {
      print('FunctionsApi.getNextFrames exception: $e');
      print(st);
      rethrow;
    }
  }

  // New: idToken-aware variant for authenticated flows. If idToken provided,
  // send Authorization: Bearer <idToken>. If code is provided, include it
  // as a fallback query parameter for compatibility.
  Future<Map<String, dynamic>> getNextFramesAuth({String? idToken, String? code}) async {
    Uri uri = Uri.parse(getNextUrl);
    if (code != null) uri = uri.replace(queryParameters: {'code': code});
    try {
      final headers = <String, String>{};
      if (idToken != null && idToken.isNotEmpty) headers['Authorization'] = 'Bearer $idToken';
      final r = await http.get(uri, headers: headers);
      if (r.statusCode != 200) {
        print('FunctionsApi.getNextFramesAuth ERROR: HTTP ${r.statusCode}');
        print('URL: $uri');
        print('Response body: ${r.body}');
        throw Exception('getNextFrames failed: HTTP ${r.statusCode}');
      }
      return jsonDecode(r.body) as Map<String, dynamic>;
    } catch (e, st) {
      print('FunctionsApi.getNextFramesAuth exception: $e');
      print(st);
      rethrow;
    }
  }

  Future<Map<String, dynamic>> getMusicLibrary() async {
    final uri = Uri.parse(getMusicLibraryUrl);
    try {
      final r = await http.get(uri);
      if (r.statusCode != 200) {
        print('FunctionsApi.getMusicLibrary ERROR: HTTP ${r.statusCode}');
        print('URL: $uri');
        print('Response body: ${r.body}');
        throw Exception('getMusicLibrary failed: HTTP ${r.statusCode}');
      }
      return jsonDecode(r.body) as Map<String, dynamic>;
    } catch (e, st) {
      print('FunctionsApi.getMusicLibrary exception: $e');
      print(st);
      rethrow;
    }
  }

  Future<Map<String, dynamic>> submitAnswer({
    String? idToken,
    String? code,
    required String questionSetId,
    required String questionId,
    required String answer,
  }) async {
    final uri = Uri.parse(submitUrl);
    final payload = {
      if (code != null) 'code': code,
      'questionSetId': questionSetId,
      'questionId': questionId,
      'answer': answer,
    };
    try {
      final headers = {'Content-Type': 'application/json'};
      if (idToken != null && idToken.isNotEmpty) headers['Authorization'] = 'Bearer $idToken';
      final r = await http.post(
        uri,
        body: jsonEncode(payload),
        headers: headers,
      );
      if (r.statusCode != 200) {
        print('FunctionsApi.submitAnswer ERROR: HTTP ${r.statusCode}');
        print('URL: $uri');
        print('Payload: ${jsonEncode(payload)}');
        print('Response body: ${r.body}');
        throw Exception('submitAnswer failed: HTTP ${r.statusCode}');
      }
      return jsonDecode(r.body) as Map<String, dynamic>;
    } catch (e, st) {
      print('FunctionsApi.submitAnswer exception: $e');
      print(st);
      rethrow;
    }
  }

  Future<Map<String, dynamic>> fetchConfig() async {
    final uri = Uri.parse(fetchConfigUrl);
    try {
      final r = await http.get(uri);
      if (r.statusCode != 200) {
        print('FunctionsApi.fetchConfig ERROR: HTTP ${r.statusCode}');
        print('URL: $uri');
        print('Response body: ${r.body}');
        throw Exception('fetchConfig failed: HTTP ${r.statusCode}');
      }
      return jsonDecode(r.body) as Map<String, dynamic>;
    } catch (e, st) {
      print('FunctionsApi.fetchConfig exception: $e');
      print(st);
      rethrow;
    }
  }

  Future<Map<String, dynamic>> resetProgress({String? idToken, String? code}) async {
    final uri = Uri.parse(resetProgressUrl);
    try {
      final headers = {'Content-Type': 'application/json'};
      if (idToken != null && idToken.isNotEmpty) headers['Authorization'] = 'Bearer $idToken';
      final r = await http.post(
        uri,
        body: jsonEncode({if (code != null) 'code': code}),
        headers: headers,
      );
      if (r.statusCode != 200) {
        print('FunctionsApi.resetProgress ERROR: HTTP ${r.statusCode}');
        print('URL: $uri');
        print('Response body: ${r.body}');
        throw Exception('resetProgress failed: HTTP ${r.statusCode}');
      }
      return jsonDecode(r.body) as Map<String, dynamic>;
    } catch (e, st) {
      print('FunctionsApi.resetProgress exception: $e');
      print(st);
      rethrow;
    }
  }

  // Bulk game data fetch: frames + questionSets + progress
  Future<Map<String, dynamic>> getGameData({required String idToken}) async {
    final uri = Uri.parse(getGameDataUrl);
    try {
      final headers = <String, String>{'Authorization': 'Bearer $idToken'};
      final r = await http.get(uri, headers: headers);
      if (r.statusCode != 200) {
        print('FunctionsApi.getGameData ERROR: HTTP ${r.statusCode}');
        print('URL: $uri');
        print('Response body: ${r.body}');
        throw Exception('getGameData failed: HTTP ${r.statusCode}');
      }
      return jsonDecode(r.body) as Map<String, dynamic>;
    } catch (e, st) {
      print('FunctionsApi.getGameData exception: $e');
      print(st);
      rethrow;
    }
  }
}
