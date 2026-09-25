// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'sync_out.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

SyncOut _$SyncOutFromJson(Map<String, dynamic> json) =>
    $checkedCreate('SyncOut', json, ($checkedConvert) {
      $checkKeys(json, requiredKeys: const ['sources']);
      final val = SyncOut(
        sources: $checkedConvert(
          'sources',
          (v) => Map<String, String>.from(v as Map),
        ),
      );
      return val;
    });

Map<String, dynamic> _$SyncOutToJson(SyncOut instance) => <String, dynamic>{
  'sources': instance.sources,
};
