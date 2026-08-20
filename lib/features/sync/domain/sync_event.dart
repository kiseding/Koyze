import 'dart:convert';

final class SyncEvent {
  const SyncEvent({
    required this.eventId,
    required this.localUserId,
    required this.deviceId,
    this.accountId,
    required this.eventType,
    required this.entityId,
    required this.payload,
    required this.createdAt,
  });

  final String eventId;
  final String localUserId;
  final String deviceId;
  final String? accountId;
  final String eventType;
  final String entityId;
  final Map<String, dynamic> payload;
  final DateTime createdAt;

  Map<String, dynamic> toJson() => {
    'eventId': eventId,
    'localUserId': localUserId,
    'deviceId': deviceId,
    if (accountId != null) 'accountId': accountId,
    'eventType': eventType,
    'entityId': entityId,
    'payload': payload,
    'createdAt': createdAt.toUtc().millisecondsSinceEpoch,
  };

  factory SyncEvent.fromJson(Map<String, dynamic> json) {
    final payload = json['payload'];
    if (payload is! Map) {
      throw const FormatException('event payload is invalid');
    }
    return SyncEvent(
      eventId: _required(json, 'eventId'),
      localUserId: _required(json, 'localUserId'),
      deviceId: _required(json, 'deviceId'),
      accountId: json['accountId']?.toString(),
      eventType: _required(json, 'eventType'),
      entityId: _required(json, 'entityId'),
      payload: Map<String, dynamic>.from(payload),
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        (json['createdAt'] as num?)?.toInt() ?? 0,
        isUtc: true,
      ),
    );
  }

  String encode() => jsonEncode(toJson());

  static String _required(Map<String, dynamic> json, String key) {
    final value = json[key]?.toString() ?? '';
    if (value.isEmpty) throw FormatException('event $key is required');
    return value;
  }
}
