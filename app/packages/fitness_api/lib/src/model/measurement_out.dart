//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:json_annotation/json_annotation.dart';

part 'measurement_out.g.dart';

@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class MeasurementOut {
  /// Returns a new [MeasurementOut] instance.
  MeasurementOut({required this.date, required this.value});

  @JsonKey(name: r'date', required: true, includeIfNull: false)
  final DateTime date;

  @JsonKey(name: r'value', required: true, includeIfNull: false)
  final num value;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MeasurementOut && other.date == date && other.value == value;

  @override
  int get hashCode => date.hashCode + value.hashCode;

  factory MeasurementOut.fromJson(Map<String, dynamic> json) =>
      _$MeasurementOutFromJson(json);

  Map<String, dynamic> toJson() => _$MeasurementOutToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }
}
