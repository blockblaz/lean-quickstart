#!/bin/bash

# TODO: parse validator-config to load values related to the $item
# needed for ream and qlean (or any other client), zeam picks directly from validator-config
# 1. load quic port and export it in $quicPort
# 2. private key and dump it into a file $client.key and export it in $privKeyPath

# $item, $configDir (genesis dir) is available here