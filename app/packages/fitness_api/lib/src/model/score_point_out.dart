//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:json_annotation/json_annotation.dart';

part 'score_point_out.g.dart';

@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class ScorePointOut {
  /// Returns a new [ScorePointOut] instance.
  ScorePointOut({
    required this.date,

    required this.readiness,

    required this.recovery,
  });

  @JsonKey(name: r'date', required: true, includeIfNull: false)
  final String date;

  @JsonKey(name: r'readiness', required: true, includeIfNull: true)
  final int? readiness;

  @JsonKey(name: r'recovery', required: true, includeIfNull: true)
  final int? recovery;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ScorePointOut &&
          other.date == date &&
          other.readiness == readiness &&
          other.recovery == recovery;

  @override
  int get hashCode =>
      date.hashCode +
      (readiness == null ? 0 : readiness.hashCode) +
      (recovery == null ? 0 : recovery.hashCode);

  factory ScorePointOut.fromJson(Map<String, dynamic> json) =>
      _$ScorePointOutFromJson(json);

  Map<String, dynamic> toJson() => _$ScorePointOutToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }
}
