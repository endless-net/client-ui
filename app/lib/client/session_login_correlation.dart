import 'dart:convert';
import 'dart:typed_data';

// Только локальная корреляция UI. Proof, URL и credentials здесь не хранятся.
final class SessionLoginCorrelation {
  const SessionLoginCorrelation({
    required this.profileId,
    required this.controlOrigin,
    required this.nodeId,
    required this.requestId,
  });
  final String profileId, controlOrigin, nodeId, requestId;

  bool same(SessionLoginCorrelation other) =>
      profileId == other.profileId &&
      controlOrigin == other.controlOrigin &&
      nodeId == other.nodeId &&
      requestId == other.requestId;
  void validate() {
    final origin = Uri.tryParse(controlOrigin);
    if (profileId.isEmpty ||
        profileId.length > 256 ||
        nodeId.isEmpty ||
        nodeId.length > 256 ||
        !RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
        ).hasMatch(requestId) ||
        requestId == '00000000-0000-0000-0000-000000000000' ||
        origin == null ||
        origin.scheme != 'https' ||
        origin.origin != controlOrigin ||
        origin.userInfo.isNotEmpty ||
        origin.hasQuery ||
        origin.hasFragment) {
      throw const FormatException('invalid session login correlation');
    }
  }

  Uint8List encode() {
    validate();
    return Uint8List.fromList(
      utf8.encode(
        jsonEncode({
          'profile': profileId,
          'origin': controlOrigin,
          'node': nodeId,
          'request': requestId,
        }),
      ),
    );
  }

  static SessionLoginCorrelation decode(List<int> bytes) {
    final value = jsonDecode(utf8.decode(bytes));
    if (value is! Map<String, dynamic> ||
        value.length != 4 ||
        value.values.any((v) => v is! String) ||
        !value.keys.toSet().containsAll({
          'profile',
          'origin',
          'node',
          'request',
        })) {
      throw const FormatException('invalid session login record');
    }
    final result = SessionLoginCorrelation(
      profileId: value['profile'] as String,
      controlOrigin: value['origin'] as String,
      nodeId: value['node'] as String,
      requestId: value['request'] as String,
    );
    result.validate();
    return result;
  }
}

abstract interface class SessionLoginCorrelationStore {
  Future<SessionLoginCorrelation?> readSessionLogin(
    String profile,
    String origin,
  );
  // Завершение означает durable flush исходного UUID до первого Start.
  Future<void> saveSessionLogin(SessionLoginCorrelation value);
}
