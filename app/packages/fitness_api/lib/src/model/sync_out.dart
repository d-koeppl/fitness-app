//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:json_annotation/json_annotation.dart';

part 'sync_out.g.dart';

@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class SyncOut {
  /// Returns a new [SyncOut] instance.
  SyncOut({required this.sources});

  @JsonKey(name: r'sources', required: true, includeIfNull: false)
  final Map<String, String> sources;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is SyncOut && other.sources == sources;

  @override
  int get hashCode => sources.hashCode;

  factory SyncOut.fromJson(Map<String, dynamic> json) =>
      _$SyncOutFromJson(json);

  Map<String, dynamic> toJson() => _$SyncOutToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }
}
