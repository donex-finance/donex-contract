"""contract.cairo test file."""
import os
import time
import pytest
import math
from functools import reduce
from asynctest import TestCase
from starkware.starknet.compiler.compile import compile_starknet_files
from inspect import signature
from starkware.starknet.testing.starknet import Starknet
from utils import (
    MAX_UINT256, assert_revert, add_uint, sub_uint,
    mul_uint, div_rem_uint, to_uint, contract_path,
    felt_to_int, from_uint, cached_contract, encode_price_sqrt,
    get_max_tick, get_min_tick, TICK_SPACINGS, FeeAmount
)

from test_tickmath import (MIN_SQRT_RATIO, MAX_SQRT_RATIO)

Q128 = to_uint(2 ** 128)
MaxUint256 = to_uint(2 ** 256 - 1)

# The path to the contract source code.
CONTRACT_FILE = os.path.join("tests", "../contracts/swap_pool.cairo")

tick_spacing = TICK_SPACINGS[FeeAmount.MEDIUM]

async def init_contract():
    begin = time.time()
    starknet = await Starknet.empty()
    print('create starknet time:', time.time() - begin)
    begin = time.time()
    compiled_contract = compile_starknet_files(
        [CONTRACT_FILE], debug_info=True, disable_hint_validation=True
    )
    print('compile contract time:', time.time() - begin)

    kwargs = {
        "contract_class": compiled_contract,
        "constructor_calldata": [tick_spacing, 0]
        }

    begin = time.time()
    contract = await starknet.deploy(**kwargs)
    print('deploy contract time:', time.time() - begin)

    return compiled_contract, contract

class SwapPoolTest(TestCase):

    @classmethod
    async def setUp(cls):
        if not hasattr(cls, 'contract_def'):
            cls.contract_def, cls.contract = await init_contract()

    def get_state_contract(self):
        _state = self.contract.state.copy()
        new_contract = cached_contract(_state, self.contract_def, self.contract)
        return new_contract


    @pytest.mark.asyncio
    async def test_initialize(self):

        contract = self.get_state_contract()
        begin = time.time()
        await contract.initialize(encode_price_sqrt(1, 1)).invoke()
        print('initial call time:', time.time() - begin)
        await assert_revert(
            contract.initialize(encode_price_sqrt(1, 1)).invoke(),
            "initialize more than once"
        )

        contract = self.get_state_contract()
        await assert_revert(
            contract.initialize(to_uint(1)).invoke(),
            "tick is too low"
        )
        await assert_revert(
            contract.initialize(to_uint(MIN_SQRT_RATIO - 1)).invoke(),
            "tick is too low"
        )

        contract = self.get_state_contract()
        await assert_revert(
            contract.initialize(to_uint(MAX_SQRT_RATIO)).invoke(),
            "tick is too high"
        )
        await assert_revert(
            contract.initialize(to_uint(2 ** 160 - 1)).invoke(),
            "tick is too high"
        )

        # can be initialized at MIN_SQRT_RATIO
        contract = self.get_state_contract()
        await contract.initialize(to_uint(MIN_SQRT_RATIO)).invoke()
        res = await contract.get_cur_slot().call()
        tick = felt_to_int(res.call_info.result[2])
        self.assertEqual(tick, get_min_tick(1))

        contract = self.get_state_contract()
        await contract.initialize(to_uint(MAX_SQRT_RATIO - 1)).invoke()
        res = await contract.get_cur_slot().call()
        tick = felt_to_int(res.call_info.result[2])
        self.assertEqual(tick, get_max_tick(1) - 1)

        contract = self.get_state_contract()
        price = encode_price_sqrt(1, 2)
        await contract.initialize(price).invoke()
        res = await contract.get_cur_slot().call()
        sqrt_price_x96 = tuple(res.call_info.result[0: 2])
        tick = felt_to_int(res.call_info.result[2])
        self.assertEqual(price, sqrt_price_x96)
        self.assertEqual(tick, -6932)
