#!/bin/bash
# set -e

if [ -n "$NETWORK_DIR" ]
then
  echo "setting up network from $scriptDir/$NETWORK_DIR"
  configDir="$scriptDir/$NETWORK_DIR/genesis"
  dataDir="$scriptDir/$NETWORK_DIR/data"
else
  echo "set NETWORK_DIR env variable to run"
  exit
fi;

# TODO: check for presense of all required files by filenames on configDir
if [ ! -n "$(ls -A $configDir)" ]
then
  echo "no genesis config at path=$configDir, exiting."
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
    *)    # unknown option
      shift # past argument
      ;;
  esac
done

# if no node and no restart-client specified, exit
if [[ ! -n "$node" ]] && [[ ! -n "$restartClient" ]];
then
  echo "no node or restart-client specified, exiting..."
  exit
fi;

# When using --restart-client with checkpoint sync, set default checkpoint URL if not provided
if [[ -n "$restartClient" ]] && [[ ! -n "$checkpointSyncUrl" ]]; then
  checkpointSyncUrl="https://leanpoint.leanroadmap.org"
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
echo "coreDumps = ${coreDumps:-disabled}"
echo "checkpointSyncUrl = ${checkpointSyncUrl:-<not set>}"
echo "restartClient = ${restartClient:-<not set>}"
