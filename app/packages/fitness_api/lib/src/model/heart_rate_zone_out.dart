//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:json_annotation/json_annotation.dart';

part 'heart_rate_zone_out.g.dart';

@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class HeartRateZoneOut {
  /// Returns a new [HeartRateZoneOut] instance.
  HeartRateZoneOut({
    required this.lowerBpm,

    required this.seconds,

    required this.upperBpm,

    required this.zone,
  });

  @JsonKey(name: r'lower_bpm', required: true, includeIfNull: true)
  final int? lowerBpm;

  @JsonKey(name: r'seconds', required: true, includeIfNull: false)
  final num seconds;

  @JsonKey(name: r'upper_bpm', required: true, includeIfNull: true)
  final int? upperBpm;

  @JsonKey(name: r'zone', required: true, includeIfNull: false)
  final String zone;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HeartRateZoneOut &&
          other.lowerBpm == lowerBpm &&
          other.seconds == seconds &&
          other.upperBpm == upperBpm &&
          other.zone == zone;

  @override
  int get hashCode =>
      (lowerBpm == null ? 0 : lowerBpm.hashCode) +
      seconds.hashCode +
      (upperBpm == null ? 0 : upperBpm.hashCode) +
      zone.hashCode;

  factory HeartRateZoneOut.fromJson(Map<String, dynamic> json) =>
      _$HeartRateZoneOutFromJson(json);

  Map<String, dynamic> toJson() => _$HeartRateZoneOutToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }
}
