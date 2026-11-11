import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

final class UpdateFailure implements Exception {
  const UpdateFailure();
}

final class ReleaseVersion implements Comparable<ReleaseVersion> {
  ReleaseVersion(String value) : text = value.replaceFirst(RegExp(r'^v'), '') {
    if (!RegExp(r'^0\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$').hasMatch(text)) {
      throw const UpdateFailure();
    }
    parts = text.split('.').map(int.parse).toList();
    if (parts[1] > 255 || parts[2] > 65535) throw const UpdateFailure();
  }
  final String text;
  late final List<int> parts;
  @override
  int compareTo(ReleaseVersion other) {
    for (var i = 0; i < parts.length; i++) {
      final result = parts[i].compareTo(other.parts[i]);
      if (result != 0) return result;
    }
    return 0;
  }
}

final class WindowsRelease {
  WindowsRelease(this.version, this.url, this.size, this.digest);
  final ReleaseVersion version;
  final Uri url;
  final int size;
  final String digest;

  static WindowsRelease decode(String body) {
    try {
      final data = jsonDecode(body) as Map<String, dynamic>;
      if (data['draft'] != false || data['prerelease'] != false) {
        throw const UpdateFailure();
      }
      final tag = data['tag_name'] as String;
      if (!tag.startsWith('v')) throw const UpdateFailure();
      final version = ReleaseVersion(tag);
      final name = 'EndlessNet-v${version.text}-windows-amd64.msi';
      final matches = (data['assets'] as List).where(
        (asset) => asset is Map && asset['name'] == name,
      );
      if (matches.length != 1) throw const UpdateFailure();
      final asset = matches.single as Map;
      final url = Uri.parse(asset['browser_download_url'] as String);
      final expected = Uri.https(
        'github.com',
        '/endless-net/client-ui/releases/download/$tag/$name',
      );
      final size = asset['size'];
      final digest = asset['digest'];
      if (url != expected ||
          asset['state'] != 'uploaded' ||
          size is! int ||
          size <= 0 ||
          size > 1024 * 1024 * 1024 ||
          digest is! String ||
          !RegExp(r'^sha256:[0-9a-f]{64}$').hasMatch(digest)) {
        throw const UpdateFailure();
      }
      return WindowsRelease(version, url, size, digest.substring(7));
    } catch (_) {
      throw const UpdateFailure();
    }
  }
}

abstract interface class ReleaseSource {
  Future<WindowsRelease> latest();
  Future<File> download(WindowsRelease release);
  void close();
}

// The same GitHub latest-release and bounded HTTPS approach as Serverdeck.
// Only standard GitHub metadata is used; no separate update catalog or keys.
final class GitHubReleases implements ReleaseSource {
  GitHubReleases({
    HttpClient Function()? clientFactory,
    this.metadataTimeout = const Duration(seconds: 30),
    this.downloadTimeout = const Duration(seconds: 60),
  }) : _clientFactory = clientFactory ?? HttpClient.new;
  final HttpClient Function() _clientFactory;
  final Duration metadataTimeout, downloadTimeout;
  final _clients = <HttpClient>{};
  bool _closed = false;
  static final endpoint = Uri.https(
    'api.github.com',
    '/repos/endless-net/client-ui/releases/latest',
  );
  static const hosts = {
    'github.com',
    'release-assets.githubusercontent.com',
    'objects.githubusercontent.com',
    'github-releases.githubusercontent.com',
  };

  Future<HttpClientResponse> _get(
    HttpClient client,
    Uri url, {
    bool api = false,
  }) async {
    for (var hops = 0; ; hops++) {
      if (url.scheme != 'https' ||
          url.userInfo.isNotEmpty ||
          url.port != 443 ||
          url.fragment.isNotEmpty ||
          (api ? url != endpoint : !hosts.contains(url.host))) {
        throw const UpdateFailure();
      }
      final request = await client.getUrl(url).timeout(metadataTimeout);
      request.followRedirects = false;
      request.headers.set(HttpHeaders.userAgentHeader, 'EndlessNet-Client-UI');
      if (api) {
        request.headers.set(
          HttpHeaders.acceptHeader,
          'application/vnd.github+json',
        );
      }
      final response = await request.close().timeout(metadataTimeout);
      if (response.statusCode == 200) return response;
      if (!api &&
          hops < 3 &&
          {301, 302, 303, 307, 308}.contains(response.statusCode)) {
        final location = response.headers.value(HttpHeaders.locationHeader);
        // Do not read an unbounded redirect/error body.
        await response.listen((_) {}).cancel();
        if (location == null) throw const UpdateFailure();
        url = url.resolve(location);
      } else {
        await response.listen((_) {}).cancel();
        throw const UpdateFailure();
      }
    }
  }

  Future<T> _operation<T>(
    Duration budget,
    Future<T> Function(HttpClient) action,
  ) async {
    if (_closed) throw const UpdateFailure();
    final client = _clientFactory()..connectionTimeout = metadataTimeout;
    _clients.add(client);
    var expired = false;
    final timer = Timer(budget, () {
      expired = true;
      client.close(force: true);
    });
    try {
      final value = await action(client);
      if (expired || _closed) throw const UpdateFailure();
      return value;
    } finally {
      timer.cancel();
      _clients.remove(client);
      client.close(force: true);
    }
  }

  @override
  Future<WindowsRelease> latest() =>
      _operation(metadataTimeout, (client) async {
        final response = await _get(client, endpoint, api: true);
        final bytes = <int>[];
        await for (final chunk in response.timeout(metadataTimeout)) {
          if (bytes.length + chunk.length > 512 * 1024) {
            throw const UpdateFailure();
          }
          bytes.addAll(chunk);
        }
        return WindowsRelease.decode(utf8.decode(bytes));
      });

  @override
  Future<File> download(WindowsRelease release) async {
    final directory = await Directory.systemTemp.createTemp(
      'endlessnet-update-',
    );
    final file = File('${directory.path}${Platform.pathSeparator}update.msi');
    try {
      await _operation(downloadTimeout, (client) async {
        final response = await _get(client, release.url);
        if (response.contentLength >= 0 &&
            response.contentLength != release.size) {
          throw const UpdateFailure();
        }
        final target = await file.open(mode: FileMode.write);
        var size = 0;
        try {
          await for (final chunk in response.timeout(downloadTimeout)) {
            size += chunk.length;
            if (size > release.size) throw const UpdateFailure();
            await target.writeFrom(chunk);
          }
          await target.flush();
        } finally {
          await target.close();
        }
        if (size != release.size ||
            (await sha256.bind(file.openRead()).first).toString() !=
                release.digest) {
          throw const UpdateFailure();
        }
      });
      return file;
    } catch (_) {
      await directory.delete(recursive: true);
      rethrow;
    }
  }

  @override
  void close() {
    _closed = true;
    for (final client in _clients) {
      client.close(force: true);
    }
  }
}
