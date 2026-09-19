"""Minimal RFC6455 WebSocket client (stdlib only) for the deterministic
Quasar control-plane legs of the universe proof chain.

Supports exactly what quasar.control.v1 needs: one text-frame
request/response round trip with a local server. No extensions, no
continuations, no compression (the server does not require them).
"""
import base64
import json
import os
import socket
import struct
import urllib.request


class WSError(Exception):
    pass


def http_get(url, timeout=10):
    with urllib.request.urlopen(url, timeout=timeout) as resp:
        return resp.status, resp.read().decode()


def session_token(index_url):
    """Extract the injected quasar-session-token meta tag
    from the CLOG boot page served at the site root."""
    _, html = http_get(index_url)
    marker = 'name="quasar-session-token" content="'
    i = html.find(marker)
    if i < 0:
        raise WSError(f"no session token in {index_url} "
                      "(frontend bundle missing?)")
    j = html.find('"', i + len(marker))
    return html[i + len(marker):j]


class WS:
    def __init__(self, host, port, resource, origin=None, timeout=15):
        self.sock = socket.create_connection((host, port), timeout=timeout)
        key = base64.b64encode(os.urandom(16)).decode()
        req = (f"GET {resource} HTTP/1.1\r\n"
               f"Host: {host}:{port}\r\n"
               "Upgrade: websocket\r\n"
               "Connection: Upgrade\r\n"
               f"Sec-WebSocket-Key: {key}\r\n"
               "Sec-WebSocket-Version: 13\r\n")
        if origin:
            req += f"Origin: {origin}\r\n"
        req += "\r\n"
        self.sock.sendall(req.encode())
        status = self._read_headers()
        if " 101 " not in status:
            raise WSError(f"websocket handshake refused: {status.strip()}")

    def _read_headers(self):
        buf = b""
        while b"\r\n\r\n" not in buf:
            chunk = self.sock.recv(4096)
            if not chunk:
                raise WSError("connection closed during handshake")
            buf += chunk
        head, _, rest = buf.partition(b"\r\n\r\n")
        self._buffer = rest
        return head.decode(errors="replace")

    def send_text(self, text):
        payload = text.encode()
        mask = os.urandom(4)
        header = bytearray([0x81])  # FIN + text
        n = len(payload)
        if n < 126:
            header.append(0x80 | n)
        elif n < 65536:
            header.append(0x80 | 126)
            header += struct.pack(">H", n)
        else:
            header.append(0x80 | 127)
            header += struct.pack(">Q", n)
        header += mask
        masked = bytes(b ^ mask[i % 4] for i, b in enumerate(payload))
        self.sock.sendall(bytes(header) + masked)

    def _read_exact(self, n):
        while len(self._buffer) < n:
            chunk = self.sock.recv(65536)
            if not chunk:
                raise WSError("connection closed mid-frame")
            self._buffer += chunk
        out, self._buffer = self._buffer[:n], self._buffer[n:]
        return out

    def recv_text(self):
        while True:
            b1, b2 = self._read_exact(2)
            opcode = b1 & 0x0F
            length = b2 & 0x7F
            masked = bool(b2 & 0x80)
            if length == 126:
                (length,) = struct.unpack(">H", self._read_exact(2))
            elif length == 127:
                (length,) = struct.unpack(">Q", self._read_exact(8))
            if masked:  # server frames must not be, but be safe
                mask = self._read_exact(4)
                length -= 0
            data = self._read_exact(length)
            if masked:
                data = bytes(b ^ mask[i % 4] for i, b in enumerate(data))
            if opcode == 0x1:
                return data.decode()
            if opcode == 0x8:
                raise WSError("server sent close frame")
            # ping/pong/binary: ignore and keep reading

    def command(self, envelope):
        """Send one quasar.control.v1 command; return the matching reply
        envelope (status ok/error)."""
        self.send_text(json.dumps(envelope))
        while True:
            reply = json.loads(self.recv_text())
            if reply.get("id") == envelope.get("id"):
                return reply
            # transaction child events: skip until the reply arrives

    def close(self):
        try:
            self.sock.close()
        except OSError:
            pass


def envelope(command, payload=None, metadata=None, _id=None):
    return {
        "protocol": "quasar.control.v1",
        "id": _id or f"universe-{os.urandom(4).hex()}",
        "command": command,
        "payload": payload or {},
        "metadata": metadata or {"client": "starintel-universe",
                                 "workspace": "default"},
    }
