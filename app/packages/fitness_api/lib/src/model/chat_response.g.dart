// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'chat_response.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ChatResponse _$ChatResponseFromJson(Map<String, dynamic> json) =>
    $checkedCreate('ChatResponse', json, ($checkedConvert) {
      $checkKeys(
        json,
        requiredKeys: const ['conversation', 'message', 'reply', 'usage'],
      );
      final val = ChatResponse(
        conversation: $checkedConvert(
          'conversation',
          (v) => ConversationOut.fromJson(v as Map<String, dynamic>),
        ),
        message: $checkedConvert(
          'message',
          (v) => ChatMessageOut.fromJson(v as Map<String, dynamic>),
        ),
        reply: $checkedConvert(
          'reply',
          (v) => ChatMessageOut.fromJson(v as Map<String, dynamic>),
        ),
        usage: $checkedConvert(
          'usage',
          (v) => CoachUsageOut.fromJson(v as Map<String, dynamic>),
        ),
      );
      return val;
    });

Map<String, dynamic> _$ChatResponseToJson(ChatResponse instance) =>
    <String, dynamic>{
      'conversation': instance.conversation.toJson(),
      'message': instance.message.toJson(),
      'reply': instance.reply.toJson(),
      'usage': instance.usage.toJson(),
    };
