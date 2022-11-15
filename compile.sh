#!/bin/bash
starknet-compile contracts/$1.cairo --output artifacts/$1.json --abi artifacts/abi/$1.json
