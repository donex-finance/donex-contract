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

```starknet-compile contracts/user_position_mgr.cairo --output artifacts/user_position_mgr.json --abi artifacts/abi/user_position_mgr.json```

## Run test

Run single test

```pytest -s -W ignore::DeprecationWarning tests/test_user_position_mgr.py```

or you can run it in parallel

```pytest -n auto -s -W ignore::DeprecationWarning tests/test_user_position_mgr.py```