//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:json_annotation/json_annotation.dart';

part 'push_device_out.g.dart';

@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class PushDeviceOut {
  /// Returns a new [PushDeviceOut] instance.
  PushDeviceOut({required this.platform, required this.registeredAt});

  @JsonKey(
    name: r'platform',
    required: true,
    includeIfNull: false,
    unknownEnumValue: PushDeviceOutPlatformEnum.unknownDefaultOpenApi,
  )
  final PushDeviceOutPlatformEnum platform;

  @JsonKey(name: r'registered_at', required: true, includeIfNull: false)
  final DateTime registeredAt;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PushDeviceOut &&
          other.platform == platform &&
          other.registeredAt == registeredAt;

  @override
  int get hashCode => platform.hashCode + registeredAt.hashCode;

  factory PushDeviceOut.fromJson(Map<String, dynamic> json) =>
      _$PushDeviceOutFromJson(json);

  Map<String, dynamic> toJson() => _$PushDeviceOutToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }
}

enum PushDeviceOutPlatformEnum {
  @JsonValue(r'android')
  android(r'android'),
  @JsonValue(r'web')
  web(r'web'),
  @JsonValue(r'unknown_default_open_api')
  unknownDefaultOpenApi(r'unknown_default_open_api');

  const PushDeviceOutPlatformEnum(this.value);

  final String value;

  @override
  String toString() => value;
}
