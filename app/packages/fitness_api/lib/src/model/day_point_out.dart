//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:json_annotation/json_annotation.dart';

part 'day_point_out.g.dart';

@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class DayPointOut {
  /// Returns a new [DayPointOut] instance.
  DayPointOut({
    required this.date,

    required this.fatigue,

    required this.fitness,

    required this.load,
  });

  @JsonKey(name: r'date', required: true, includeIfNull: false)
  final String date;

  @JsonKey(name: r'fatigue', required: true, includeIfNull: false)
  final num fatigue;

  @JsonKey(name: r'fitness', required: true, includeIfNull: false)
  final num fitness;

  @JsonKey(name: r'load', required: true, includeIfNull: false)
  final num load;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DayPointOut &&
          other.date == date &&
          other.fatigue == fatigue &&
          other.fitness == fitness &&
          other.load == load;

  @override
  int get hashCode =>
      date.hashCode + fatigue.hashCode + fitness.hashCode + load.hashCode;

  factory DayPointOut.fromJson(Map<String, dynamic> json) =>
      _$DayPointOutFromJson(json);

  Map<String, dynamic> toJson() => _$DayPointOutToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }
}
