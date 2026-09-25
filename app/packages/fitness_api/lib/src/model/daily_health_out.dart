//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:json_annotation/json_annotation.dart';

part 'daily_health_out.g.dart';

@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class DailyHealthOut {
  /// Returns a new [DailyHealthOut] instance.
  DailyHealthOut({
    required this.activeZoneMinutes,

    required this.date,

    required this.hrvMs,

    required this.restingHr,

    required this.sleepMinutes,

    required this.steps,

    required this.vo2max,

    required this.weightKg,
  });

  @JsonKey(name: r'active_zone_minutes', required: true, includeIfNull: true)
  final int? activeZoneMinutes;

  @JsonKey(name: r'date', required: true, includeIfNull: false)
  final DateTime date;

  @JsonKey(name: r'hrv_ms', required: true, includeIfNull: true)
  final num? hrvMs;

  @JsonKey(name: r'resting_hr', required: true, includeIfNull: true)
  final int? restingHr;

  @JsonKey(name: r'sleep_minutes', required: true, includeIfNull: true)
  final int? sleepMinutes;

  @JsonKey(name: r'steps', required: true, includeIfNull: true)
  final int? steps;

  @JsonKey(name: r'vo2max', required: true, includeIfNull: true)
  final num? vo2max;

  @JsonKey(name: r'weight_kg', required: true, includeIfNull: true)
  final num? weightKg;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DailyHealthOut &&
          other.activeZoneMinutes == activeZoneMinutes &&
          other.date == date &&
          other.hrvMs == hrvMs &&
          other.restingHr == restingHr &&
          other.sleepMinutes == sleepMinutes &&
          other.steps == steps &&
          other.vo2max == vo2max &&
          other.weightKg == weightKg;

  @override
  int get hashCode =>
      (activeZoneMinutes == null ? 0 : activeZoneMinutes.hashCode) +
      date.hashCode +
      (hrvMs == null ? 0 : hrvMs.hashCode) +
      (restingHr == null ? 0 : restingHr.hashCode) +
      (sleepMinutes == null ? 0 : sleepMinutes.hashCode) +
      (steps == null ? 0 : steps.hashCode) +
      (vo2max == null ? 0 : vo2max.hashCode) +
      (weightKg == null ? 0 : weightKg.hashCode);

  factory DailyHealthOut.fromJson(Map<String, dynamic> json) =>
      _$DailyHealthOutFromJson(json);

  Map<String, dynamic> toJson() => _$DailyHealthOutToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }
}
