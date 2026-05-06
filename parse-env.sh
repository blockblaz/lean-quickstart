#!/bin/bash
# set -e

if [ -n "$NETWORK_DIR" ]
then
  # Support both absolute paths and relative paths (relative to scriptDir)
  if [[ "$NETWORK_DIR" = /* ]]; then
    _resolved_network_dir="$NETWORK_DIR"
  else
    _resolved_network_dir="$scriptDir/$NETWORK_DIR"
  fi
  echo "setting up network from $_resolved_network_dir"
  configDir="$_resolved_network_dir/genesis"
  dataDir="$_resolved_network_dir/data"
else
  echo "set NETWORK_DIR env variable to run"
  exit
fi;

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
    --aggregator)
      aggregatorNode="$2"
      shift # past argument
      shift # past value
      ;;
    --checkpoint-sync-url)
      checkpointSyncUrl="$2"
      shift
      shift
      ;;
    --restart-client)
      restartClient="$2"
      shift
      shift
      ;;
    --coreDumps)
      coreDumps="$2"
      shift # past argument
      shift # past value
      ;;
    --skip-leanpoint)
      skipLeanpoint=true
      shift
      ;;
    --skip-nemo)
      skipNemo=true
      shift
      ;;
    --prepare)
      prepareMode=true
      shift
      ;;
    --subnets)
      subnets="$2"
      shift # past argument
      shift # past value
      ;;
    --dry-run)
      dryRun=true
      shift
      ;;
    --replace-with)
      replaceWith="$2"
      shift
      shift
      ;;
    --network)
      networkName="$2"
      shift # past argument
      shift # past value
      ;;
    --logs)
      enableLogs=true
      shift
      ;;
    *)    # unknown option
      shift # past argument
      ;;
  esac
done

# if no node and no restart-client specified, exit (unless --prepare mode)
if [[ ! -n "$node" ]] && [[ ! -n "$restartClient" ]] && [[ "$prepareMode" != "true" ]];
then
  echo "no node or restart-client specified, exiting..."
  exit
fi;

# Check genesis dir exists and is non-empty, unless --generateGenesis will create it
if [ "$generateGenesis" != "true" ] && [ ! -n "$(ls -A $configDir 2>/dev/null)" ]
then
  echo "no genesis config at path=$configDir, exiting."
  exit
fi;

# Validate --replace-with requires --restart-client
if [[ -n "$replaceWith" ]] && [[ ! -n "$restartClient" ]]; then
  echo "Warning: --replace-with requires --restart-client. Ignoring --replace-with."
  replaceWith=""
fi

# When using --restart-client with checkpoint sync, set default checkpoint URL if not provided
if [[ -n "$restartClient" ]] && [[ ! -n "$checkpointSyncUrl" ]]; then
  checkpointSyncUrl="https://leanpoint.leanroadmap.org/lean/v0/states/finalized"
fi;

if [ ! -n "$validatorConfig" ]
then
  echo "no external validator config provided, assuming genesis bootnode"
  validatorConfig="genesis_bootnode"
fi;

# freshStart logic removed - now handled by --generateGenesis flag

echo "configDir = $configDir"
echo "dataDir = $dataDir"
echo "spin_nodes(s) = ${spin_nodes[@]}"
echo "generateGenesis = $generateGenesis"
echo "cleanData = $cleanData"
echo "popupTerminal = $popupTerminal"
echo "dockerTag = ${dockerTag:-latest}"
echo "enableMetrics = $enableMetrics"
echo "aggregatorNode = ${aggregatorNode:-<auto-select>}"
echo "coreDumps = ${coreDumps:-disabled}"
echo "checkpointSyncUrl = ${checkpointSyncUrl:-<not set>}"
echo "restartClient = ${restartClient:-<not set>}"
echo "skipLeanpoint = ${skipLeanpoint:-false}"
echo "skipNemo = ${skipNemo:-false}"
echo "dryRun = ${dryRun:-false}"
echo "replaceWith = ${replaceWith:-<not set>}"
echo "networkName = $networkName"
echo "enableLogs = ${enableLogs:-false}"
