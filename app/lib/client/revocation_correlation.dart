import 'dart:convert';
import 'dart:typed_data';

import 'package:endlessnet_client_api/client_api.dart' as api;

// UI correlation only. A resolved command is not evidence of stopped traffic.
final class RevocationCorrelation {
  RevocationCorrelation({
    required this.profileId,
    required this.controlOrigin,
    required this.commandId,
    required api.NodeRevocationTarget target,
    this.resolved = false,
  }) : _target = api.NodeRevocationTarget.fromBuffer(target.writeToBuffer());
  final String profileId, controlOrigin, commandId;
  final api.NodeRevocationTarget _target;
  final bool resolved;
  api.NodeRevocationTarget get target =>
      api.NodeRevocationTarget.fromBuffer(_target.writeToBuffer());
  RevocationCorrelation resolve() => RevocationCorrelation(
    profileId: profileId,
    controlOrigin: controlOrigin,
    commandId: commandId,
    target: _target,
    resolved: true,
  );
  bool same(RevocationCorrelation other) =>
      profileId == other.profileId &&
      controlOrigin == other.controlOrigin &&
      commandId == other.commandId &&
      base64Encode(_target.writeToBuffer()) ==
          base64Encode(other._target.writeToBuffer());
  void validate() {
    final origin = Uri.tryParse(controlOrigin);
    if (!RegExp(r'^[0-9a-f-]{36}$').hasMatch(profileId) ||
        !RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        ).hasMatch(commandId) ||
        origin == null ||
        origin.scheme != 'https' ||
        origin.origin != controlOrigin ||
        origin.userInfo.isNotEmpty ||
        origin.hasQuery ||
        origin.hasFragment ||
        _target.accountId.isEmpty ||
        _target.networkId.isEmpty ||
        _target.nodeId.isEmpty ||
        BigInt.parse(_target.networkRevision.toStringUnsigned()) <=
            BigInt.zero) {
      throw const FormatException('invalid revocation correlation');
    }
  }

  Uint8List encode() {
    validate();
    return Uint8List.fromList(
      utf8.encode(
        jsonEncode({
          'profile': profileId,
          'origin': controlOrigin,
          'command': commandId,
          'target': base64Encode(_target.writeToBuffer()),
          'resolved': resolved,
        }),
      ),
    );
  }

  static RevocationCorrelation decode(List<int> bytes) {
    final value = jsonDecode(utf8.decode(bytes));
    if (value is! Map<String, dynamic> ||
        value.length != 5 ||
        value['profile'] is! String ||
        value['origin'] is! String ||
        value['command'] is! String ||
        value['target'] is! String ||
        value['resolved'] is! bool) {
      throw const FormatException('invalid revocation record');
    }
    final c = RevocationCorrelation(
      profileId: value['profile'] as String,
      controlOrigin: value['origin'] as String,
      commandId: value['command'] as String,
      target: api.NodeRevocationTarget.fromBuffer(
        base64Decode(value['target'] as String),
      ),
      resolved: value['resolved'] as bool,
    );
    c.validate();
    return c;
  }
}

abstract interface class RevocationCorrelationStore {
  Future<RevocationCorrelation?> readRevocation(String profile, String origin);
  // Completes only after the same locked journal has flushed the immutable UUID/target.
  Future<void> saveRevocation(RevocationCorrelation value);
}
