#!/bin/bash
trap 'kill $(jobs -p)' EXIT
ganache-cli -l 6721975000 -m runway -a 20 -q & truffle test
