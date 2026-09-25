import 'package:fitness_api/src/model/ai_report_out.dart';
import 'package:fitness_api/src/model/calendar_event_out.dart';
import 'package:fitness_api/src/model/daily_health_out.dart';
import 'package:fitness_api/src/model/day_point_out.dart';
import 'package:fitness_api/src/model/drink_count_in.dart';
import 'package:fitness_api/src/model/drink_counter_out.dart';
import 'package:fitness_api/src/model/drink_day_out.dart';
import 'package:fitness_api/src/model/exercise_session_out.dart';
import 'package:fitness_api/src/model/google_status_out.dart';
import 'package:fitness_api/src/model/http_validation_error.dart';
import 'package:fitness_api/src/model/health.dart';
import 'package:fitness_api/src/model/heart_rate_zone_out.dart';
import 'package:fitness_api/src/model/latest_measurements_out.dart';
import 'package:fitness_api/src/model/match_out.dart';
import 'package:fitness_api/src/model/me.dart';
import 'package:fitness_api/src/model/measurement_out.dart';
import 'package:fitness_api/src/model/missing_match_out.dart';
import 'package:fitness_api/src/model/o_auth_callback_out.dart';
import 'package:fitness_api/src/model/o_auth_login_out.dart';
import 'package:fitness_api/src/model/push_device_in.dart';
import 'package:fitness_api/src/model/push_device_out.dart';
import 'package:fitness_api/src/model/push_token_in.dart';
import 'package:fitness_api/src/model/refresh_report_out.dart';
import 'package:fitness_api/src/model/score_point_out.dart';
import 'package:fitness_api/src/model/session_heart_rate_out.dart';
import 'package:fitness_api/src/model/skip_in.dart';
import 'package:fitness_api/src/model/skip_out.dart';
import 'package:fitness_api/src/model/sync_out.dart';
import 'package:fitness_api/src/model/token_status_out.dart';
import 'package:fitness_api/src/model/training_status_out.dart';
import 'package:fitness_api/src/model/validation_error.dart';

final _regList = RegExp(r'^List<(.*)>$');
final _regSet = RegExp(r'^Set<(.*)>$');
final _regMap = RegExp(r'^Map<String,(.*)>$');

ReturnType deserialize<ReturnType, BaseType>(
  dynamic value,
  String targetType, {
  bool growable = true,
}) {
  switch (targetType) {
    case 'String':
      return '$value' as ReturnType;
    case 'int':
      return (value is int ? value : int.parse('$value')) as ReturnType;
    case 'bool':
      if (value is bool) {
        return value as ReturnType;
      }
      final valueString = '$value'.toLowerCase();
      return (valueString == 'true' || valueString == '1') as ReturnType;
    case 'double':
      return (value is double ? value : double.parse('$value')) as ReturnType;
    case 'AiReportOut':
      return AiReportOut.fromJson(value as Map<String, dynamic>) as ReturnType;
    case 'CalendarEventOut':
      return CalendarEventOut.fromJson(value as Map<String, dynamic>)
          as ReturnType;
    case 'DailyHealthOut':
      return DailyHealthOut.fromJson(value as Map<String, dynamic>)
          as ReturnType;
    case 'DayPointOut':
      return DayPointOut.fromJson(value as Map<String, dynamic>) as ReturnType;
    case 'DrinkCountIn':
      return DrinkCountIn.fromJson(value as Map<String, dynamic>) as ReturnType;
    case 'DrinkCounterOut':
      return DrinkCounterOut.fromJson(value as Map<String, dynamic>)
          as ReturnType;
    case 'DrinkDayOut':
      return DrinkDayOut.fromJson(value as Map<String, dynamic>) as ReturnType;
    case 'ExerciseSessionOut':
      return ExerciseSessionOut.fromJson(value as Map<String, dynamic>)
          as ReturnType;
    case 'GoogleStatusOut':
      return GoogleStatusOut.fromJson(value as Map<String, dynamic>)
          as ReturnType;
    case 'HTTPValidationError':
      return HTTPValidationError.fromJson(value as Map<String, dynamic>)
          as ReturnType;
    case 'Health':
      return Health.fromJson(value as Map<String, dynamic>) as ReturnType;
    case 'HeartRateZoneOut':
      return HeartRateZoneOut.fromJson(value as Map<String, dynamic>)
          as ReturnType;
    case 'LatestMeasurementsOut':
      return LatestMeasurementsOut.fromJson(value as Map<String, dynamic>)
          as ReturnType;
    case 'MatchOut':
      return MatchOut.fromJson(value as Map<String, dynamic>) as ReturnType;
    case 'Me':
      return Me.fromJson(value as Map<String, dynamic>) as ReturnType;
    case 'MeasurementOut':
      return MeasurementOut.fromJson(value as Map<String, dynamic>)
          as ReturnType;
    case 'MissingMatchOut':
      return MissingMatchOut.fromJson(value as Map<String, dynamic>)
          as ReturnType;
    case 'OAuthCallbackOut':
      return OAuthCallbackOut.fromJson(value as Map<String, dynamic>)
          as ReturnType;
    case 'OAuthLoginOut':
      return OAuthLoginOut.fromJson(value as Map<String, dynamic>)
          as ReturnType;
    case 'PushDeviceIn':
      return PushDeviceIn.fromJson(value as Map<String, dynamic>) as ReturnType;
    case 'PushDeviceOut':
      return PushDeviceOut.fromJson(value as Map<String, dynamic>)
          as ReturnType;
    case 'PushTokenIn':
      return PushTokenIn.fromJson(value as Map<String, dynamic>) as ReturnType;
    case 'RefreshReportOut':
      return RefreshReportOut.fromJson(value as Map<String, dynamic>)
          as ReturnType;
    case 'ScorePointOut':
      return ScorePointOut.fromJson(value as Map<String, dynamic>)
          as ReturnType;
    case 'SessionHeartRateOut':
      return SessionHeartRateOut.fromJson(value as Map<String, dynamic>)
          as ReturnType;
    case 'SkipIn':
      return SkipIn.fromJson(value as Map<String, dynamic>) as ReturnType;
    case 'SkipOut':
      return SkipOut.fromJson(value as Map<String, dynamic>) as ReturnType;
    case 'SyncOut':
      return SyncOut.fromJson(value as Map<String, dynamic>) as ReturnType;
    case 'TokenStatusOut':
      return TokenStatusOut.fromJson(value as Map<String, dynamic>)
          as ReturnType;
    case 'TrainingStatusOut':
      return TrainingStatusOut.fromJson(value as Map<String, dynamic>)
          as ReturnType;
    case 'ValidationError':
      return ValidationError.fromJson(value as Map<String, dynamic>)
          as ReturnType;
    default:
      RegExpMatch? match;

      if (value is List && (match = _regList.firstMatch(targetType)) != null) {
        targetType = match![1]!; // ignore: parameter_assignments
        return value
                .map<BaseType>(
                  (dynamic v) => deserialize<BaseType, BaseType>(
                    v,
                    targetType,
                    growable: growable,
                  ),
                )
                .toList(growable: growable)
            as ReturnType;
      }
      if (value is Set && (match = _regSet.firstMatch(targetType)) != null) {
        targetType = match![1]!; // ignore: parameter_assignments
        return value
                .map<BaseType>(
                  (dynamic v) => deserialize<BaseType, BaseType>(
                    v,
                    targetType,
                    growable: growable,
                  ),
                )
                .toSet()
            as ReturnType;
      }
      if (value is Map && (match = _regMap.firstMatch(targetType)) != null) {
        targetType = match![1]!.trim(); // ignore: parameter_assignments
        return Map<String, BaseType>.fromIterables(
              value.keys as Iterable<String>,
              value.values.map(
                (dynamic v) => deserialize<BaseType, BaseType>(
                  v,
                  targetType,
                  growable: growable,
                ),
              ),
            )
            as ReturnType;
      }
      break;
  }
  throw Exception('Cannot deserialize');
}
