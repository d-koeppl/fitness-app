//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:json_annotation/json_annotation.dart';

part 'push_device_in.g.dart';

@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class PushDeviceIn {
  /// Returns a new [PushDeviceIn] instance.
  PushDeviceIn({required this.platform, required this.token});

  @JsonKey(
    name: r'platform',
    required: true,
    includeIfNull: false,
    unknownEnumValue: PushDeviceInPlatformEnum.unknownDefaultOpenApi,
  )
  final PushDeviceInPlatformEnum platform;

  @JsonKey(name: r'token', required: true, includeIfNull: false)
  final String token;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PushDeviceIn &&
          other.platform == platform &&
          other.token == token;

  @override
  int get hashCode => platform.hashCode + token.hashCode;

  factory PushDeviceIn.fromJson(Map<String, dynamic> json) =>
      _$PushDeviceInFromJson(json);

  Map<String, dynamic> toJson() => _$PushDeviceInToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }
}

enum PushDeviceInPlatformEnum {
  @JsonValue(r'android')
  android(r'android'),
  @JsonValue(r'web')
  web(r'web'),
  @JsonValue(r'unknown_default_open_api')
  unknownDefaultOpenApi(r'unknown_default_open_api');

  const PushDeviceInPlatformEnum(this.value);

  final String value;

  @override
  String toString() => value;
}
