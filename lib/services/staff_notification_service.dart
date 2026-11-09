
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/backend_config.dart';
import 'auth_service.dart';
import 'api_client.dart';

class StaffNotification {
  final String id;
  final String appointmentId;
  final String eventType;
  final String title;
  final String message;
  final DateTime? createdAt;
  final bool read;

  const StaffNotification({
    required this.id,
    required this.appointmentId,
    required this.eventType,
    required this.title,
    required this.message,
    required this.createdAt,
    required this.read,
  });

  factory StaffNotification.fromMap(Map<String, dynamic> map) {
    return StaffNotification(
      id: map['id']?.toString() ?? '',
      appointmentId: map['appointmentId']?.toString() ?? '',
      eventType: map['eventType']?.toString() ?? '',
      title: map['title']?.toString() ?? '',
      message: map['message']?.toString() ?? '',
      createdAt: map['createdAt'] == null
          ? null
          : DateTime.tryParse(map['createdAt'].toString()),
      read: map['read'] == true,
    );
  }
}

class StaffNotificationPreferences {
  final bool enabled;
  final bool appointments;
  final bool consultations;
  final bool messages;
  final bool system;

  const StaffNotificationPreferences({
    this.enabled = true,
    this.appointments = true,
    this.consultations = true,
    this.messages = true,
    this.system = true,
  });

  factory StaffNotificationPreferences.fromMap(
    Map<String, dynamic> map,
  ) {
    final categories = map['categories'] is Map
        ? Map<String, dynamic>.from(map['categories'])
        : <String, dynamic>{};

    return StaffNotificationPreferences(
      enabled: map['enabled'] != false,
      appointments: categories['appointments'] != false,
      consultations: categories['consultations'] != false,
      messages: categories['messages'] != false,
      system: categories['system'] != false,
    );
  }
}

class StaffNotificationService {
  final AuthService _auth = AuthService();

  String get _url => BackendConfig.baseUrl;

  String get _token {
    final token = _auth.profileSessionToken;

    if (token == null || token.isEmpty) {
      throw ApiException(
        401,
        'Your staff session has expired. Please select your profile again.',
      );
    }

    return token;
  }

  Future<Map<String, dynamic>> _post(
    String path, {
    Map<String, dynamic> body = const {},
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$_url$path'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $_token',
            },
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 20));

      Map<String, dynamic> data = {};

      try {
        final decoded = jsonDecode(
          utf8.decode(response.bodyBytes),
        );

        if (decoded is Map<String, dynamic>) {
          data = decoded;
        }
      } catch (_) {}

      if (response.statusCode < 200 ||
          response.statusCode >= 300 ||
          data['success'] != true) {
        throw ApiException(
          response.statusCode,
          data['error']?.toString() ??
              'Unable to complete the notification request.',
        );
      }

      return data;
    } on ApiException {
      rethrow;
    } catch (_) {
      throw ApiException(
        0,
        'Cannot reach the notification service. Check your connection.',
      );
    }
  }

  Future<List<StaffNotification>> getNotifications() async {
    final data = await _post('/api/staff/notifications');

    final items = data['notifications'];

    if (items is! List) return [];

    return items
        .whereType<Map>()
        .map(
          (item) => StaffNotification.fromMap(
            Map<String, dynamic>.from(item),
          ),
        )
        .toList();
  }

  Future<void> markAsRead(String notificationId) async {
    await _post(
      '/api/staff/notifications/read',
      body: {'notificationId': notificationId},
    );
  }

  Future<StaffNotificationPreferences> getPreferences() async {
    final data = await _post(
      '/api/staff/notifications/preferences',
    );

    final preferences = data['preferences'];

    return StaffNotificationPreferences.fromMap(
      preferences is Map
          ? Map<String, dynamic>.from(preferences)
          : <String, dynamic>{},
    );
  }

  Future<void> updatePreferences(
    StaffNotificationPreferences preferences,
  ) async {
    await _post(
      '/api/staff/notifications/preferences/update',
      body: {
        'enabled': preferences.enabled,
        'categories': {
          'appointments': preferences.appointments,
          'consultations': preferences.consultations,
          'messages': preferences.messages,
          'system': preferences.system,
        },
      },
    );
  }
}
