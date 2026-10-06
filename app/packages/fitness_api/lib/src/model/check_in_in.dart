//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:json_annotation/json_annotation.dart';

part 'check_in_in.g.dart';

@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class CheckInIn {
  /// Returns a new [CheckInIn] instance.
  CheckInIn({required this.feeling, this.note, required this.strength});

  @JsonKey(
    name: r'feeling',
    required: true,
    includeIfNull: false,
    unknownEnumValue: CheckInInFeelingEnum.unknownDefaultOpenApi,
  )
  final CheckInInFeelingEnum feeling;

  /// The user's own words, required for `other`.
  @JsonKey(name: r'note', required: false, includeIfNull: false)
  final String? note;

  /// How strong the feeling is, 1 (barely) to 5 (very strong).
  // minimum: 1
  // maximum: 5
  @JsonKey(name: r'strength', required: true, includeIfNull: false)
  final int strength;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CheckInIn &&
          other.feeling == feeling &&
          other.note == note &&
          other.strength == strength;

  @override
  int get hashCode => feeling.hashCode + note.hashCode + strength.hashCode;

  factory CheckInIn.fromJson(Map<String, dynamic> json) =>
      _$CheckInInFromJson(json);

  Map<String, dynamic> toJson() => _$CheckInInToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }
}

enum CheckInInFeelingEnum {
  @JsonValue(r'energised')
  energised(r'energised'),
  @JsonValue(r'good')
  good(r'good'),
  @JsonValue(r'okay')
  okay(r'okay'),
  @JsonValue(r'tired')
  tired(r'tired'),
  @JsonValue(r'stressed')
  stressed(r'stressed'),
  @JsonValue(r'sore')
  sore(r'sore'),
  @JsonValue(r'ill')
  ill(r'ill'),
  @JsonValue(r'cold')
  cold(r'cold'),
  @JsonValue(r'other')
  other(r'other'),
  @JsonValue(r'unknown_default_open_api')
  unknownDefaultOpenApi(r'unknown_default_open_api');

  const CheckInInFeelingEnum(this.value);

  final String value;

  @override
  String toString() => value;
}
