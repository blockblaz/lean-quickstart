#!/bin/bash
# set -e

# Parse arguments first so we know special modes (e.g. --setupToolsServer) before requiring NETWORK_DIR/node
while [[ $# -gt 0 ]]; do
  key="$1"
  case $key in
    --node)
      node="$2"
      shift # past argument
      shift # past value
      ;;
    --validatorConfig)
      validatorConfig="$2"
      shift # past argument
      shift # past value
      ;;
    --forceKeyGen)
      # to be passed to genesis generator
      FORCE_KEYGEN_FLAG="--forceKeyGen"
      shift
      ;;
    --cleanData)
      cleanData=true
      shift # past argument
      ;;
    --popupTerminal)
      popupTerminal=true
      shift # past argument
      ;;
    --dockerWithSudo)
      dockerWithSudo=true
      shift # past argument
      ;;
    --metrics)
      enableMetrics=true
      shift # past argument
      ;;
    --generateGenesis)
      generateGenesis=true
      cleanData=true  # generateGenesis implies clean data
      shift # past argument
      ;;
    --deploymentMode)
      deploymentMode="$2"
      shift # past argument
      shift # past value
      ;;
    --sshKey|--private-key)
      sshKeyFile="$2"
      shift # past argument
      shift # past value
      ;;
    --useRoot)
      useRoot=true
      shift
      ;;
    --tag)
      dockerTag="$2"
      shift # past argument
      shift # past value
      ;;
    --stop)
      stopNodes=true
      shift
      ;;
    --setupToolsServer)
      setupToolsServer=true
      shift
      ;;
    *)    # unknown option
      shift # past argument
      ;;
  esac
done

# Tools server setup: no NETWORK_DIR or node required; spin-node.sh will branch and run setup-tools-server
if [ -z "$setupToolsServer" ] || [ "$setupToolsServer" != "true" ]; then
  # Require NETWORK_DIR for node operations
  if [ -z "$NETWORK_DIR" ]; then
    echo "set NETWORK_DIR env variable to run"
    exit 1
  fi

  echo "setting up network from $scriptDir/$NETWORK_DIR"
  configDir="$scriptDir/$NETWORK_DIR/genesis"
  dataDir="$scriptDir/$NETWORK_DIR/data"

  # TODO: check for presense of all required files by filenames on configDir
  if [ ! -n "$(ls -A $configDir)" ]; then
    echo "no genesis config at path=$configDir, exiting."
    exit 1
  fi

  # Require node for node operations
  if [[ ! -n "$node" ]]; then
    echo "no node specified, options = all or node names from validator config, exiting."
    exit 1
  fi
fi

if [ -z "$setupToolsServer" ] || [ "$setupToolsServer" != "true" ]; then
  if [ ! -n "$validatorConfig" ]; then
    echo "no external validator config provided, assuming genesis bootnode"
    validatorConfig="genesis_bootnode"
  fi

  echo "configDir = $configDir"
  echo "dataDir = $dataDir"
  echo "spin_nodes(s) = ${spin_nodes[@]}"
  echo "generateGenesis = $generateGenesis"
  echo "cleanData = $cleanData"
  echo "popupTerminal = $popupTerminal"
  echo "dockerTag = ${dockerTag:-latest}"
  echo "enableMetrics = $enableMetrics"
fi
