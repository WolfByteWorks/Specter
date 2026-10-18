#!/usr/bin/env python3
"""Keeps Specter's Sparkle private key locked with the "Specter Sparkle" SSH key in Bitwarden.

The Sparkle key is stored only in encrypted form. To unlock it, the Bitwarden SSH agent signs a
fixed message with the Specter Sparkle key; Ed25519 signatures are deterministic, so that
signature is always the same and only that key can produce it. It becomes the encryption key.

  sparkle-key.py new <locked-file>      make a new Sparkle key, lock it, print its public key
  sparkle-key.py unlock <locked-file>   print the Sparkle private key (for --ed-key-file -)
  sparkle-key.py public <locked-file>   print the Sparkle public key (SUPublicEDKey)
"""
import base64, hashlib, hmac, os, socket, struct, sys

AGENT = os.path.expanduser("~/.bitwarden-ssh-agent.sock")
KEY_NAME = "Specter Sparkle"
CHALLENGE = b"Specter Sparkle key lock v1"
MAGIC = "SPECTER-SPARKLE-KEY-LOCKED-V1"


def fail(msg):
    sys.exit(f"sparkle-key: {msg}")


def _string(b):
    return struct.pack(">I", len(b)) + b


def _read(buf, i):
    n = struct.unpack(">I", buf[i:i + 4])[0]
    return buf[i + 4:i + 4 + n], i + 4 + n


def _call(sock, msg):
    sock.sendall(struct.pack(">I", len(msg)) + msg)
    head = b""
    while len(head) < 4:
        chunk = sock.recv(4 - len(head))
        if not chunk:
            fail("the Bitwarden SSH agent closed the connection")
        head += chunk
    n = struct.unpack(">I", head)[0]
    body = b""
    while len(body) < n:
        body += sock.recv(n - len(body))
    return body


def agent_secret():
    """32-byte secret: SHA-256 of the agent's Ed25519 signature over CHALLENGE."""
    try:
        sock = socket.socket(socket.AF_UNIX)
        sock.connect(AGENT)
    except OSError:
        fail("can't reach the Bitwarden SSH agent; open Bitwarden, unlock it, and turn on its SSH agent")
    reply = _call(sock, bytes([11]))  # list keys
    count, i, blob = struct.unpack(">I", reply[1:5])[0], 5, None
    for _ in range(count):
        key, i = _read(reply, i)
        comment, i = _read(reply, i)
        if comment.decode(errors="replace").strip() == KEY_NAME:
            blob = key
    if blob is None:
        fail(f'no "{KEY_NAME}" key in Bitwarden (unlock Bitwarden and check the key name)')
    reply = _call(sock, bytes([13]) + _string(blob) + _string(CHALLENGE) + struct.pack(">I", 0))
    if reply[0] != 14:
        fail("Bitwarden declined to sign")
    sig_blob, _ = _read(reply, 1)
    _, j = _read(sig_blob, 0)
    signature, _ = _read(sig_blob, j)
    return hashlib.sha256(signature).digest()


def _keystream(key, nonce, length):
    out, counter = b"", 0
    while len(out) < length:
        out += hashlib.sha256(key + nonce + struct.pack(">I", counter)).digest()
        counter += 1
    return out[:length]


def lock(plain, secret):
    enc, mac = hashlib.sha256(secret + b"enc").digest(), hashlib.sha256(secret + b"mac").digest()
    nonce = os.urandom(16)
    cipher = bytes(a ^ b for a, b in zip(plain, _keystream(enc, nonce, len(plain))))
    tag = hmac.new(mac, nonce + cipher, hashlib.sha256).digest()
    return f"{MAGIC}\n{base64.b64encode(nonce + cipher + tag).decode()}\n"


def unlock(text, secret):
    magic, _, payload = text.strip().partition("\n")
    if magic != MAGIC:
        fail("not a locked Specter Sparkle key file")
    raw = base64.b64decode(payload)
    nonce, cipher, tag = raw[:16], raw[16:-32], raw[-32:]
    enc, mac = hashlib.sha256(secret + b"enc").digest(), hashlib.sha256(secret + b"mac").digest()
    if not hmac.compare_digest(tag, hmac.new(mac, nonce + cipher, hashlib.sha256).digest()):
        fail('wrong key: this file was locked with a different "Specter Sparkle" key')
    return bytes(a ^ b for a, b in zip(cipher, _keystream(enc, nonce, len(cipher))))


# Ed25519 public key from a 32-byte seed (RFC 8032), to print SUPublicEDKey.
_P = 2**255 - 19
_D = -121665 * pow(121666, _P - 2, _P) % _P


def _add(p, q):
    (x1, y1), (x2, y2) = p, q
    t = _D * x1 * x2 * y1 * y2
    return ((x1 * y2 + x2 * y1) * pow(1 + t, _P - 2, _P) % _P,
            (y1 * y2 + x1 * x2) * pow(1 - t, _P - 2, _P) % _P)


def public_key(seed):
    h = hashlib.sha512(seed).digest()
    a = int.from_bytes(h[:32], "little")
    a = (a & ~7 & ((1 << 254) - 1)) | (1 << 254)
    by = 4 * pow(5, _P - 2, _P) % _P
    xx = (by * by - 1) * pow(_D * by * by + 1, _P - 2, _P)
    bx = pow(xx, (_P + 3) // 8, _P)
    if (bx * bx - xx) % _P:
        bx = bx * pow(2, (_P - 1) // 4, _P) % _P
    if bx % 2:
        bx = _P - bx
    point, result = (bx, by), (0, 1)
    while a:
        if a & 1:
            result = _add(result, point)
        point, a = _add(point, point), a >> 1
    x, y = result
    return base64.b64encode((y | ((x & 1) << 255)).to_bytes(32, "little")).decode()


def main():
    if len(sys.argv) != 3 or sys.argv[1] not in ("new", "unlock", "public"):
        sys.exit(__doc__)
    mode, path = sys.argv[1], sys.argv[2]
    secret = agent_secret()
    if mode == "new":
        if os.path.exists(path):
            fail(f"{path} already exists; not overwriting it")
        seed = os.urandom(32)
        with open(path, "w") as f:
            f.write(lock(base64.b64encode(seed), secret))
        print(public_key(seed))
        return
    seed_b64 = unlock(open(path).read(), secret)
    if mode == "unlock":
        sys.stdout.write(seed_b64.decode())
    else:
        print(public_key(base64.b64decode(seed_b64)))


if __name__ == "__main__":
    main()
