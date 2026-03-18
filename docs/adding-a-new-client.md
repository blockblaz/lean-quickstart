# Adding a New Client to lean-quickstart

This guide walks through every file you need to create or modify to integrate a new Lean
Ethereum client into lean-quickstart. The integration has **6 touch points**. All other
infrastructure (genesis generation, key management, Ansible inventory, subnet expansion,
leanpoint upstreams, aggregator selection) is generic and requires no changes.

---

## Naming convention

Every client follows the pattern `{client}_{index}`:

- `myclient_0` — first (and usually only) node for `myclient`
- `myclient_1`, `myclient_2` — additional nodes when `--subnets N` is used

The prefix before the first `_` is the **client type**. lean-quickstart derives it
automatically (`node_name.split('_')[0]`). All file and role names must use this prefix
consistently.

---

## Touch point 1 — `validator-config.yaml`

You must add your entry to **both** config files. They serve different purposes and are kept
intentionally separate:

| File | Purpose |
|---|---|
| `local-devnet/genesis/validator-config.yaml` | Local development on your own machine |
| `ansible-devnet/genesis/validator-config.yaml` | Remote deployment to production servers |

### Local devnet entry

For local use all nodes run on the same machine, so every node gets `127.0.0.1` and a unique
port.

```yaml
# local-devnet/genesis/validator-config.yaml
validators:
  # ... existing entries ...

  - name: "myclient_0"
    # A unique 32-byte hex P2P identity key.
    # Generate one: python3 -c "import secrets; print(secrets.token_hex(32))"
    privkey: "a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2"
    enrFields:
      ip: "127.0.0.1"
      quic: 9009             # Must be unique among all local nodes
    metricsPort: 9104        # Must be unique among all local nodes
    apiPort: 5064            # Must be unique among all local nodes
    isAggregator: false      # Managed automatically by spin-node.sh — do not set manually
    count: 1                 # Number of validator indices to assign to this node
```

### Ansible devnet entry

For remote deployment each node gets the IP of the server it will run on. Ports must be
unique per server (not globally, since nodes on different servers don't share a network
namespace).

```yaml
# ansible-devnet/genesis/validator-config.yaml
validators:
  # ... existing entries ...

  - name: "myclient_0"
    privkey: "a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2"
    enrFields:
      ip: "203.0.113.42"     # Public IP of the server this node will run on
      quic: 9001             # Can reuse port 9001 if no other node is on this server
    metricsPort: 9095
    apiPort: 5055
    isAggregator: false
    count: 1
```

> **Note — server assignment:** The `enrFields.ip` field is currently how lean-quickstart
> ties a node to a specific server. The Ansible inventory is generated from this IP, and
> `--prepare` opens firewall ports by matching this IP against each host. This coupling of
> server IP to node name is expected to be decoupled in a future release.

### Ports and `--subnets N`

When `--subnets N` is used, `generate-subnet-config.py` generates `myclient_0` … `myclient_{N-1}`
from your single template entry, incrementing every port by the subnet index:

| Subnet | Node | quic | metricsPort | apiPort |
|---|---|---|---|---|
| 0 | `myclient_0` | base | base | base |
| 1 | `myclient_1` | base+1 | base+1 | base+1 |
| … | … | … | … | … |

Your base ports therefore only need to be unique among subnet-0 entries. The generated nodes
`myclient_1` … `myclient_{N-1}` also receive fresh P2P keys automatically — you do not need
to provide them.

> **`apiPort` vs `httpPort`**: use `apiPort` if your client serves its REST API under that
> config key. If your client uses `httpPort` (as Lantern does), use `httpPort` instead — both
> are understood everywhere in lean-quickstart.

---

## Touch point 2 — `client-cmds/myclient-cmd.sh`

This file defines how lean-quickstart starts your client. It must set exactly two variables:

- **`node_binary`** — command line for running the client as a local binary
- **`node_docker`** — docker arguments (everything after `docker run … -v … -v …`) for
  running the client as a container
- **`node_setup`** — either `"docker"` or `"binary"` to select which of the above is used

The following shell variables are available when this script is sourced:

| Variable | Content |
|---|---|
| `$item` | Node name (e.g. `myclient_0`) — use as `--node-id` |
| `$configDir` | Absolute path to the genesis directory (e.g. `local-devnet/genesis`) — mounted as `/config` in Docker |
| `$dataDir` | Absolute path to the data root — mounted as `/data` in Docker |
| `$quicPort` | QUIC/P2P UDP port read from `validator-config.yaml` |
| `$metricsPort` | Prometheus metrics TCP port |
| `$apiPort` | REST API TCP port (`httpPort` is also available if you used that key) |
| `$privKeyPath` | Relative path to the P2P key file inside `$configDir` (e.g. `myclient_0.key`) |
| `$validatorConfig` | Either `"genesis_bootnode"` or a path to a node-specific `validator-config.yaml` |
| `$isAggregator` | `"true"` or `"false"` — set by aggregator selection before startup |
| `$attestationCommitteeCount` | Number of subnets (set when `--subnets N` is used) |
| `$checkpoint_sync_url` | Checkpoint sync URL (set when `--restart-client` is used) |
| `$scriptDir` | Directory of `spin-node.sh` (the lean-quickstart root) |

```bash
#!/bin/bash

#-----------------------myclient setup----------------------

# Build optional flags from environment variables injected by spin-node.sh.
aggregator_flag=""
if [ "$isAggregator" == "true" ]; then
    aggregator_flag="--aggregator"
fi

attestation_committee_flag=""
if [ -n "$attestationCommitteeCount" ]; then
    attestation_committee_flag="--attestation-committee-count $attestationCommitteeCount"
fi

checkpoint_sync_flag=""
if [ -n "${checkpoint_sync_url:-}" ]; then
    checkpoint_sync_flag="--checkpoint-sync-url $checkpoint_sync_url"
fi

# Binary mode: path relative to the lean-quickstart root.
node_binary="$scriptDir/../myclient/target/release/myclient \
      --data-dir $dataDir/$item \
      --genesis $configDir/config.yaml \
      --validators $configDir/validators.yaml \
      --bootnodes $configDir/nodes.yaml \
      --node-id $item \
      --node-key $configDir/$privKeyPath \
      --listen-port $quicPort \
      --metrics-port $metricsPort \
      --api-port $apiPort \
      $attestation_committee_flag \
      $aggregator_flag \
      $checkpoint_sync_flag"

# Docker mode: everything after 'docker run <run-options> -v ... -v ...'.
# The genesis dir is always at /config and data dir at /data inside the container.
node_docker="ghcr.io/yourorg/myclient:latest \
      --data-dir /data \
      --genesis /config/config.yaml \
      --validators /config/validators.yaml \
      --bootnodes /config/nodes.yaml \
      --node-id $item \
      --node-key /config/$privKeyPath \
      --listen-port $quicPort \
      --metrics-port $metricsPort \
      --api-port $apiPort \
      $attestation_committee_flag \
      $aggregator_flag \
      $checkpoint_sync_flag"

# Set to "binary" to use the binary path during development.
node_setup="docker"
```

### Required CLI flags your client must support

| Flag | Purpose |
|---|---|
| `--node-id <name>` | Identifies the node in logs and config lookups |
| `--node-key <path>` | Path to the P2P libp2p private key file |
| `--genesis` / `--custom_genesis` / `--network` | Path to `config.yaml` (or directory containing it) |
| `--validators` / `--validator-registry-path` | Path to `validators.yaml` (index assignments) |
| `--bootnodes` | Path to `nodes.yaml` (ENRs for peer discovery) |
| `--metrics-port <port>` | Prometheus metrics endpoint |
| `--api-port <port>` (or `--http-port`) | REST API endpoint (used by leanpoint health checks) |
| `--is-aggregator` / `--aggregator` | Enable aggregator mode for this node |
| `--attestation-committee-count <N>` | Number of subnets; controls which attestation gossip topics the node subscribes to |
| `--checkpoint-sync-url <url>` | URL to fetch finalized checkpoint state from |

> **`GET /v0/health`** — your client's REST API must respond to this endpoint. leanpoint
> uses it to monitor node health. Return HTTP 200 when the node is healthy.

### Files provided in the genesis directory

Your client will find these files at `$configDir` (or `/config` in Docker):

| File | Contents |
|---|---|
| `config.yaml` | Chain config — genesis time, ACTIVE\_EPOCH, VALIDATOR\_COUNT, GENESIS\_VALIDATORS pubkeys |
| `validators.yaml` | Validator index → node name assignments |
| `annotated_validators.yaml` | Validator index + pubkey\_hex + privkey\_file per node name (preferred over validators.yaml) |
| `nodes.yaml` | ENR list for all nodes — use as static bootnode list |
| `genesis.json` | Genesis state (JSON) |
| `genesis.ssz` | Genesis state (SSZ) |
| `hash-sig-keys/validator_N_sk.ssz` | Post-quantum secret key for validator N |
| `hash-sig-keys/validator_N_pk.ssz` | Post-quantum public key for validator N |
| `myclient_0.key` | P2P libp2p private key for this node |

> Clients should derive their genesis state from `config.yaml` directly (using
> `GENESIS_VALIDATORS` pubkeys and `GENESIS_TIME`). The `genesis.json` / `genesis.ssz`
> files are provided for compatibility but their format may not be up to date.

---

## Touch point 3 — Ansible role: `ansible/roles/myclient/defaults/main.yml`

```yaml
---
# Default variables for myclient role.
# Actual values are extracted from client-cmds/myclient-cmd.sh at deploy time.

myclient_docker_image: "ghcr.io/yourorg/myclient:latest"
myclient_binary_path: "{{ playbook_dir }}/../myclient/target/release/myclient"
deployment_mode: docker   # docker or binary
```

---

## Touch point 4 — Ansible role: `ansible/roles/myclient/tasks/main.yml`

This is the most substantial file. Copy the pattern from an existing role (e.g. `ream`) and
adjust the variable names and docker command arguments to match your client.

```yaml
---
# myclient role: Deploy and manage myclient nodes

- name: Extract docker image from client-cmd.sh
  shell: |
    project_root="$(cd '{{ playbook_dir }}/../..' && pwd)"
    grep -E '^node_docker=' "$project_root/client-cmds/myclient-cmd.sh" | head -1 \
      | grep -oE '[a-zA-Z0-9._/-]+:[a-zA-Z0-9._-]+' | head -1
  register: myclient_docker_image_raw
  changed_when: false
  delegate_to: localhost
  run_once: true

- name: Extract deployment mode from client-cmd.sh
  shell: |
    project_root="$(cd '{{ playbook_dir }}/../..' && pwd)"
    grep -E '^node_setup=' "$project_root/client-cmds/myclient-cmd.sh" | head -1 \
      | sed -E 's/.*node_setup="([^"]+)".*/\1/'
  register: myclient_deployment_mode_raw
  changed_when: false
  delegate_to: localhost
  run_once: true

- name: Set docker image and deployment mode
  set_fact:
    myclient_docker_image: "{{ myclient_docker_image_raw.stdout | trim | default('ghcr.io/yourorg/myclient:latest') }}"
    deployment_mode: "{{ myclient_deployment_mode_raw.stdout | trim | default('docker') }}"
  delegate_to: localhost
  run_once: true

- name: Extract node configuration from validator-config.yaml
  shell: |
    yq eval ".validators[] | select(.name == \"{{ node_name }}\") | .{{ item }}" \
      "{{ hostvars['localhost']['local_genesis_dir_path'] }}/validator-config.yaml"
  register: myclient_node_config
  changed_when: false
  delegate_to: localhost
  loop:
    - enrFields.quic
    - metricsPort
    - apiPort        # change to httpPort if your config uses that key
    - privkey
    - isAggregator
  when: node_name is defined

- name: Set node ports and aggregator flag
  set_fact:
    myclient_quic_port:      "{{ myclient_node_config.results[0].stdout }}"
    myclient_metrics_port:   "{{ myclient_node_config.results[1].stdout }}"
    myclient_api_port:       "{{ myclient_node_config.results[2].stdout }}"
    myclient_is_aggregator:  "{{ 'true' if (myclient_node_config.results[4].stdout | default('') | trim) == 'true' else 'false' }}"
  when: myclient_node_config is defined

- name: Ensure node key file exists
  stat:
    path: "{{ genesis_dir }}/{{ node_name }}.key"
  register: node_key_stat

- name: Fail if node key file is missing
  fail:
    msg: "Node key file {{ node_name }}.key not found in {{ genesis_dir }}"
  when: not (node_key_stat.stat.exists | default(false))

- name: Create node data directory
  file:
    path: "{{ data_dir }}/{{ node_name }}"
    state: directory
    mode: '0755'

- name: Deploy myclient node using Docker
  block:
    - name: Stop existing container (if any)
      command: docker rm -f {{ node_name }}
      register: myclient_stop
      failed_when: false
      changed_when: myclient_stop.rc == 0

    - name: Start myclient container
      command: >-
        docker run -d
        --pull=always
        --name {{ node_name }}
        --restart unless-stopped
        --network host
        {{ '--init --ulimit core=-1 --workdir /data'
           if (enable_core_dumps | default('') == 'all')
           or (node_name in (enable_core_dumps | default('')).split(','))
           or (node_name.split('_')[0] in (enable_core_dumps | default('')).split(','))
           else '' }}
        -v {{ genesis_dir }}:/config:ro
        -v {{ data_dir }}/{{ node_name }}:/data
        {{ myclient_docker_image }}
        --data-dir /data
        --genesis /config/config.yaml
        --validators /config/validators.yaml
        --bootnodes /config/nodes.yaml
        --node-id {{ node_name }}
        --node-key /config/{{ node_name }}.key
        --listen-port {{ myclient_quic_port }}
        --metrics-port {{ myclient_metrics_port }}
        --api-port {{ myclient_api_port }}
        {{ '--aggregator' if (myclient_is_aggregator | default('false')) == 'true' else '' }}
        {{ ('--checkpoint-sync-url ' + checkpoint_sync_url)
           if (checkpoint_sync_url is defined and checkpoint_sync_url | length > 0)
           else '' }}
      register: myclient_container
      changed_when: myclient_container.rc == 0
  when: deployment_mode == 'docker'
```

> **Core dumps** — the `enable_core_dumps` logic is boilerplate. Keep it as-is; it allows
> the operator to enable core dumps for specific nodes or client types at deploy time without
> changing the role.

---

## Touch point 5 — Register in `ansible/playbooks/helpers/deploy-single-node.yml`

Add a block for your client type. The client type is the prefix before the first `_` in the
node name (`myclient_0` → `myclient`).

```yaml
# ... existing entries for zeam, ream, qlean, lantern, lighthouse, grandine, ethlambda ...

- name: Deploy myclient node
  include_role:
    name: myclient
  when: client_type == "myclient"
  tags:
    - myclient
    - deploy
```

Also update the final guard at the bottom of the file to include your client type in the
known list:

```yaml
- name: Fail if unknown client type
  fail:
    msg: "Unknown client type '{{ client_type }}' for node '{{ node_name }}'. Expected: zeam, ream, qlean, lantern, lighthouse, grandine, ethlambda or myclient"
  when: client_type not in ["zeam", "ream", "qlean", "lantern", "lighthouse", "grandine", "ethlambda", "myclient"]
```

---

## Touch point 6 — Update `README.md`

In the **Clients supported** section, add your client to the numbered list:

```markdown
### Clients supported

Current following clients are supported:

1. Zeam
2. Ream
3. Qlean
4. Lantern
5. Lighthouse
6. Grandine
7. Ethlambda
8. Myclient        ← add here
```

---

## No changes needed elsewhere

The following components are fully generic and require zero modifications:

| Component | Why no changes needed |
|---|---|
| `spin-node.sh` | Discovers clients from `validator-config.yaml`; routes to `client-cmds/{client}-cmd.sh` by name |
| `generate-genesis.sh` | Uses `validator-config.yaml` as source of truth; assigns validator indices round-robin regardless of client type |
| `generate-subnet-config.py` | Derives client name from node name prefix; works for any `{client}_{index}` naming |
| `convert-validator-config.py` | Reads `apiPort` / `httpPort` from any entry; generates leanpoint upstreams for all nodes |
| `ansible/playbooks/deploy-nodes.yml` | Calls `deploy-single-node.yml` per node; no client-specific logic |
| `ansible/playbooks/prepare.yml` | Reads ports from config by IP; opens firewall rules for any node |
| `ansible/roles/observability/` | Scrapes `metricsPort` from config; works for any client |
| Aggregator selection | Derives subnet from `subnet:` field or defaults to 0; works for any node name |

---

## Checklist

```
[ ] 1. validator-config.yaml  — add entry with unique privkey, IP, ports
[ ] 2. client-cmds/myclient-cmd.sh — define node_binary, node_docker, node_setup
[ ] 3. ansible/roles/myclient/defaults/main.yml — fallback image and deployment mode
[ ] 4. ansible/roles/myclient/tasks/main.yml — extract config, start Docker container
[ ] 5. ansible/playbooks/helpers/deploy-single-node.yml — add include_role block + update guard
[ ] 6. README.md — add to Clients supported list
```

---

## Local test

```sh
# Generate genesis and spin up only your new node locally
NETWORK_DIR=local-devnet ./spin-node.sh --node myclient_0 --generateGenesis

# Verify it is running
docker ps | grep myclient_0

# Check health endpoint
curl http://127.0.0.1:5064/v0/health
```

## Ansible test

```sh
# Prepare the remote server (first time only)
NETWORK_DIR=ansible-devnet ./spin-node.sh --prepare --sshKey ~/.ssh/id_ed25519 --useRoot

# Deploy your node alongside the existing nodes
NETWORK_DIR=ansible-devnet ./spin-node.sh --node all --generateGenesis \
  --sshKey ~/.ssh/id_ed25519 --useRoot

# Dry run first to verify without deploying
NETWORK_DIR=ansible-devnet ./spin-node.sh --node myclient_0 --dry-run \
  --sshKey ~/.ssh/id_ed25519 --useRoot
```

## Subnet test

```sh
# Verify your client works correctly with 2 subnets
NETWORK_DIR=ansible-devnet ./spin-node.sh --node all --subnets 2 --generateGenesis \
  --sshKey ~/.ssh/id_ed25519 --useRoot
# Expected: myclient_0 (subnet 0) and myclient_1 (subnet 1) are both running
```
