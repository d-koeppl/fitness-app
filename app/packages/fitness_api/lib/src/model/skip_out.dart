//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:json_annotation/json_annotation.dart';

part 'skip_out.g.dart';

@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class SkipOut {
  /// Returns a new [SkipOut] instance.
  SkipOut({required this.refId, required this.skipped, required this.source_});

  @JsonKey(name: r'ref_id', required: true, includeIfNull: false)
  final String refId;

  @JsonKey(name: r'skipped', required: true, includeIfNull: false)
  final bool skipped;

  @JsonKey(name: r'source', required: true, includeIfNull: false)
  final String source_;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SkipOut &&
          other.refId == refId &&
          other.skipped == skipped &&
          other.source_ == source_;

  @override
  int get hashCode => refId.hashCode + skipped.hashCode + source_.hashCode;

  factory SkipOut.fromJson(Map<String, dynamic> json) =>
      _$SkipOutFromJson(json);

  Map<String, dynamic> toJson() => _$SkipOutToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }
}
