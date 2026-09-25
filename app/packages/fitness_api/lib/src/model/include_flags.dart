//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:json_annotation/json_annotation.dart';

part 'include_flags.g.dart';

@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class IncludeFlags {
  /// Returns a new [IncludeFlags] instance.
  IncludeFlags({
    this.alcohol = true,

    this.events = true,

    this.exercises = true,

    this.health = true,

    this.matches = true,

    this.report = true,
  });

  @JsonKey(
    defaultValue: true,
    name: r'alcohol',
    required: false,
    includeIfNull: false,
  )
  final bool? alcohol;

  @JsonKey(
    defaultValue: true,
    name: r'events',
    required: false,
    includeIfNull: false,
  )
  final bool? events;

  @JsonKey(
    defaultValue: true,
    name: r'exercises',
    required: false,
    includeIfNull: false,
  )
  final bool? exercises;

  @JsonKey(
    defaultValue: true,
    name: r'health',
    required: false,
    includeIfNull: false,
  )
  final bool? health;

  @JsonKey(
    defaultValue: true,
    name: r'matches',
    required: false,
    includeIfNull: false,
  )
  final bool? matches;

  @JsonKey(
    defaultValue: true,
    name: r'report',
    required: false,
    includeIfNull: false,
  )
  final bool? report;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is IncludeFlags &&
          other.alcohol == alcohol &&
          other.events == events &&
          other.exercises == exercises &&
          other.health == health &&
          other.matches == matches &&
          other.report == report;

  @override
  int get hashCode =>
      alcohol.hashCode +
      events.hashCode +
      exercises.hashCode +
      health.hashCode +
      matches.hashCode +
      report.hashCode;

  factory IncludeFlags.fromJson(Map<String, dynamic> json) =>
      _$IncludeFlagsFromJson(json);

  Map<String, dynamic> toJson() => _$IncludeFlagsToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }
}
