//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:json_annotation/json_annotation.dart';

part 'drink_count_in.g.dart';

@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class DrinkCountIn {
  /// Returns a new [DrinkCountIn] instance.
  DrinkCountIn({required this.count});

  // minimum: 0
  // maximum: 99
  @JsonKey(name: r'count', required: true, includeIfNull: false)
  final int count;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is DrinkCountIn && other.count == count;

  @override
  int get hashCode => count.hashCode;

  factory DrinkCountIn.fromJson(Map<String, dynamic> json) =>
      _$DrinkCountInFromJson(json);

  Map<String, dynamic> toJson() => _$DrinkCountInToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }
}
