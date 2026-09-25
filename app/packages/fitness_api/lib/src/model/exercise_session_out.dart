//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:json_annotation/json_annotation.dart';

part 'exercise_session_out.g.dart';

@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class ExerciseSessionOut {
  /// Returns a new [ExerciseSessionOut] instance.
  ExerciseSessionOut({
    required this.activeZoneMinutes,

    required this.averageHeartRate,

    required this.date,

    required this.durationMinutes,

    required this.endTs,

    required this.estimatedLoad,

    required this.exerciseType,

    required this.id,

    required this.metrics,

    required this.refId,

    required this.skipped,

    required this.source_,

    required this.startTs,

    required this.title,
  });

  @JsonKey(name: r'active_zone_minutes', required: true, includeIfNull: true)
  final num? activeZoneMinutes;

  @JsonKey(name: r'average_heart_rate', required: true, includeIfNull: true)
  final num? averageHeartRate;

  @JsonKey(name: r'date', required: true, includeIfNull: false)
  final DateTime date;

  @JsonKey(name: r'duration_minutes', required: true, includeIfNull: true)
  final num? durationMinutes;

  @JsonKey(name: r'end_ts', required: true, includeIfNull: true)
  final DateTime? endTs;

  @JsonKey(name: r'estimated_load', required: true, includeIfNull: true)
  final num? estimatedLoad;

  @JsonKey(name: r'exercise_type', required: true, includeIfNull: true)
  final String? exerciseType;

  @JsonKey(name: r'id', required: true, includeIfNull: false)
  final String id;

  @JsonKey(name: r'metrics', required: true, includeIfNull: false)
  final Map<String, num> metrics;

  @JsonKey(name: r'ref_id', required: true, includeIfNull: true)
  final String? refId;

  @JsonKey(name: r'skipped', required: true, includeIfNull: false)
  final bool skipped;

  @JsonKey(name: r'source', required: true, includeIfNull: false)
  final String source_;

  @JsonKey(name: r'start_ts', required: true, includeIfNull: true)
  final DateTime? startTs;

  @JsonKey(name: r'title', required: true, includeIfNull: true)
  final String? title;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ExerciseSessionOut &&
          other.activeZoneMinutes == activeZoneMinutes &&
          other.averageHeartRate == averageHeartRate &&
          other.date == date &&
          other.durationMinutes == durationMinutes &&
          other.endTs == endTs &&
          other.estimatedLoad == estimatedLoad &&
          other.exerciseType == exerciseType &&
          other.id == id &&
          other.metrics == metrics &&
          other.refId == refId &&
          other.skipped == skipped &&
          other.source_ == source_ &&
          other.startTs == startTs &&
          other.title == title;

  @override
  int get hashCode =>
      (activeZoneMinutes == null ? 0 : activeZoneMinutes.hashCode) +
      (averageHeartRate == null ? 0 : averageHeartRate.hashCode) +
      date.hashCode +
      (durationMinutes == null ? 0 : durationMinutes.hashCode) +
      (endTs == null ? 0 : endTs.hashCode) +
      (estimatedLoad == null ? 0 : estimatedLoad.hashCode) +
      (exerciseType == null ? 0 : exerciseType.hashCode) +
      id.hashCode +
      metrics.hashCode +
      (refId == null ? 0 : refId.hashCode) +
      skipped.hashCode +
      source_.hashCode +
      (startTs == null ? 0 : startTs.hashCode) +
      (title == null ? 0 : title.hashCode);

  factory ExerciseSessionOut.fromJson(Map<String, dynamic> json) =>
      _$ExerciseSessionOutFromJson(json);

  Map<String, dynamic> toJson() => _$ExerciseSessionOutToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }
}
