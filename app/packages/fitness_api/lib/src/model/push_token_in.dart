//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:json_annotation/json_annotation.dart';

part 'push_token_in.g.dart';

@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class PushTokenIn {
  /// Returns a new [PushTokenIn] instance.
  PushTokenIn({required this.token});

  @JsonKey(name: r'token', required: true, includeIfNull: false)
  final String token;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is PushTokenIn && other.token == token;

  @override
  int get hashCode => token.hashCode;

  factory PushTokenIn.fromJson(Map<String, dynamic> json) =>
      _$PushTokenInFromJson(json);

  Map<String, dynamic> toJson() => _$PushTokenInToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }
}
