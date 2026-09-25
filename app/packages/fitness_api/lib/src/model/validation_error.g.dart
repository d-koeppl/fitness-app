// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'validation_error.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ValidationError _$ValidationErrorFromJson(Map<String, dynamic> json) =>
    $checkedCreate('ValidationError', json, ($checkedConvert) {
      $checkKeys(json, requiredKeys: const ['loc', 'msg', 'type']);
      final val = ValidationError(
        ctx: $checkedConvert('ctx', (v) => v),
        input: $checkedConvert('input', (v) => v),
        loc: $checkedConvert(
          'loc',
          (v) => (v as List<dynamic>).map((e) => e as Object).toList(),
        ),
        msg: $checkedConvert('msg', (v) => v as String),
        type: $checkedConvert('type', (v) => v as String),
      );
      return val;
    });

Map<String, dynamic> _$ValidationErrorToJson(ValidationError instance) =>
    <String, dynamic>{
      'ctx': ?instance.ctx,
      'input': ?instance.input,
      'loc': instance.loc,
      'msg': instance.msg,
      'type': instance.type,
    };
