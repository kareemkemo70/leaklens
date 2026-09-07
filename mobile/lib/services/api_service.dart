// lib/services/api_service.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/prediction_model.dart';

class ApiException implements Exception {
  final String message;
  final int? statusCode;
  const ApiException(this.message, {this.statusCode});

  @override
  String toString() => 'ApiException($statusCode): $message';
}

class ApiService {
  static String? customBaseUrl;
  static const _defaultBase = 'http://192.168.100.8:8000'; // Local network IP for physical device
  final String baseUrl;

  ApiService({String? baseUrl}) : baseUrl = baseUrl ?? customBaseUrl ?? _defaultBase;

  // ── Helpers ──────────────────────────────────────────────────────

  Uri _uri(String path, [Map<String, String>? query]) =>
      Uri.parse('$baseUrl$path').replace(queryParameters: query);

  Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    'Accept': 'application/json',
  };

  Future<dynamic> _get(String path, [Map<String, String>? q]) async {
    try {
      final resp = await http.get(_uri(path, q), headers: _headers)
          .timeout(const Duration(seconds: 15));
      return _parse(resp);
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('Network error: $e');
    }
  }

  Future<dynamic> _post(String path, Map<String, dynamic> body) async {
    try {
      final resp = await http
          .post(_uri(path), headers: _headers, body: jsonEncode(body))
          .timeout(const Duration(seconds: 30));
      return _parse(resp);
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('Network error: $e');
    }
  }

  Future<dynamic> _patch(String path, [Map<String, String>? query]) async {
    try {
      final resp = await http
          .patch(_uri(path, query), headers: _headers)
          .timeout(const Duration(seconds: 30));
      return _parse(resp);
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('Network error: $e');
    }
  }

  dynamic _parse(http.Response resp) {
    final decoded = jsonDecode(resp.body);
    if (resp.statusCode >= 400) {
      final Map<String, dynamic> errorJson = (decoded is Map) 
          ? decoded as Map<String, dynamic> 
          : {'detail': decoded.toString()};
          
      throw ApiException(
        errorJson['detail']?.toString() ?? 'Unknown error',
        statusCode: resp.statusCode,
      );
    }
    return decoded;
  }

  // ── Health ────────────────────────────────────────────────────────
  Future<Map<String, dynamic>> checkHealth() async => (await _get('/health')) as Map<String, dynamic>;

  // ── Predict ───────────────────────────────────────────────────────
  Future<PredictionResult> predict(List<List<double>> data) async {
    final json = await _post('/api/v1/predict', {'data': data});
    return PredictionResult.fromJson(json);
  }

  // ── Report ────────────────────────────────────────────────────────
  Future<Map<String, dynamic>> submitReport({
    required String zone,
    required String description,
    String severity = 'medium',
    int? userId,
  }) async {
    return (await _post('/api/v1/report', {
      'zone': zone,
      'description': description,
      'severity': severity,
      if (userId != null) 'user_id': userId,
    })) as Map<String, dynamic>;
  }

  Future<List<ReportModel>> getReports({int limit = 50, String? zone}) async {
    final q = <String, String>{'limit': '$limit'};
    if (zone != null) q['zone'] = zone;

    final json = await _get('/api/v1/reports', q);
    
    final List<dynamic> listData = (json is List) 
        ? json 
        : (json is Map && json.containsKey('items')) 
            ? json['items'] 
            : [];

    return listData
        .map((e) => ReportModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<ReportModel>> getMyReports({required int userId, int limit = 50}) async {
    final q = <String, String>{'limit': '$limit', 'user_id': '$userId'};
    final json = await _get('/api/v1/reports', q);
    
    final List<dynamic> listData = (json is List) 
        ? json 
        : (json is Map && json.containsKey('items')) 
            ? json['items'] 
            : [];

    return listData
        .map((e) => ReportModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<ReportModel> updateReportStatus({required int reportId, required String newStatus}) async {
    final json = await _patch('/api/v1/reports/$reportId/status', {'new_status': newStatus});
    return ReportModel.fromJson(json as Map<String, dynamic>);
  }

  // ── Alerts ────────────────────────────────────────────────────────
  Future<List<AlertModel>> getAlerts({int limit = 30, String? zone}) async {
    final q = <String, String>{'limit': '$limit'};
    if (zone != null) q['zone'] = zone;
    
    final json = await _get('/api/v1/alerts', q);
    
    // Check if the response is a direct list or wrapped in a map
    final List<dynamic> listData = (json is List) 
        ? json 
        : (json is Map && json.containsKey('items')) 
            ? json['items'] 
            : [];

    return listData
        .map((e) => AlertModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<AlertModel?> getLatestAlert({required String zone, required DateTime since}) async {
    try {
      final q = {'zone': zone, 'since': since.toIso8601String()};
      final json = await _get('/api/v1/latest', q);
      if (json.isEmpty) return null;
      return AlertModel.fromJson(json);
    } catch (e) {
      return null; // Silent fail for background tasks
    }
  }

  // ── Analytics ─────────────────────────────────────────────────────
  Future<AnalyticsData> getAnalytics({int days = 30}) async {
    final json = await _get('/api/v1/analytics', {'days': '$days'});
    return AnalyticsData.fromJson(json);
  }

  // ── Timeseries ────────────────────────────────────────────────────
  Future<List<TimeseriesPoint>> getTimeseries({int hours = 24}) async {
    final json = await _get('/api/v1/timeseries', {'hours': '$hours'});
    return (json['series'] as List)
        .map((e) => TimeseriesPoint.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // ── Auth ──────────────────────────────────────────────────────────
  Future<Map<String, dynamic>> registerUser({
    required String name,
    required String address,
    required String zone,
    required String phone,
    required String email,
    required String password,
  }) async {
    return (await _post('/api/v1/auth/user/register', {
      'name': name, 'address': address, 'zone': zone,
      'phone': phone, 'email': email, 'password': password,
    })) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> loginUser({
    String? email,
    String? phone,
    required String password,
  }) async {
    return (await _post('/api/v1/auth/user/login', {
      if (email != null) 'email': email,
      if (phone != null) 'phone': phone,
      'password': password,
    })) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> registerEngineer({
    required String name,
    required String engineerId,
    required String password,
  }) async {
    return (await _post('/api/v1/auth/engineer/register', {
      'name': name,
      'engineer_id': engineerId,
      'password': password,
    })) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> loginEngineer({
    required String engineerId,
    required String password,
  }) async {
    return (await _post('/api/v1/auth/engineer/login', {
      'engineer_id': engineerId,
      'password': password,
    })) as Map<String, dynamic>;
  }

  // ── Delete helpers ────────────────────────────────────────────────
  Future<void> _delete(String path) async {
    try {
      final resp = await http
          .delete(_uri(path), headers: _headers)
          .timeout(const Duration(seconds: 15));
      if (resp.statusCode >= 400) {
        final decoded = jsonDecode(resp.body);
        throw ApiException(
          (decoded is Map ? decoded['detail'] : decoded).toString(),
          statusCode: resp.statusCode,
        );
      }
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('Network error: $e');
    }
  }

  Future<void> deleteAlert(int alertId) => _delete('/api/v1/alerts/$alertId');
  Future<void> deleteReport(int reportId) => _delete('/api/v1/reports/$reportId');

  Future<Map<String, dynamic>> resetData() async =>
      (await _post('/api/v1/reset-data', {})) as Map<String, dynamic>;

  // ── Outages ───────────────────────────────────────────────────────
  Future<List<OutageModel>> getOutages({String? zone, bool includePast = false}) async {
    final q = <String, String>{'include_past': '$includePast'};
    if (zone != null) q['zone'] = zone;
    final json = await _get('/api/v1/outages', q);
    final List<dynamic> list = json is List ? json : [];
    return list.map((e) => OutageModel.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<OutageModel> createOutage({
    required String zone,
    required String title,
    String? description,
    required DateTime startTime,
    required DateTime endTime,
  }) async {
    final json = await _post('/api/v1/outages', {
      'zone': zone,
      'title': title,
      if (description != null) 'description': description,
      'start_time': startTime.toUtc().toIso8601String(),
      'end_time': endTime.toUtc().toIso8601String(),
    });
    return OutageModel.fromJson(json as Map<String, dynamic>);
  }

  Future<void> deleteOutage(int outageId) => _delete('/api/v1/outages/$outageId');
}
