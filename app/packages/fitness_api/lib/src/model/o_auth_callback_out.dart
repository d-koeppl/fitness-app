//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:json_annotation/json_annotation.dart';

part 'o_auth_callback_out.g.dart';

@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class OAuthCallbackOut {
  /// Returns a new [OAuthCallbackOut] instance.
  OAuthCallbackOut({
    required this.scopes,

    required this.status,

    required this.target,
  });

  @JsonKey(name: r'scopes', required: true, includeIfNull: false)
  final String scopes;

  @JsonKey(name: r'status', required: true, includeIfNull: false)
  final String status;

  @JsonKey(name: r'target', required: true, includeIfNull: false)
  final String target;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is OAuthCallbackOut &&
          other.scopes == scopes &&
          other.status == status &&
          other.target == target;

  @override
  int get hashCode => scopes.hashCode + status.hashCode + target.hashCode;

  factory OAuthCallbackOut.fromJson(Map<String, dynamic> json) =>
      _$OAuthCallbackOutFromJson(json);

  Map<String, dynamic> toJson() => _$OAuthCallbackOutToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }
}
