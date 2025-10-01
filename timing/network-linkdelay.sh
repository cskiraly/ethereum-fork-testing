#!/bin/bash

config_file=$1
debug_output=/dev/null

# get timing from the config file
# format:
## network_params:
##   fulu_fork_epoch: 1
##   bpo_1_epoch: 2
##   bpo_1_max_blobs: 48
##   bpo_1_target_blobs: 48
##   withdrawal_type: "0x02"
##   genesis_delay: 40
##   seconds_per_slot: 6

genesis_delay=$(grep 'genesis_delay:' $config_file | awk '{print $2}')
seconds_per_slot=$(grep 'seconds_per_slot:' $config_file | awk '{print $2}')
fulu_fork_epoch=$(grep 'fulu_fork_epoch:' $config_file | awk '{print $2}')
slots_per_epoch=32
node_count=$(grep -w 'count:' $config_file | awk '{print $2}')

# make sure we have sudo permissions for tc
echo "Requesting sudo permissions to run tc on containers ... run at your own risk!"
sudo -v

echo "Applying 150+150 ms network delay on all links ..."
sudo ethereum-kurtosis-tc/bin/kurtosis-tc.sh -e -c --delay=150ms >$debug_output

# Timing:
# wait until 1 minute after fulu fork
wait_time=$((genesis_delay + seconds_per_slot * slots_per_epoch * fulu_fork_epoch + 60))
echo "Waiting for 1 minute after the fork ... ($wait_time seconds)"
sleep $wait_time

sleep 60
