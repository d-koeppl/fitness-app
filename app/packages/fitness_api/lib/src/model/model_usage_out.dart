//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:json_annotation/json_annotation.dart';

part 'model_usage_out.g.dart';

@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class ModelUsageOut {
  /// Returns a new [ModelUsageOut] instance.
  ModelUsageOut({required this.limit, required this.model, required this.used});

  @JsonKey(name: r'limit', required: true, includeIfNull: false)
  final int limit;

  @JsonKey(name: r'model', required: true, includeIfNull: false)
  final String model;

  @JsonKey(name: r'used', required: true, includeIfNull: false)
  final int used;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ModelUsageOut &&
          other.limit == limit &&
          other.model == model &&
          other.used == used;

  @override
  int get hashCode => limit.hashCode + model.hashCode + used.hashCode;

  factory ModelUsageOut.fromJson(Map<String, dynamic> json) =>
      _$ModelUsageOutFromJson(json);

  Map<String, dynamic> toJson() => _$ModelUsageOutToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }
}
