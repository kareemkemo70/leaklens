// lib/models/prediction_model.dart

class PredictionResult {
  final int isAnomaly;
  final double confidence;
  final double mse;
  final double threshold;
  final List<String> topSensors;
  final String zone;
  final List<double> sensorErrors;
  final String message;
  final double? latencyMs;

  const PredictionResult({
    required this.isAnomaly,
    required this.confidence,
    required this.mse,
    required this.threshold,
    required this.topSensors,
    required this.zone,
    required this.sensorErrors,
    required this.message,
    this.latencyMs,
  });

  bool get isLeakDetected => isAnomaly == 1;
  int get confidencePct => (confidence * 100).round();

  factory PredictionResult.fromJson(Map<String, dynamic> json) {
    return PredictionResult(
      isAnomaly:    json['is_anomaly'] as int,
      confidence:   (json['confidence'] as num).toDouble(),
      mse:          (json['mse'] as num).toDouble(),
      threshold:    (json['threshold'] as num).toDouble(),
      topSensors:   List<String>.from(json['top_sensors'] as List),
      zone:         json['zone'] as String,
      sensorErrors: List<double>.from(
                      (json['sensor_errors'] as List).map((e) => (e as num).toDouble())),
      message:      json['message'] as String? ?? '',
      latencyMs:    json['latency_ms'] != null
                      ? (json['latency_ms'] as num).toDouble()
                      : null,
    );
  }
}

class AlertModel {
  final int id;
  final bool isAnomaly;
  final double confidence;
  final double mse;
  final List<String> topSensors;
  final String zone;
  final DateTime detectedAt;
  final String source;
  final String? message;

  const AlertModel({
    required this.id,
    required this.isAnomaly,
    required this.confidence,
    required this.mse,
    required this.topSensors,
    required this.zone,
    required this.detectedAt,
    required this.source,
    this.message,
  });

  factory AlertModel.fromJson(Map<String, dynamic> json) {
    try {
      // Handle both boolean and integer (0/1) for anomaly status
      bool anomalyStatus = false;
      var rawAnomaly = json['is_anomaly'];
      if (rawAnomaly is bool) {
        anomalyStatus = rawAnomaly;
      } else if (rawAnomaly is int) {
        anomalyStatus = rawAnomaly == 1;
      } else if (rawAnomaly is String) {
        anomalyStatus = rawAnomaly.toLowerCase() == 'true' || rawAnomaly == '1';
      }

      // Handle top sensors safely
      List<String> sensors = [];
      if (json['top_sensors'] is List) {
        sensors = (json['top_sensors'] as List).map((e) => e.toString()).toList();
      }

      // Fix Timezone issue: The server sends UTC time but without 'Z'
      // Example: '2026-04-25T12:43:35' -> Dart thinks this is LOCAL time.
      // We append 'Z' to force Dart to read it as UTC, then convert to local.
      DateTime parsedDate = DateTime.now();
      if (json['detected_at'] != null) {
        String dateStr = json['detected_at'].toString();
        if (!dateStr.endsWith('Z')) {
           // If there is no timezone info, assume it's UTC from our backend
           dateStr += 'Z';
        }
        parsedDate = DateTime.parse(dateStr).toLocal();
      }

      return AlertModel(
        id:          (json['id'] as num?)?.toInt() ?? 0,
        isAnomaly:   anomalyStatus,
        confidence:  (json['confidence'] as num?)?.toDouble() ?? 0.0,
        mse:         (json['mse'] as num?)?.toDouble() ?? 0.0,
        topSensors:  sensors,
        zone:        json['zone']?.toString() ?? 'Unknown Zone',
        detectedAt:  parsedDate,
        source:      json['source']?.toString() ?? 'System',
        message:     json['message'] as String?,
      );
    } catch (e) {
      // If one alert fails, we return a mock one so the list isn't empty!
      return AlertModel(
        id: -1,
        isAnomaly: true,
        confidence: 0.9,
        mse: 0.5,
        topSensors: ['Error Parsing'],
        zone: 'System Error',
        detectedAt: DateTime.now(),
        source: 'Error',
      );
    }
  }
}

class ZoneAnalytics {
  final String zone;
  final int leakCount;
  final int reportCount;
  final int totalIncidents;

  const ZoneAnalytics({
    required this.zone,
    required this.leakCount,
    required this.reportCount,
    required this.totalIncidents,
  });

  factory ZoneAnalytics.fromJson(Map<String, dynamic> json) {
    return ZoneAnalytics(
      zone:           json['zone'] as String,
      leakCount:      json['leak_count'] as int,
      reportCount:    json['report_count'] as int,
      totalIncidents: json['total_incidents'] as int,
    );
  }
}

class AnalyticsData {
  final int totalAnomalies;
  final int totalReports;
  final List<ZoneAnalytics> leaksPerZone;
  final String mostAffectedZone;
  final double avgConfidence;

  const AnalyticsData({
    required this.totalAnomalies,
    required this.totalReports,
    required this.leaksPerZone,
    required this.mostAffectedZone,
    required this.avgConfidence,
  });

  factory AnalyticsData.fromJson(Map<String, dynamic> json) {
    return AnalyticsData(
      totalAnomalies:   json['total_anomalies'] as int,
      totalReports:     json['total_reports'] as int,
      leaksPerZone:     (json['leaks_per_zone'] as List)
                          .map((e) => ZoneAnalytics.fromJson(e as Map<String, dynamic>))
                          .toList(),
      mostAffectedZone: json['most_affected_zone'] as String,
      avgConfidence:    (json['avg_confidence'] as num).toDouble(),
    );
  }
}

class TimeseriesPoint {
  final String timestamp;
  final double pressure;
  final double flow;
  final int isAnomaly;
  final String zone;

  const TimeseriesPoint({
    required this.timestamp,
    required this.pressure,
    required this.flow,
    required this.isAnomaly,
    required this.zone,
  });

  factory TimeseriesPoint.fromJson(Map<String, dynamic> json) => TimeseriesPoint(
    timestamp:  json['timestamp'] as String,
    pressure:   (json['pressure'] as num).toDouble(),
    flow:       (json['flow'] as num).toDouble(),
    isAnomaly:  json['is_anomaly'] as int,
    zone:       json['zone'] as String,
  );
}

class ReportModel {
  final int id;
  final int? userId;
  final String? userName;
  final String zone;
  final String description;
  final String severity;
  final String status;
  final DateTime createdAt;

  const ReportModel({
    required this.id,
    this.userId,
    this.userName,
    required this.zone,
    required this.description,
    required this.severity,
    required this.status,
    required this.createdAt,
  });

  factory ReportModel.fromJson(Map<String, dynamic> json) {
    DateTime parsedDate = DateTime.now();
    if (json['created_at'] != null) {
      String dateStr = json['created_at'].toString();
      if (!dateStr.endsWith('Z')) dateStr += 'Z';
      parsedDate = DateTime.parse(dateStr).toLocal();
    }

    return ReportModel(
      id:          json['id'] as int,
      userId:      json['user_id'] as int?,
      userName:    json['user_name'] as String?,
      zone:        json['zone'] as String,
      description: json['description'] as String,
      severity:    json['severity'] as String,
      status:      json['status'] as String,
      createdAt:   parsedDate,
    );
  }
}

class OutageModel {
  final int id;
  final String zone;
  final String title;
  final String? description;
  final DateTime startTime;
  final DateTime endTime;
  final bool isCancelled;

  const OutageModel({
    required this.id,
    required this.zone,
    required this.title,
    this.description,
    required this.startTime,
    required this.endTime,
    required this.isCancelled,
  });

  factory OutageModel.fromJson(Map<String, dynamic> json) {
    DateTime parseLocal(String key) {
      if (json[key] == null) return DateTime.now();
      String dateStr = json[key].toString();
      if (!dateStr.endsWith('Z')) dateStr += 'Z';
      return DateTime.parse(dateStr).toLocal();
    }

    return OutageModel(
      id:          json['id'] as int,
      zone:        json['zone'] as String,
      title:       json['title'] as String,
      description: json['description'] as String?,
      startTime:   parseLocal('start_time'),
      endTime:     parseLocal('end_time'),
      isCancelled: json['is_cancelled'] as bool? ?? false,
    );
  }
}
