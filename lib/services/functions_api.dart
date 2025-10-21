import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config.dart';

class FunctionsApi {
  final String getNextUrl;
  final String submitUrl;
  final String getMusicLibraryUrl;
  final String fetchConfigUrl;
  final String resetProgressUrl;

  FunctionsApi({
    String? getNextUrl,
    String? submitUrl,
    String? fetchConfigUrl,
    String? resetProgressUrl,
  }) : getNextUrl = getNextUrl ?? Config.getNextFramesUrl,
       submitUrl = submitUrl ?? Config.submitAnswerUrl,
       getMusicLibraryUrl = Config.getMusicLibraryUrl,
       fetchConfigUrl = fetchConfigUrl ?? Config.fetchConfigUrl,
       resetProgressUrl = resetProgressUrl ?? Config.resetProgressUrl;

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
    required String code,
    required String questionSetId,
    required String questionId,
    required String answer,
  }) async {
    final uri = Uri.parse(submitUrl);
    final payload = {
      'code': code,
      'questionSetId': questionSetId,
      'questionId': questionId,
      'answer': answer,
    };
    try {
      final r = await http.post(
        uri,
        body: jsonEncode(payload),
        headers: {'Content-Type': 'application/json'},
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

  Future<Map<String, dynamic>> resetProgress(String code) async {
    final uri = Uri.parse(resetProgressUrl);
    try {
      final r = await http.post(
        uri,
        body: jsonEncode({'code': code}),
        headers: {'Content-Type': 'application/json'},
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
}
