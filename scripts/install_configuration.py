"""Build private installer inputs from producer defaults and one server origin."""
import argparse
import ipaddress
import json
from pathlib import Path
import re
from urllib.parse import urlsplit
import uuid


def configure(defaults, server, endpoint, sid, state_directory, output):
    url = urlsplit(server)
    if (url.scheme != "https" or not url.hostname or url.username or url.password
            or url.path not in ("", "/") or url.query or url.fragment
            or url.port not in (None, 443) or not re.fullmatch(r"[a-z0-9.-]+", url.hostname)):
        raise ValueError("Server must be an HTTPS origin")
    origin = "https://" + url.hostname
    if origin == "https://endlessnet.ru":
        origin = "https://api.endlessnet.ru"
    address, port = endpoint.rsplit(":", 1)
    ip = ipaddress.IPv4Address(address)
    if ip.is_unspecified or ip.is_loopback or ip.is_link_local or ip.is_multicast or not 1 <= int(port) <= 65535:
        raise ValueError("Expected local IPv4 endpoint")
    if not re.fullmatch(r"S-1-(?:[0-9]+-)*[0-9]+", sid):
        raise ValueError("Expected local Windows SID")
    settings = dict(defaults)
    if not settings or any(not isinstance(k, str) or not k.startswith("ENDLESSNET_CLIENT_") or not isinstance(v, str) for k, v in settings.items()):
        raise ValueError("Invalid producer defaults")
    if settings["ENDLESSNET_CLIENT_CONNECTION_LISTEN_PORT"] != port:
        raise ValueError("Endpoint must use the producer listen port")
    profile = str(uuid.uuid5(uuid.NAMESPACE_URL, origin))
    settings.update({
        "ENDLESSNET_CLIENT_CONTROL_ORIGIN": origin,
        "ENDLESSNET_CLIENT_APPROVAL_BASE": ("https://admin.endlessnet.ru/" if origin == "https://api.endlessnet.ru" else origin + "/"),
        "ENDLESSNET_CLIENT_DEFAULT_PROFILE_ID": profile,
        "ENDLESSNET_CLIENT_INSTALLATION_ID": str(uuid.uuid4()),
        "ENDLESSNET_CLIENT_STATE_DIRECTORY": state_directory,
        "ENDLESSNET_CLIENT_SERVICE_SID": "S-1-5-18",
        "ENDLESSNET_CLIENT_ALLOWED_SIDS": sid,
        "ENDLESSNET_CLIENT_CONNECTION_ENDPOINT": endpoint,
    })
    policy = {"schema": 1, "profile_id": profile, "control_origin": origin,
              "server_sid": "S-1-5-18", "connect_timeout_ms": 2000,
              "write_timeout_ms": 2000, "rpc_timeout_ms": 30000,
              "poll_interval_seconds": 2, "journal_max_bytes": 65536,
              "pending_write_max_bytes": 262144, "failure_max_bytes": 16384}
    output = Path(output)
    output.mkdir(parents=True, exist_ok=True)
    for name, value in [("service.json", settings), ("policy.json", policy)]:
        (output / name).write_text(json.dumps(value, ensure_ascii=False), encoding="utf-8")
    return settings, policy


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ["defaults", "server", "endpoint", "sid", "state-directory", "output"]:
        parser.add_argument("--" + name, required=True)
    args = parser.parse_args()
    configure(json.loads(Path(args.defaults).read_text(encoding="utf-8")), args.server,
              args.endpoint, args.sid, args.state_directory, args.output)


if __name__ == "__main__":
    main()
