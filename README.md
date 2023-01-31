# Donex core contracts written in Cairo

## What is Donex

See our [medium aticle](https://medium.com/@donexfinance/introducing-donex-finance-4818e4fa3a99).

## Install Cairo lang

[Install cairo-lang 0.10.3](https://www.cairo-lang.org/docs/quickstart.html#quickstart).
## Install depedency

```
pip3 install pytest asynctest pytest-xdist[psutil] openzeppelin-cairo-contracts
```

## Compile contract

```starknet-compile contracts/swap_pool.cairo --output artifacts/swap_pool.json --abi artifacts/abi/swap_pool.json```

## Run test

Run single test

```pytest -s -W ignore::DeprecationWarning tests/test_swap_pool.py```

or you can run it in parallel

```pytest -n auto -s -W ignore::DeprecationWarning tests/test_swap_pool.py```