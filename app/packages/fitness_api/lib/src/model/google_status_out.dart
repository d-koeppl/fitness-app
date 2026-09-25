//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:fitness_api/src/model/token_status_out.dart';
import 'package:json_annotation/json_annotation.dart';

part 'google_status_out.g.dart';

@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class GoogleStatusOut {
  /// Returns a new [GoogleStatusOut] instance.
  GoogleStatusOut({required this.calendar, required this.health});

  @JsonKey(name: r'calendar', required: true, includeIfNull: false)
  final TokenStatusOut calendar;

  @JsonKey(name: r'health', required: true, includeIfNull: false)
  final TokenStatusOut health;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GoogleStatusOut &&
          other.calendar == calendar &&
          other.health == health;

  @override
  int get hashCode => calendar.hashCode + health.hashCode;

  factory GoogleStatusOut.fromJson(Map<String, dynamic> json) =>
      _$GoogleStatusOutFromJson(json);

  Map<String, dynamic> toJson() => _$GoogleStatusOutToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }
}
