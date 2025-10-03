#!/bin/bash
# set -e

if [ -n "$freshStart" ]
then
  TIME_NOW="$(date +%s)"
  GENESIS_TIME=$((TIME_NOW + 30))
  sedPatten="/GENESIS_TIME/c\GENESIS_TIME: $GENESIS_TIME"
  cmd="sed -i \"$sedPatten\" \"$configDir/config.yaml\""
  echo $cmd
  eval $cmd
fi;
