// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'skip_in.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

SkipIn _$SkipInFromJson(Map<String, dynamic> json) =>
    $checkedCreate('SkipIn', json, ($checkedConvert) {
      $checkKeys(json, requiredKeys: const ['ref_id', 'skipped', 'source']);
      final val = SkipIn(
        refId: $checkedConvert('ref_id', (v) => v as String),
        skipped: $checkedConvert('skipped', (v) => v as bool),
        source_: $checkedConvert(
          'source',
          (v) => $enumDecode(
            _$SkipInSource_EnumEnumMap,
            v,
            unknownValue: SkipInSource_Enum.unknownDefaultOpenApi,
          ),
        ),
      );
      return val;
    }, fieldKeyMap: const {'refId': 'ref_id', 'source_': 'source'});

Map<String, dynamic> _$SkipInToJson(SkipIn instance) => <String, dynamic>{
  'ref_id': instance.refId,
  'skipped': instance.skipped,
  'source': _$SkipInSource_EnumEnumMap[instance.source_]!,
};

const _$SkipInSource_EnumEnumMap = {
  SkipInSource_Enum.match: 'match',
  SkipInSource_Enum.training: 'training',
  SkipInSource_Enum.unknownDefaultOpenApi: 'unknown_default_open_api',
};
