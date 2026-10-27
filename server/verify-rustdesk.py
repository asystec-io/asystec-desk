"""Exercise a RustDesk OSS server from outside its network, using stdlib only.

Wire format: rustdesk/hbb_common commit
83419b6549636ee39dacef7776c473f5802e08d6, rendezvous.proto + bytes_codec.rs.
Creates only a transient heartbeat and relay pair; does not register a device key.
"""
import argparse
import datetime
import json
import secrets
import socket
import time
import uuid


def varint(value):
    result = bytearray()
    while value > 127:
        result.append((value & 127) | 128)
        value >>= 7
    result.append(value)
    return bytes(result)


def field(number, value):
    if isinstance(value, str):
        value = value.encode()
    return varint((number << 3) | 2) + varint(len(value)) + value


def frame(payload):
    size = len(payload)
    width = next(n for n in range(1, 5) if size < 1 << (8 * n - 2))
    return ((size << 2) | (width - 1)).to_bytes(width, "little") + payload


def receive_exact(stream, count):
    result = bytearray()
    while len(result) < count:
        chunk = stream.recv(count - len(result))
        if not chunk:
            raise ConnectionError("Unexpected EOF")
        result.extend(chunk)
    return bytes(result)


def receive_frame(stream):
    first = receive_exact(stream, 1)
    width = (first[0] & 3) + 1
    header = first + receive_exact(stream, width - 1)
    return receive_exact(stream, int.from_bytes(header, "little") >> 2)


def connect(host, port):
    return socket.create_connection((host, port), timeout=8)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", default="184.197.59.221")
    parser.add_argument("--key", default="6o6MWnTv2Vh6l+1oCrfEnlUSNQmMXaaLpqctaNcCulg=")
    args = parser.parse_args()
    checks = {}

    for port in (21115, 21116, 21117):
        with connect(args.host, port):
            checks[f"tcp_{port}"] = "PASS"

    # TestNatRequest -> TestNatResponse.
    for port in (21115, 21116):
        with connect(args.host, port) as stream:
            stream.sendall(frame(field(20, b"")))
            response = receive_frame(stream)
            if not response.startswith(varint((21 << 3) | 2)):
                raise RuntimeError(f"Unexpected NAT response on {port}: {response.hex()}")
            checks[f"nat_protocol_{port}"] = "PASS"

    # UDP heartbeat -> request to register the public key. Stop before registration.
    peer_id = str(secrets.randbelow(1_000_000_000) + 8_000_000_000)
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as udp:
        udp.settimeout(8)
        udp.sendto(field(6, field(1, peer_id)), (args.host, 21116))
        response, sender = udp.recvfrom(4096)
        if sender[0] != args.host or not response.startswith(b"\x3a"):
            raise RuntimeError(f"Unexpected UDP registration response: {response.hex()}")
        checks["udp_21116_registration_response"] = "PASS"

    # Both relay clients must send the configured key. Verify actual bidirectional data.
    pair_id = str(uuid.uuid4())
    request = frame(field(18, field(1, peer_id) + field(2, pair_id) + field(6, args.key)))
    with connect(args.host, 21117) as left, connect(args.host, 21117) as right:
        left.sendall(request)
        time.sleep(0.25)
        right.sendall(request)
        time.sleep(0.25)
        outbound = b"rustdesk-relay-check-a-" + secrets.token_bytes(32)
        left.sendall(outbound)
        if receive_exact(right, len(outbound)) != outbound:
            raise RuntimeError("Relay A -> B data mismatch")
        inbound = b"rustdesk-relay-check-b-" + secrets.token_bytes(32)
        right.sendall(inbound)
        if receive_exact(left, len(inbound)) != inbound:
            raise RuntimeError("Relay B -> A data mismatch")
        checks["relay_bidirectional_payload"] = "PASS"

    with connect(args.host, 21117) as unauthenticated:
        unauthenticated.sendall(frame(field(18, field(2, str(uuid.uuid4())))))
        if unauthenticated.recv(1) != b"":
            raise RuntimeError("Relay did not reject a missing key")
        checks["relay_rejects_missing_key"] = "PASS"

    print(json.dumps({
        "checked_at_utc": datetime.datetime.now(datetime.timezone.utc).isoformat(),
        "host": args.host,
        "checks": checks,
        "scope": "External protocol and relay checks; no desktop session attempted."
    }, indent=2))


if __name__ == "__main__":
    main()
