import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:schuly/api/lib/api.dart';
import 'package:http/http.dart' as http;
import 'package:sentry_flutter/sentry_flutter.dart';

/// Data fetching talks directly to the school's own Schulnetz REST API
/// (`{schulnetzBaseUrl}/rest/v1/...`) - no Schuly/SchulwareAPI backend
/// involved. `defaultApiClient.basePath`/`defaultHeaderMap['Authorization']`
/// (set by `ApiStore.bearerToken` and `setApiBaseUrl`) are reused as-is so the
/// rest of the app's auth/base-URL plumbing needs no changes; only how the
/// data itself is fetched changes. The generated DTOs below
/// (`GradeDto`, `AbsenceDto`, etc.) already match Schulnetz's raw REST JSON
/// field-for-field - they were generated from the same `/api/mobile/*`
/// SchulwareAPI spec, which did zero transformation on these fields.
class ApiService {
  AuthApi get _authApi => AuthApi();

  final Dio _dio = Dio();

  String get _restBase =>
      '${defaultApiClient.basePath.trim().replaceAll(RegExp(r'/+$'), '')}/rest/v1';

  Map<String, String> get _headers => {
        'Authorization': defaultApiClient.defaultHeaderMap['Authorization'] ?? '',
        'Accept': 'application/json',
      };

  // Performance monitoring helper
  Future<T> _withPerformanceMonitoring<T>({
    required String operationName,
    required String description,
    required Future<T> Function() operation,
    Map<String, dynamic>? data,
  }) async {
    final transaction = Sentry.startTransaction(
      operationName,
      'http.client',
    );

    transaction.setData('description', description);
    if (data != null) {
      data.forEach((key, value) => transaction.setData(key, value));
    }

    try {
      final result = await operation();
      transaction.status = const SpanStatus.ok();
      return result;
    } catch (e) {
      transaction.status = const SpanStatus.internalError();
      transaction.throwable = e;
      rethrow;
    } finally {
      await transaction.finish();
    }
  }

  // --- Email/password login: still routed through the generated AuthApi
  // (the old SchulwareAPI backend). Schools federated to Microsoft/Entra use
  // MicrosoftAuthPage instead, which talks to Schulnetz directly. ---

  Future<http.Response> authenticateWithResponse(String email, String password) {
    return _withPerformanceMonitoring(
      operationName: 'authenticate.non_microsoft',
      description: 'Non-Microsoft authentication',
      data: {'email': email},
      operation: () => _authApi.authenticateMobileWithHttpInfo(email, password).timeout(Duration(minutes: 1)),
    );
  }

  Future<AuthenticateMobileResponseDto?> authenticate(String email, String password) {
    return _withPerformanceMonitoring(
      operationName: 'authenticate.mobile',
      description: 'Mobile authentication',
      data: {'email': email},
      operation: () => _authApi.authenticateMobile(email, password),
    );
  }

  // --- Data: direct Schulnetz REST calls ---

  Future<Response<dynamic>> _get(String path) =>
      _dio.get<dynamic>('$_restBase/$path', options: Options(headers: _headers));

  Future<List<AbsenceDto>?> getAbsences() {
    return _withPerformanceMonitoring(
      operationName: 'api.get_absences',
      description: 'Fetch absences',
      operation: () async => AbsenceDto.listFromJson((await _get('me/absences')).data),
    );
  }

  Future<List<AgendaDto>?> getAgenda() {
    return _withPerformanceMonitoring(
      operationName: 'api.get_agenda',
      description: 'Fetch agenda',
      operation: () async => AgendaDto.listFromJson((await _get('me/events')).data),
    );
  }

  Future<List<GradeDto>?> getGrades() {
    return _withPerformanceMonitoring(
      operationName: 'api.get_grades',
      description: 'Fetch grades',
      operation: () async => GradeDto.listFromJson((await _get('me/grades')).data),
    );
  }

  Future<List<ExamDto>?> getExams() {
    return _withPerformanceMonitoring(
      operationName: 'api.get_exams',
      description: 'Fetch exams',
      operation: () async => ExamDto.listFromJson((await _get('me/exams')).data),
    );
  }

  Future<List<Object>?> getNotifications() {
    return _withPerformanceMonitoring(
      operationName: 'api.get_notifications',
      description: 'Fetch notifications',
      operation: () async {
        final data = (await _get('me/notifications/push')).data;
        return data is List ? List<Object>.from(data) : const [];
      },
    );
  }

  Future<UserInfoDto?> getUserInfo() {
    return _withPerformanceMonitoring(
      operationName: 'api.get_user_info',
      description: 'Fetch user info',
      operation: () async => UserInfoDto.fromJson((await _get('me')).data),
    );
  }

  Future<StudentIdCardDto?> getStudentIdCard(int reportId) {
    return _withPerformanceMonitoring(
      operationName: 'api.get_student_id_card',
      description: 'Fetch student ID card',
      data: {'report_id': reportId},
      operation: () async {
        // Schulnetz returns this one as a properly JSON-encoded string (the
        // raw HTML report) - decode it as JSON rather than hand-rolling the
        // unescaping, which only handles a few sequences and mangles anything
        // else (unicode escapes for umlauts, embedded already-escaped quotes,
        // etc.) into garbage.
        final res = await _dio.get<String>(
          '$_restBase/me/cockpitReport/$reportId',
          options: Options(headers: _headers, responseType: ResponseType.plain),
        );
        final raw = res.data ?? '';
        String html;
        try {
          final decoded = jsonDecode(raw);
          html = decoded is String ? decoded : raw;
        } on FormatException {
          // Not JSON-wrapped - already raw HTML.
          html = raw;
        }
        return StudentIdCardDto(html: html);
      },
    );
  }

  Future<List<SettingDto>?> getSettings() {
    return _withPerformanceMonitoring(
      operationName: 'api.get_settings',
      description: 'Fetch settings',
      operation: () async => SettingDto.listFromJson((await _get('config/settings')).data),
    );
  }

  Future<List<LatenessDto>?> getLateness() {
    return _withPerformanceMonitoring(
      operationName: 'api.get_lateness',
      description: 'Fetch lateness',
      operation: () async => LatenessDto.listFromJson((await _get('me/lateness')).data),
    );
  }

  Future<List<Object>?> getAbsenceNotices() {
    return _withPerformanceMonitoring(
      operationName: 'api.get_absence_notices',
      description: 'Fetch absence notices',
      operation: () async {
        final data = (await _get('me/absencenotices')).data;
        return data is List ? List<Object>.from(data) : const [];
      },
    );
  }
}
