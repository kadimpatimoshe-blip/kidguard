import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

/// Standalone Firebase Realtime Database Client for Child Mobile Application
class RtdbClientService {
  final String databaseUrl;
  final http.Client _httpClient;

  RtdbClientService({
    this.databaseUrl = 'https://kidguard-3b499-default-rtdb.asia-southeast1.firebasedatabase.app',
    http.Client? httpClient,
  }) : _httpClient = httpClient ?? http.Client();

  /// Updates or writes data at a specific path under Firebase RTDB
  Future<bool> updatePath(String path, Map<String, dynamic> data) async {
    try {
      final cleanPath = path.startsWith('/') ? path.substring(1) : path;
      final uri = Uri.parse('$databaseUrl/$cleanPath.json');
      
      final response = await _httpClient.patch(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(data),
      );

      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (e) {
      // ignore or log
      return false;
    }
  }

  /// Sets / overwrites data at a specific path under Firebase RTDB
  Future<bool> setPath(String path, dynamic data) async {
    try {
      final cleanPath = path.startsWith('/') ? path.substring(1) : path;
      final uri = Uri.parse('$databaseUrl/$cleanPath.json');
      
      final response = await _httpClient.put(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(data),
      );

      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (e) {
      return false;
    }
  }

  /// Reads data from a specific path under Firebase RTDB
  Future<dynamic> getPath(String path, {Map<String, String>? queryParams}) async {
    try {
      final cleanPath = path.startsWith('/') ? path.substring(1) : path;
      var urlStr = '$databaseUrl/$cleanPath.json';
      
      if (queryParams != null && queryParams.isNotEmpty) {
        final query = queryParams.entries
            .map((e) => '${e.key}=${Uri.encodeComponent('"${e.value}"')}')
            .join('&');
        urlStr += '?$query';
      }

      final uri = Uri.parse(urlStr);
      final response = await _httpClient.get(uri);
      
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return jsonDecode(response.body);
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  void dispose() {
    _httpClient.close();
  }
}
