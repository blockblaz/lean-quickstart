# Lean Consensus Devnet-1 retrospective

This note covers our findings from the Devnet-1 run in late December 2025 and the first half of January 2026, based on our observability stack and node logs.

> **Devnet-1 setup**: one node per client on 6 separate servers (Zeam, Ream, Qlean, Lantern, Lighthouse, Grandine - joined later).
>
> **Server configuration**: 8-core/16GB/150GB Debian 13.
>
> **Tooling**: Lean-quickstart (Ansible deploy).
>
> **Observability stack**: Prometheus, Grafana, Node Exporter.

## Summary & Key Achievements

The primary goals of Devnet-1 were successfully reached. All participating clients followed the specs and implemented a working [3SF-mini](https://github.com/ethereum/research/tree/master/3sf-mini) with 4-second slots. Using attestations signed by [XMSS signatures](https://github.com/leanEthereum/leanSpec/tree/main/src/lean_spec/subspecs/xmss), the network successfully reached finality.

PQ signature signing and verification remained stable throughout Devnet-1. Based on metrics from Zeam, Ream, Qlean, and Lantern, signing time ranged from 5–25ms, reaching up to 50ms. Verification took on average 5ms, with occasional spikes up to 10ms.

![PQ Signatures Performance](./images/devnet1-pq-signatures.png)

While the network reached finality and maintained liveness throughout the run, finalization remained unstable. Despite these issues, having a devnet running on 6 clients with achieved finality is a significant success. All teams were responsive, open to collaboration, and worked quickly to fix bugs and keep the network alive.

![Devnet-1 Summary Success](./images/devnet1-summary-success.png)

The troubleshooting details provided below are intended to help resolve the remaining issues as soon as possible and ensure a more stable Devnet-2.

## Troubleshooting

### Finalization issues

Finality in Devnet-1 was unstable and was often lost shortly after restarting the devnet: from several hours to several days. As the number of validators is preconfigured on the start, this made finality very fragile when clients went down.

These failures led us to investigate the issue in more detail, discussed in [Lean Ethereum PM #54](https://github.com/leanEthereum/pm/issues/54). Going back from 5-node to 4-node devnet and 3/4 clients simulation by disconnecting Zeam, discovered the threshold issue:

- In the 4-client devnet, losing 2 clients meant finality was impossible.

- In the 5-client devnet (after Lighthouse joined), having only 3 healthy nodes was still not enough for finalization.

Both cases are below the 2/3 threshold, so finalization stalled. 3/4 clients devnet went well.

![3/4 Clients Finalization](./images/devnet1-3-of-4-clients-finalization.png)

Finalization failures caused by lack of votes resulted from a combination of:

- Hash-sig/SSZ bugs
- Req/Resp mismatches
- Unstable peer connections
- Memory leaks forcing restarts.

### Hash Signature and SSZ Bugs

The transition from hash-sig to the LeanSig library introduced some implementation bugs. They led to missing votes which was the main reason of losing finality.

```bash
2025-12-26 21:33:48.872 ERROR [reqresp] status[3] failed to decode response bytes=40  peer=16Uiu2HA..
2025-12-26 21:33:48.872 WARN [reqresp] status request failed error=-7 (internal)  validator=lantern_0 peer=16Uiu2HA..
2025-12-26 21:33:48.909 ERROR [reqresp] status[2] failed to read response err=-3  peer=16Uiu2HA..
2025-12-26 21:33:48.909 WARN [reqresp] status request failed error=-3 (eof)  validator=lantern_0 peer=16Uiu2HA..
2025-12-26 21:33:51.646 ERROR [network] /leanconsensus/req/status/1/ssz_snappy decode request failed  peer=16Uiu2HA..
2025-12-26 21:33:51.651 INFO [reqresp] response legacy framing first_byte=0x28  peer=16Uiu2HA..
```

### Peer Connection Issues

Nodes had frequent problems maintaining peer connections. When a node lost peers it stopped receiving blocks, participating in consensus, its validator votes were missing. This directly affected finalization.

```bash
2025-12-26 21:37:28.896 ERROR [QUIC] handshake timeout state=client_init_sent(1) local_err=0 (unknown) remote_err=0 (unknown) initial_cid=5c37d95aae20017d local_cid=8de4d7ac0ae26009 remote_cid=- local_addr=- remote_addr=/ip4/46.224.135.169/udp/9001
2025-12-26 21:37:28.896 WARN [network] outgoing connection error code=-4 (timeout) msg=transport dial failed  validator=lantern_0
2025-12-26 21:37:28.905 ERROR [QUIC] handshake timeout state=client_init_sent(1) local_err=0 (unknown) remote_err=0 (unknown) initial_cid=a3401909d3340a26 local_cid=11d4127f8ca1fdb1 remote_cid=- local_addr=- remote_addr=/ip4/46.224.135.169/udp/9001
2025-12-26 21:37:28.905 WARN [network] outgoing connection error code=-4 (timeout) msg=transport dial failed  validator=lantern_0
2025-12-26 21:37:28.907 ERROR [QUIC] handshake timeout state=client_init_sent(1) local_err=0 (unknown) remote_err=0 (unknown) initial_cid=d5989c6e41daa0b1 local_cid=dc53f005caa6a167 remote_cid=- local_addr=- remote_addr=/ip4/46.224.135.169/udp/9001
2025-12-26 21:37:28.908 WARN [network] outgoing connection error code=-4 (timeout) msg=transport dial failed  validator=lantern_0
```

### Memory and storage issues

Observability tools caught several memory leaks on clients over time. They eventually led to process crashes and required to restart nodes. We also ran into a storage-full scenario that was identified through monitoring.

![Memory Issue](./images/devnet1-memory-issue.png)

![Storage Issue](./images/devnet1-storage-issue.png)

### Req/resp issues

Req/resp issues made it impossible for some nodes to fetch blocks from peers. They were related to some minor SSZ implementation bugs, switching from hash sig library to LeanSig and message format mismatches between the clients.

As a result nodes couldn't sync, responses were rejected, clients missed blocks, attestations or even disconnected.

```bash
# Lantern
2025-12-23 18:04:17.360 ERROR [reqresp] status[2] failed to read response err=-3  peer=16Uiu2HA..
2025-12-23 18:04:17.360 WARN [reqresp] status request failed error=-3 (eof)  validator=lantern_0 peer=16Uiu2HA..
2025-12-23 18:04:21.465 ERROR [network] /leanconsensus/req/status/1/ssz_snappy decode request failed  peer=16Uiu2HA..

# Zeam
Jan-02 15:07:22.454 [warning] (zeam): [network] network-0:: Received RPC error for request_id=3 protocol=/leanconsensus/req/lean_blocks_by_root/1/ssz_snappy code=3 from peer=16Uiu2HAmQj1RDNAxopeeeCFPRr3zhJYmH6DEPHYKmxLViLahWcFE(qlean_0)
Jan-02 15:07:22.455 [warning] (zeam): [node] blocks-by-root request to peer 16Uiu2HAmQj1RDNAxopeeeCFPRr3zhJYmH6DEPHYKmxLViLahWcFE(qlean_0) failed (3): Disconnected
Jan-02 15:07:22.455 [error] (zeam): [network] rust-bridge: [reqresp] Outbound error for request 3 with 16Uiu2HAmQj1RDNAxopeeeCFPRr3zhJYmH6DEPHYKmxLViLahWcFE: Disconnected
```

### Genesis/anchor block

When starting the devnet some clients log genesis block with zero target and source as in [generate_genesis()](https://github.com/leanEthereum/leanSpec/blob/main/src/lean_spec/subspecs/containers/state/state.py#L109):

```bash
============================================================
REAM's CHAIN STATUS: Next Slot: 1 | Head Slot: 0
------------------------------------------------------------
Connected Peers:   4
------------------------------------------------------------
Head Block Root:   0x761c884ad7ddebf6c383dbe7f3e54593660e0d57b537ea5cd389096aa22906f1
Parent Block Root: 0x0000000000000000000000000000000000000000000000000000000000000000
State Root:        0x070a952f38bb78e37c8771b19606a7f8fe71ab3567278eb9880c486315897f3d
------------------------------------------------------------
Latest Justified:  Slot 0 | Root: 0x0000000000000000000000000000000000000000000000000000000000000000
Latest Finalized:  Slot 0 | Root: 0x0000000000000000000000000000000000000000000000000000000000000000
============================================================
```

Others seem to start with the anchor block and apply the block hash to target and source as in [get_forkchoice_store()](https://github.com/leanEthereum/leanSpec/blob/main/src/lean_spec/subspecs/forkchoice/store.py#L220):

```bash
+===============================================================+
  CHAIN STATUS: Current Slot: 0 | Head Slot: 0 | Behind: 0
+---------------------------------------------------------------+
  Connected Peers:    0
+---------------------------------------------------------------+
  Head Block Root:    0x761c884ad7ddebf6c383dbe7f3e54593660e0d57b537ea5cd389096aa22906f1
  Parent Block Root:  0x0000000000000000000000000000000000000000000000000000000000000000
  State Root:         0x070a952f38bb78e37c8771b19606a7f8fe71ab3567278eb9880c486315897f3d
  Timely:             YES
+---------------------------------------------------------------+
  Latest Justified:   Slot      0 | Root: 0x761c884ad7ddebf6c383dbe7f3e54593660e0d57b537ea5cd389096aa22906f1
  Latest Finalized:   Slot      0 | Root: 0x761c884ad7ddebf6c383dbe7f3e54593660e0d57b537ea5cd389096aa22906f1
+===============================================================+
```

This potentially caused an `unknown target` and `unknown source` errors and led to rejecting the votes. Here is an example:

```bash
# Lighthouse published attestation with 0x0 finalized and justified roots

Dec 23 18:04:40.011 INFO  CHAIN STATUS | Slot 0 | Justified: 0 | Finalized: 0  current_slot: 0, head_slot: 0, justified_slot: 0, justified_root: 0x0000000000000000000000000000000000000000000000000000000000000000, finalized_slot: 0, finalized_root: 0x0000000000000000000000000000000000000000000000000000000000000000
Dec 23 18:04:40.011 INFO  Publishing attestation to network             slot: 0, validator_id: 4

# Lantern failed to validate this vote

2025-12-23 18:04:40.015 INFO [gossip] rejected vote validator=4 slot=0 head=0x6691eb3ea2573128e6d942555072d9e15b5d239de6656fbd28d8ce16404e3738 target=0x6691eb3ea2573128e6d942555072d9e15b5d239de6656fbd28d8ce16404e3738@0 source=0x0@0 reason=source checkpoint root zero slot=0 root=0x0  validator=lantern_0 peer=16Uiu2HA..
2025-12-23 18:04:40.054 INFO [gossip] published attestation validator=3 slot=0  validator=lantern_0
2025-12-23 18:04:40.057 INFO [gossip] processed vote validator=3 slot=0 head=0x6691eb3ea2573128e6d942555072d9e15b5d239de6656fbd28d8ce16404e3738 target=0x6691eb3ea2573128e6d942555072d9e15b5d239de6656fbd28d8ce16404e3738@0 source=0x6691eb3ea2573128e6d942555072d9e15b5d239de6656fbd28d8ce16404e3738@0  validator=lantern_0
```

All clients were informed about the above issues. Most of them are already fixed or actively being worked on.

### Unstable Node Syncing

In Devnet-1, disconnected clients could not rejoin without a full network restart. Consequently, teams began implementing syncing mechanisms. We tested several syncing scenarios across the 4- and 5-client devnets:

- **Node recovery**: Shutting down and spinning up a single client after 10–30 minutes.
- **Late join**: Starting with 3 of 4 clients and having the final client join after ~10 minutes.

While most clients successfully reached the head of the chain, we still lost finality during these tests. This was primarily caused by unstable peer connections, which led to a lack of sufficient votes for finalization.

![Head Sync](./images/devnet1-head-sync.png)

## Next steps for Devnet-2

### Checkpoint Sync Implementation

For Devnet-2, clients need to add or improve syncing functionality, specifically by implementing [checkpoint sync](https://github.com/leanEthereum/leanSpec/pull/279). This is critical for iterative testing and more realistic long-running network simulations. It will allow late joins and recovery after crashes without requiring a full network restart for every fix.

### Observability Improvements

Our goal for the next devnet is to significantly reduce debugging time by setting up a shared Grafana dashboard accessible to all clients and integrating Grafana Loki for better remote searchable logging.

### Upcoming Metrics

Metrics PRs planned or merged for Devnet-2 include:

- Connected peers — [#13](https://github.com/leanEthereum/leanMetrics/pull/13)
- Node info, reorgs — [#16](https://github.com/leanEthereum/leanMetrics/pull/16)
- PQ aggregated signatures — [#18](https://github.com/leanEthereum/leanMetrics/pull/18)

### Expected Clients Updates

Besides following the [pq-devnet-2: High Level Plan](https://github.com/leanEthereum/pm/blob/main/breakout-rooms/leanConsensus/pq-interop/pq-devnet-2.md), clients should:

- **Resolve:** peer connection issues, memory leaks, and SSZ/hash signature implementation bugs.
- **Optimize:** req/resp logic and message formatting.
- **Implement:** node syncing and checkpoint sync functionality.
- **Add**: [OCI standard labels](https://github.com/blockblaz/lean-quickstart/issues/91) (Git commit/branch) and [default Docker images](https://github.com/blockblaz/lean-quickstart/issues/94) for better version tracking and easier deployments.

### Lean Spec Proposals

- **Dynamic Validator Count:** Moving away from a strictly defined validator set to allow finality calculation based on currently active validators. This will prevent finality stalls when individual nodes are upgrading or restarting. See the PR [#256](https://github.com/leanEthereum/leanSpec/pull/256).

## Tooling Improvements

Hands-on time with `lean-quickstart` brought up a few ideas to discuss:

- **Support isolated devnet environments:** Enable running multiple devnets to test different scenarios or minor features on the same set of hardware, or even a single local machine. For example, a long-running devnet can coexist with short-lived secondary devnets on the same server set.
- **Improve configuration files:** Bring more flexibility into devnet parameters like client images, ports, flags, client set, and the number of validators. This is essential for enabling isolated devnet environments.
- **Add fork visualization:** Integrate fork visualization tools to provide better chain monitoring.
