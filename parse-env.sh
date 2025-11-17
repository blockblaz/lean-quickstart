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
    --tag)
      dockerTag="$2"
      shift # past argument
      shift # past value
      ;;
    *)    # unknown option
      shift # past argument
      ;;
  esac
done

# if no node has been assigned assume all nodes to be started
if [[ ! -n "$node" ]];
then
  echo "no node specified, exiting..."
  exit
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
