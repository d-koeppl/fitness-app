//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:fitness_api/src/model/measurement_out.dart';
import 'package:json_annotation/json_annotation.dart';

part 'latest_measurements_out.g.dart';

@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class LatestMeasurementsOut {
  /// Returns a new [LatestMeasurementsOut] instance.
  LatestMeasurementsOut({this.vo2max, this.weightKg});

  @JsonKey(name: r'vo2max', required: false, includeIfNull: false)
  final MeasurementOut? vo2max;

  @JsonKey(name: r'weight_kg', required: false, includeIfNull: false)
  final MeasurementOut? weightKg;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LatestMeasurementsOut &&
          other.vo2max == vo2max &&
          other.weightKg == weightKg;

  @override
  int get hashCode => vo2max.hashCode + weightKg.hashCode;

  factory LatestMeasurementsOut.fromJson(Map<String, dynamic> json) =>
      _$LatestMeasurementsOutFromJson(json);

  Map<String, dynamic> toJson() => _$LatestMeasurementsOutToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }
}
