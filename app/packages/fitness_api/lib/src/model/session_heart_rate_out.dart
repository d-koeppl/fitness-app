//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:fitness_api/src/model/heart_rate_zone_out.dart';
import 'package:json_annotation/json_annotation.dart';

part 'session_heart_rate_out.g.dart';

@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class SessionHeartRateOut {
  /// Returns a new [SessionHeartRateOut] instance.
  SessionHeartRateOut({
    required this.averageBpm,

    required this.date,

    required this.endTs,

    required this.fetchedAt,

    required this.maxBpm,

    required this.maxHr,

    required this.minBpm,

    required this.restingHr,

    required this.sampleCount,

    required this.samples,

    required this.sessionId,

    required this.startTs,

    required this.zoneSource,

    required this.zones,
  });

  @JsonKey(name: r'average_bpm', required: true, includeIfNull: true)
  final num? averageBpm;

  @JsonKey(name: r'date', required: true, includeIfNull: false)
  final DateTime date;

  @JsonKey(name: r'end_ts', required: true, includeIfNull: true)
  final DateTime? endTs;

  @JsonKey(name: r'fetched_at', required: true, includeIfNull: true)
  final DateTime? fetchedAt;

  @JsonKey(name: r'max_bpm', required: true, includeIfNull: true)
  final int? maxBpm;

  @JsonKey(name: r'max_hr', required: true, includeIfNull: true)
  final int? maxHr;

  @JsonKey(name: r'min_bpm', required: true, includeIfNull: true)
  final int? minBpm;

  @JsonKey(name: r'resting_hr', required: true, includeIfNull: true)
  final int? restingHr;

  @JsonKey(name: r'sample_count', required: true, includeIfNull: false)
  final int sampleCount;

  @JsonKey(name: r'samples', required: true, includeIfNull: false)
  final List<List<Object>> samples;

  @JsonKey(name: r'session_id', required: true, includeIfNull: false)
  final String sessionId;

  @JsonKey(name: r'start_ts', required: true, includeIfNull: true)
  final DateTime? startTs;

  @JsonKey(name: r'zone_source', required: true, includeIfNull: true)
  final String? zoneSource;

  @JsonKey(name: r'zones', required: true, includeIfNull: false)
  final List<HeartRateZoneOut> zones;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SessionHeartRateOut &&
          other.averageBpm == averageBpm &&
          other.date == date &&
          other.endTs == endTs &&
          other.fetchedAt == fetchedAt &&
          other.maxBpm == maxBpm &&
          other.maxHr == maxHr &&
          other.minBpm == minBpm &&
          other.restingHr == restingHr &&
          other.sampleCount == sampleCount &&
          other.samples == samples &&
          other.sessionId == sessionId &&
          other.startTs == startTs &&
          other.zoneSource == zoneSource &&
          other.zones == zones;

  @override
  int get hashCode =>
      (averageBpm == null ? 0 : averageBpm.hashCode) +
      date.hashCode +
      (endTs == null ? 0 : endTs.hashCode) +
      (fetchedAt == null ? 0 : fetchedAt.hashCode) +
      (maxBpm == null ? 0 : maxBpm.hashCode) +
      (maxHr == null ? 0 : maxHr.hashCode) +
      (minBpm == null ? 0 : minBpm.hashCode) +
      (restingHr == null ? 0 : restingHr.hashCode) +
      sampleCount.hashCode +
      samples.hashCode +
      sessionId.hashCode +
      (startTs == null ? 0 : startTs.hashCode) +
      (zoneSource == null ? 0 : zoneSource.hashCode) +
      zones.hashCode;

  factory SessionHeartRateOut.fromJson(Map<String, dynamic> json) =>
      _$SessionHeartRateOutFromJson(json);

  Map<String, dynamic> toJson() => _$SessionHeartRateOutToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }
}
