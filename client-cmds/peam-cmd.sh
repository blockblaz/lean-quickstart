#!/bin/bash

#-----------------------peam setup----------------------

binary_path="$scriptDir/../Peam/target/release/peam"
default_peam_docker_image="ghcr.io/malik672/peam:sha-f11c8d1"
peam_docker_image="${PEAM_DOCKER_IMAGE:-$default_peam_docker_image}"
runtime_config_host="$dataDir/$item/peam.conf"
runtime_config_container="/data/peam.conf"
genesis_config="$configDir/config.yaml"
validator_config="$configDir/validator-config.yaml"
hash_sig_keys_dir="$configDir/hash-sig-keys"

genesis_time=$(yq eval '.GENESIS_TIME // .genesis_time' "$genesis_config")
validator_count=$(yq eval '.validators[].count // 1' "$validator_config" | awk '{sum += $1} END {print sum + 0}')
local_validator_index="${HASH_SIG_KEY_INDEX:-0}"
committee_count="${attestationCommitteeCount:-1}"
topic_domain="${devnet:-devnet0}"

allowed_topics="/leanconsensus/$topic_domain/block/ssz_snappy,/leanconsensus/$topic_domain/aggregation/ssz_snappy"
topic_scores="/leanconsensus/$topic_domain/block/ssz_snappy:2,/leanconsensus/$topic_domain/aggregation/ssz_snappy:1"
topic_validators="/leanconsensus/$topic_domain/block/ssz_snappy=block,/leanconsensus/$topic_domain/aggregation/ssz_snappy=aggregation"

for ((subnet = 0; subnet < committee_count; subnet++)); do
    att_topic="/leanconsensus/$topic_domain/attestation_${subnet}/ssz_snappy"
    allowed_topics="$allowed_topics,$att_topic"
    topic_scores="$topic_scores,$att_topic:1"
    topic_validators="$topic_validators,$att_topic=attestation"
done

cat > "$runtime_config_host" <<EOF
genesis_time=$genesis_time
metrics=true
metrics_address=0.0.0.0
metrics_port=$metricsPort
http_api=true
listen_addr=/ip4/0.0.0.0/udp/$quicPort/quic-v1
node_key_path=/config/$item.key
bootnodes_file=/config/nodes.yaml
validator_count=$validator_count
local_validator_index=$local_validator_index
attestation_committee_count=$committee_count
validator_config_path=/config/validator-config.yaml
allowed_topics=$allowed_topics
topic_scores=$topic_scores
topic_validators=$topic_validators
metrics_node_name=$item
metrics_client_name=peam
EOF

aggregator_flag=""
if [ "$isAggregator" == "true" ]; then
    aggregator_flag="--is-aggregator"
fi

checkpoint_sync_flag=""
if [ -n "${checkpoint_sync_url:-}" ]; then
    checkpoint_sync_flag="--checkpoint-sync-url $checkpoint_sync_url"
fi

validator_keys_flag=""
if [ -d "$hash_sig_keys_dir" ]; then
    validator_keys_flag="--validator-keys $hash_sig_keys_dir"
fi

api_port_flag=""
if [ -n "$apiPort" ]; then
    api_port_flag="--api-port $apiPort"
fi

node_binary="$binary_path \
      --run \
      --config $runtime_config_host \
      --data-dir $dataDir/$item \
      --node-id $item \
      $validator_keys_flag \
      $api_port_flag \
      $aggregator_flag \
      $checkpoint_sync_flag"

validator_keys_flag_container=""
if [ -d "$hash_sig_keys_dir" ]; then
    validator_keys_flag_container="--validator-keys /config/hash-sig-keys"
fi

node_docker="ghcr.io/malik672/peam:sha-f11c8d1 \
      --run \
      --config $runtime_config_container \
      --data-dir /data \
      --node-id $item \
      $validator_keys_flag_container \
      $api_port_flag \
      $aggregator_flag \
      $checkpoint_sync_flag"

if [ -n "${PEAM_DOCKER_IMAGE:-}" ]; then
    node_docker="${peam_docker_image}${node_docker#"ghcr.io/malik672/peam:sha-f11c8d1"}"
fi

node_setup="docker"
