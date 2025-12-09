# Peering Issue: Ream Cannot Establish Bidirectional Connection with Zeam in Docker

## Summary

When running both `zeam` and `ream` nodes in Docker containers, `ream` fails to establish an outbound connection to `zeam`, resulting in a `HandshakeTimedOut` error. However, `zeam` successfully establishes an inbound connection to `ream`. This issue only occurs when both nodes are containerized; it works correctly when at least one node runs as a binary.

## Environment

- **Network**: Local devnet (`local-devnet`)
- **Nodes**: `zeam_0` (port 9000) and `ream_0` (port 9001)
- **Docker Images**: 
  - Zeam: `blockblaz/zeam:devnet1` (or `zeam:local`)
  - Ream: `ghcr.io/reamlabs/ream:latest`
- **Network Configuration**: Both nodes use `127.0.0.1` in their ENRs and listen on `0.0.0.0` for incoming connections
- **Command**: `NETWORK_DIR=local-devnet ./spin-node.sh --node zeam_0,ream_0 --generateGenesis --popupTerminal`

## Observed Behavior

### Successful Connection (Zeam → Ream)
- Zeam successfully initiates and completes a connection to ream
- Zeam logs show: `Peer connected: 16Uiu2HAmPQhkD6Zg5Co2ee8ShshkiY4tDePKFARPpCS2oKSLj1E1`
- Zeam sends a status request to ream

### Failed Connection (Ream → Zeam)
- Ream attempts to connect to zeam but times out during handshake
- Ream logs show: `Failed to connect to Some(PeerId("16Uiu2HAkvi2sxT75Bpq1c7yV2FjnSQJJ432d6jeshbmfdJss1i6f")): Transport([(/ip4/127.0.0.1/udp/9000/quic-v1/p2p/16Uiu2HAkvi2sxT75Bpq1c7yV2FjnSQJJ432d6jeshbmfdJss1i6f, Other(Custom { kind: Other, error: Other(Right(HandshakeTimedOut)) }))])`
- Ream also logs: `Incoming connection from /ip4/0.0.0.0/udp/9001/quic-v1` (from zeam)

### Connection Termination
- After the failed outbound connection attempt, zeam's status request to ream fails with error code 3 (Disconnected)
- The connection is closed: `Connection closed with peer: 16Uiu2HAmPQhkD6Zg5Co2ee8ShshkiY4tDePKFARPpCS2oKSLj1E1`

## Logs

### Ream Logs
```
2025-11-26T18:50:38.630473Z  INFO ream_p2p::network::lean: Dialing peer: PeerId("16Uiu2HAmQj1RDNAxopeeeCFPRr3zhJYmH6DEPHYKmxLViLahWcFE")

2025-11-26T18:50:39.191071Z  INFO ream_p2p::network::lean: Incoming connection from /ip4/0.0.0.0/udp/9001/quic-v1

2025-11-26T18:50:43.684059Z  WARN ream_p2p::network::lean: Failed to connect to Some(PeerId("16Uiu2HAkvi2sxT75Bpq1c7yV2FjnSQJJ432d6jeshbmfdJss1i6f")): Transport([(/ip4/127.0.0.1/udp/9000/quic-v1/p2p/16Uiu2HAkvi2sxT75Bpq1c7yV2FjnSQJJ432d6jeshbmfdJss1i6f, Other(Custom { kind: Other, error: Other(Right(HandshakeTimedOut)) }))])
```

### Zeam Logs
```
Nov-26 18:50:39.200 [info] (zeam): [network] network-0:: Peer connected: 16Uiu2HAmPQhkD6Zg5Co2ee8ShshkiY4tDePKFARPpCS2oKSLj1E1
Nov-26 18:50:39.200 [info] (zeam): [node] Peer connected: 16Uiu2HAmPQhkD6Zg5Co2ee8ShshkiY4tDePKFARPpCS2oKSLj1E1, total peers: 1
Nov-26 18:50:39.200 [info] (zeam): [network] rust-bridge: [reqresp] Sent StatusV1 request to 16Uiu2HAmPQhkD6Zg5Co2ee8ShshkiY4tDePKFARPpCS2oKSLj1E1 (id: 1)
...
Nov-26 18:50:44.198 [warning] (zeam): [network] network-0:: Received RPC error for request_id=1 protocol=/leanconsensus/req/status/1/ssz_snappy code=3
Nov-26 18:50:44.200 [warning] (zeam): [node] Status request to peer 16Uiu2HAmPQhkD6Zg5Co2ee8ShshkiY4tDePKFARPpCS2oKSLj1E1 failed (3): Disconnected
Nov-26 18:50:44.201 [info] (zeam): [network] rust-bridge: Connection closed with peer: 16Uiu2HAmPQhkD6Zg5Co2ee8ShshkiY4tDePKFARPpCS2oKSLj1E1
```

## Workarounds

The issue does **not** occur when:
- At least one node runs as a binary (not in Docker)
- Both nodes are run as binaries
- One node is in Docker and the other is a binary

## Additional Context

1. **Zeam-Zeam Peering Works**: Two zeam nodes can successfully peer with each other when both are run in Docker, suggesting the issue is specific to ream's outbound connection handling in Docker.

2. **ENR Configuration**: Both nodes have ENRs with `ip: "127.0.0.1"` in `validator-config.yaml`, and the generated `nodes.yaml` contains ENRs with `127.0.0.1`. Zeam listens on `0.0.0.0` but advertises `127.0.0.1` in its ENR.

3. **Docker Networking**: The containers are run with `--network host` mode (via `spin-node.sh`), so they should have direct access to `127.0.0.1`.

## Hypothesis

The issue appears to be related to how ream resolves or uses ENR addresses when running in Docker. Possible causes:
- ENR IP address resolution issue in Docker environment
- QUIC handshake timeout configuration when connecting from Docker container
- Network interface binding issue when ream initiates outbound connections from Docker

## Request

Could the ream team investigate:
1. How ream resolves ENR IP addresses when running in Docker?
2. Whether there are any Docker-specific networking configurations needed for outbound QUIC connections?
3. If the handshake timeout can be adjusted or if there's a known issue with QUIC handshakes from Docker containers?

## Test Configuration

Validator config used: [validator-config.yaml](https://github.com/blockblaz/lean-quickstart/blob/2a49a7622d033f228c732900d17c3feff582612f/local-devnet/genesis/validator-config.yaml)


