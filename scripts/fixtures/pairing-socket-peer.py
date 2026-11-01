#!/usr/bin/env python3
"""Independent loopback TLS peer for the Swift transport effect witness."""
import hashlib
import json
from pathlib import Path
import socket
import ssl
import sys

root = Path(sys.argv[1])

def publish(name, text):
    temporary = root / (name + '.tmp')
    temporary.write_text(text, encoding='utf-8')
    temporary.replace(root / name)

context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
context.minimum_version = ssl.TLSVersion.TLSv1_3
context.load_cert_chain(root / 'cert.pem', root / 'key.pem')
receipt = {'acceptedSockets': 0, 'plaintextBytes': 0, 'tlsVersion': None}
with socket.socket() as listener:
    listener.bind(('127.0.0.1', 0))
    listener.listen(1)
    listener.settimeout(10)
    publish('port', str(listener.getsockname()[1]))
    try:
        raw, address = listener.accept()
        receipt['acceptedSockets'] += 1
        raw.settimeout(5)
        with context.wrap_socket(raw, server_side=True) as channel:
            receipt['tlsVersion'] = channel.version()
            data = bytearray()
            while len(data) < 4:
                part = channel.recv(4 - len(data))
                if not part:
                    break
                data.extend(part)
            if len(data) == 4:
                size = int.from_bytes(data, 'big')
                if size > 4096:
                    raise ValueError('oversized fixture frame')
                while len(data) < size + 4:
                    part = channel.recv(size + 4 - len(data))
                    if not part:
                        break
                    data.extend(part)
                receipt['plaintextBytes'] = len(data)
                receipt['frameSHA256'] = hashlib.sha256(data).hexdigest()
                channel.sendall(data)
    except (OSError, ValueError) as error:
        receipt['failureType'] = type(error).__name__
    finally:
        publish('receipt.json', json.dumps(receipt))
