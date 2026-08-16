#!/usr/bin/env python3
"""
The instrument for I5: a loopback TCP tap that records every connection made to it.

## Why this exists rather than an assertion over the source

I5 asks whether the phone-to-Mac pairing round trip happens. The tempting proof is a grep:
no `NWListener` in either app target, therefore no transport. That is an argument about the
source, and `spec-M6.md` already makes it. It is not a measurement of the running product,
and this fleet has recorded what happens when the two are confused.

So the round trip is attempted for real, and this is the thing that watches. It binds a port,
it writes down every connection that arrives, and the experiment's verdict is a count of the
lines in that file.

## The one property that makes silence mean anything

A tap that records nothing looks exactly like a tap that is broken. **So it is calibrated
before it is trusted**: the harness sends it a known token from a separate process and
asserts the token appears, and the phone process sends its own token from inside the
simulator before the pairing call is made. Only after both have landed does a subsequent
absence of traffic say something about the product rather than about this file, the port,
the sandbox or the simulator's network stack.

That ordering is the whole design. An uncalibrated tap turns "the transport does not exist"
and "I mistyped the port" into the same observation.

## The log format

One line per event, flushed immediately so the reader never races the writer:

    PORT <n>            once, at startup, before anything can connect
    CONNECT <n>         the nth connection, counted from 1
    DATA <n> <text>     what that connection sent, newlines escaped

The count is what the harness asserts on. Bytes are recorded so a connection that arrives
can be identified rather than merely counted — an unexpected third connection should be
attributable to something.
"""

import socket
import sys
import threading

# Bounded so a runaway sender cannot fill the disk of a machine running eight worktrees.
MAX_BYTES_PER_CONNECTION = 4096


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: i5-wire-tap.py <logfile>", file=sys.stderr)
        return 2

    log = open(sys.argv[1], "w", buffering=1)  # line-buffered: the reader must never race us
    counter = {"n": 0}
    lock = threading.Lock()

    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    # Loopback only, and an ephemeral port. Binding 0.0.0.0 on a laptop that lives on real
    # networks would put a listening socket in front of whoever else is on the Wi-Fi, to
    # measure something that only ever needed to be local.
    server.bind(("127.0.0.1", 0))
    server.listen(16)
    port = server.getsockname()[1]

    # Written before the first accept can happen, so a harness that has read a port knows the
    # listener is already up. A port printed after listen() would let the harness connect into
    # a race and read the refusal as evidence about the product.
    log.write(f"PORT {port}\n")
    print(port, flush=True)

    def serve(conn: socket.socket, index: int) -> None:
        try:
            conn.settimeout(5.0)
            chunks = []
            received = 0
            while received < MAX_BYTES_PER_CONNECTION:
                try:
                    chunk = conn.recv(1024)
                except (socket.timeout, OSError):
                    break
                if not chunk:
                    break
                chunks.append(chunk)
                received += len(chunk)
            text = b"".join(chunks).decode("utf-8", "replace").replace("\n", "\\n")
            with lock:
                log.write(f"DATA {index} {text}\n")
        finally:
            conn.close()

    while True:
        try:
            conn, _ = server.accept()
        except KeyboardInterrupt:
            return 0
        except OSError:
            return 0
        with lock:
            counter["n"] += 1
            index = counter["n"]
            # CONNECT is written at accept time rather than after the read, so a connection
            # that opens and sends nothing is still counted. A transport that connected and
            # then failed to send would otherwise be recorded as no transport at all, which is
            # a different finding.
            log.write(f"CONNECT {index}\n")
        threading.Thread(target=serve, args=(conn, index), daemon=True).start()


if __name__ == "__main__":
    sys.exit(main())
