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

# Timing:
# - 40 seconds before genesis
# - 6 second slots, 32 slots per epoch => 192 seconds per epoch
# - wait until 6 slots before the fork (fulu_fork_epoch)
wait_time=$((genesis_delay + seconds_per_slot * (slots_per_epoch * fulu_fork_epoch - 6) ))
echo "Waiting for the last few slots before the fork...($wait_time seconds)"
sleep $wait_time

wait_time=$((seconds_per_slot * 12))
echo "simulation network issues for 12 slots...($wait_time seconds)"
sudo ethereum-kurtosis-tc/bin/kurtosis-tc.sh -e --delay=2000ms --uplink=100kbps --downlink=100kbps >$debug_output
sudo ethereum-kurtosis-tc/bin/kurtosis-tc.sh -c --delay=2000ms --uplink=100kbps --downlink=100kbps >>$debug_output
sleep $wait_time
echo "removing network issues"
sudo ethereum-kurtosis-tc/bin/kurtosis-tc.sh -e --delete >>$debug_output
sudo ethereum-kurtosis-tc/bin/kurtosis-tc.sh -c --delete >>$debug_output

echo "Waiting for 1 minute to allow logs to accumulate..."
sleep 60
