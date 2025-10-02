#!/bin/bash
# set -e

mkdir $dataDir

for item in "${spin_nodes[@]}"; do
  itemDataDir="$dataDir/$item"
  mkdir $itemDataDir
  # with docker previous runs could have created dirs with non current user
  # hence might need sudo
  cmd="sudo rm -rf $itemDataDir/*"
  # always show the executing command
  echo $cmd
  eval $cmd
done;

if [ -n "$freshStart" ]
then
  TIME_NOW="$(date +%s)"
  GENESIS_TIME=$((TIME_NOW))
  sedPatten="/GENESIS_TIME/c\GENESIS_TIME: $GENESIS_TIME"
  cmd="sed -i \"$sedPatten\" \"$configDir/config.yaml\""
  echo $cmd
  eval $cmd
fi;
