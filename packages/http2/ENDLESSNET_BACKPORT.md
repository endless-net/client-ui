# Local HTTP/2 correction (version unchanged)

Source: https://github.com/dart-lang/http/tree/http2-v2.3.1/pkgs/http2

The library, manifest, AUTHORS, LICENSE and upstream documentation are copied
from that tag. Only `lib/src/streams/stream_handler.dart` is changed: late HEADERS
on a canceled client stream reset that stream rather than killing the entire
connection. Based on upstream correction:
https://github.com/dart-lang/http/pull/1800
merge commit `d6dd5ec9a24e66b386cc38d52c6d4e8decb26902`.

Version stays 2.3.1; this is an explicitly modified local source, not a claim
that the published 2.3.1 contains the fix. No change is made in the global pub
cache. All three consumer roots override http2 to this directory.

Regression: `dart run tool/probe_late_headers.dart` in
`packages/local_client_rpc`, plus real producer-script jobs on three desktop
platforms. The probe must exit 0. Native mobile and runtime acceptance remain
separate. Preserve upstream copyright and license when modifying this copy.
