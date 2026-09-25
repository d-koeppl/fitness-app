//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:json_annotation/json_annotation.dart';

part 'token_status_out.g.dart';

@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class TokenStatusOut {
  /// Returns a new [TokenStatusOut] instance.
  TokenStatusOut({
    this.accessTokenExpiresAt,

    required this.connected,

    this.scopes,

    this.updatedAt,
  });

  @JsonKey(
    name: r'access_token_expires_at',
    required: false,
    includeIfNull: false,
  )
  final DateTime? accessTokenExpiresAt;

  @JsonKey(name: r'connected', required: true, includeIfNull: false)
  final bool connected;

  @JsonKey(name: r'scopes', required: false, includeIfNull: false)
  final String? scopes;

  @JsonKey(name: r'updated_at', required: false, includeIfNull: false)
  final DateTime? updatedAt;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TokenStatusOut &&
          other.accessTokenExpiresAt == accessTokenExpiresAt &&
          other.connected == connected &&
          other.scopes == scopes &&
          other.updatedAt == updatedAt;

  @override
  int get hashCode =>
      accessTokenExpiresAt.hashCode +
      connected.hashCode +
      scopes.hashCode +
      updatedAt.hashCode;

  factory TokenStatusOut.fromJson(Map<String, dynamic> json) =>
      _$TokenStatusOutFromJson(json);

  Map<String, dynamic> toJson() => _$TokenStatusOutToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }
}
