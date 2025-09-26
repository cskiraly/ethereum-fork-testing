#!/bin/bash
set -e
set -o pipefail

# This script is used to test the fusaka transition setup in a Kurtosis enclave.
# It runs the Ethereum package in a new enclave, waits for 2 minutes to allow logs
# to accumulate, and then collects and filters the logs from each node to display
# any ERROR or WARN messages.

config_file="test-fusaka-transition-01.yaml"
enclave_name="test-fusaka-transition"
logfile="${config_file%.*}.log"

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

# Remove any existing enclave with the same name to ensure a clean start
kurtosis enclave rm -f $enclave_name || true

# Start a new enclave with the specified configuration file
kurtosis run --enclave $enclave_name github.com/ethpandaops/ethereum-package --args-file $config_file

# Timing:
# - 40 seconds before genesis
# - 6 second slots, 32 slots per epoch => 192 seconds per epoch
# - wait until 6 slots before the fork (fulu_fork_epoch)
wait_time=$((genesis_delay + seconds_per_slot * (slots_per_epoch * fulu_fork_epoch - 6) ))
echo "Waiting for the last few slots before the fork...($wait_time seconds)"
sleep $wait_time

wait_time=$((seconds_per_slot * 12))
echo "simulation network issues for 12 slots...($wait_time seconds)"
sudo ethereum-kurtosis-tc/bin/kurtosis-tc.sh -e --delay=2000ms --uplink=100kbps --downlink=100kbps
sudo ethereum-kurtosis-tc/bin/kurtosis-tc.sh -c --delay=2000ms --uplink=100kbps --downlink=100kbps
sleep $wait_time
echo "removing network issues"
sudo ethereum-kurtosis-tc/bin/kurtosis-tc.sh -e --delete
sudo ethereum-kurtosis-tc/bin/kurtosis-tc.sh -c --delete

echo "Waiting for 1 minute to allow logs to accumulate..."
sleep 60

# Generate merged EL logs from all nodes
for node in $(seq 1 $node_count); do
    docker logs $(docker ps --filter name=^/el-0*$node --quiet) 2>&1 | sed -e "s/^/el-$node /" -e "s/\[/ \[/";
done | sort -s -k3,3 > $logfile

echo -e "\nChecking for conversion logs"
grep -i "conver" $logfile || echo "No conversion logs found"

echo -e "\nChecking for errors"
grep -i "ERROR" $logfile || echo "No ERROR logs found"

# stop the enclave, but keep the data for further investigation if needed
kurtosis enclave stop $enclave_name