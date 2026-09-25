//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:json_annotation/json_annotation.dart';

part 'skip_in.g.dart';

@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class SkipIn {
  /// Returns a new [SkipIn] instance.
  SkipIn({required this.refId, required this.skipped, required this.source_});

  @JsonKey(name: r'ref_id', required: true, includeIfNull: false)
  final String refId;

  @JsonKey(name: r'skipped', required: true, includeIfNull: false)
  final bool skipped;

  @JsonKey(
    name: r'source',
    required: true,
    includeIfNull: false,
    unknownEnumValue: SkipInSource_Enum.unknownDefaultOpenApi,
  )
  final SkipInSource_Enum source_;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SkipIn &&
          other.refId == refId &&
          other.skipped == skipped &&
          other.source_ == source_;

  @override
  int get hashCode => refId.hashCode + skipped.hashCode + source_.hashCode;

  factory SkipIn.fromJson(Map<String, dynamic> json) => _$SkipInFromJson(json);

  Map<String, dynamic> toJson() => _$SkipInToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }
}

enum SkipInSource_Enum {
  @JsonValue(r'match')
  match(r'match'),
  @JsonValue(r'training')
  training(r'training'),
  @JsonValue(r'unknown_default_open_api')
  unknownDefaultOpenApi(r'unknown_default_open_api');

  const SkipInSource_Enum(this.value);

  final String value;

  @override
  String toString() => value;
}
