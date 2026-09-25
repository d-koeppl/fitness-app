//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:json_annotation/json_annotation.dart';

part 'drink_day_out.g.dart';

@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class DrinkDayOut {
  /// Returns a new [DrinkDayOut] instance.
  DrinkDayOut({
    required this.count,

    required this.date,

    required this.editable,

    required this.reported,
  });

  @JsonKey(name: r'count', required: true, includeIfNull: false)
  final int count;

  @JsonKey(name: r'date', required: true, includeIfNull: false)
  final DateTime date;

  @JsonKey(name: r'editable', required: true, includeIfNull: false)
  final bool editable;

  @JsonKey(name: r'reported', required: true, includeIfNull: false)
  final int reported;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DrinkDayOut &&
          other.count == count &&
          other.date == date &&
          other.editable == editable &&
          other.reported == reported;

  @override
  int get hashCode =>
      count.hashCode + date.hashCode + editable.hashCode + reported.hashCode;

  factory DrinkDayOut.fromJson(Map<String, dynamic> json) =>
      _$DrinkDayOutFromJson(json);

  Map<String, dynamic> toJson() => _$DrinkDayOutToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }
}
