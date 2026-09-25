// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'skip_out.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

SkipOut _$SkipOutFromJson(Map<String, dynamic> json) =>
    $checkedCreate('SkipOut', json, ($checkedConvert) {
      $checkKeys(json, requiredKeys: const ['ref_id', 'skipped', 'source']);
      final val = SkipOut(
        refId: $checkedConvert('ref_id', (v) => v as String),
        skipped: $checkedConvert('skipped', (v) => v as bool),
        source_: $checkedConvert('source', (v) => v as String),
      );
      return val;
    }, fieldKeyMap: const {'refId': 'ref_id', 'source_': 'source'});

Map<String, dynamic> _$SkipOutToJson(SkipOut instance) => <String, dynamic>{
  'ref_id': instance.refId,
  'skipped': instance.skipped,
  'source': instance.source_,
};
