# Ethereum Fork Testing

**Ethereum Fork Testing** is designed to run local test networks reproducing various scenarios around a hard fork. It is based on:
- kurtosis to handle containerization
- the kurtosis ethereum-package to set up and run the test network
- ethereum-kurtosis-tc to simulate network scenarios

## Prerequisites

Install Docker and Kurtosis.

Make sure submodules are also cloned.

## Quickstart

`./testfork.sh config/fusaka-transition-1source.yaml timing/network-disrupt-at-fork.sh`

## Licence

MIT License, see the included LICENSE file.
