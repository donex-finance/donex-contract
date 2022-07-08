"""contract.cairo test file."""
import os
import pytest
from functools import reduce
from starkware.starknet.testing.starknet import Starknet
from asynctest import TestCase
from starkware.starknet.compiler.compile import compile_starknet_files
from inspect import signature
from starkware.starknet.testing.starknet import Starknet
from utils import (
    MAX_UINT256, assert_revert, add_uint, sub_uint,
    mul_uint, div_rem_uint, to_uint, contract_path
)

# The path to the contract source code.
CONTRACT_FILE = os.path.join("tests", "mocks/tickmath_mock.cairo")

MIN_TICK = -887272
# @dev The maximum tick that may be passed to #get_sqrt_ratio_at_tick computed from log uint256_ltbase 1.0001 of 2**128
MAX_TICK = -MIN_TICK

MIN_SQRT_RATIO = 4295128739
# @dev The maximum value that can be returned from #get_sqrt_ratio_at_tick. Equivalent to get_sqrt_ratio_at_tick(MAX_TICK)
# TODO: in ether, this value is 1461446703485210103287273052203988822378723970342
MAX_SQRT_RATIO_LOW = 1461446703485210103287273052203988822378723970342

class CairoContractTest(TestCase):
    @classmethod
    async def setUp(cls):
        cls.starknet = await Starknet.empty()
        compiled_contract = compile_starknet_files(
            [CONTRACT_FILE], debug_info=True, disable_hint_validation=True
        )
        kwargs = (
            {"contract_def": compiled_contract}
            if "contract_def" in signature(cls.starknet.deploy).parameters
            else {"contract_class": compiled_contract}
        )
        #kwargs["constructor_calldata"] = [len(PRODUCT_ARRAY), *PRODUCT_ARRAY]

        cls.contract = await cls.starknet.deploy(**kwargs)

    #@pytest.mark.asyncio
    #async def test_mock_contract(self):
    #    a = to_uint(79224201403219477170569942574)
    #    res = await self.contract.get_sqrt_ratio_at_tick(-1).call()
    #    print(res.call_info.result, a)
    #    self.assertEqual(
    #        tuple(res.call_info.result),
    #        a,
    #        "test wrong"
    #    )

    @pytest.mark.asyncio
    async def test_get_sqrt_ratio_at_tick(self):
        await assert_revert(
            self.contract.get_sqrt_ratio_at_tick(MIN_TICK - 1).call(),
            "TickMath: abs_tick is too large"
        )

        await assert_revert(
            self.contract.get_sqrt_ratio_at_tick(MAX_TICK + 1).call(),
            "TickMath: abs_tick is too large"
        )

        res = await self.contract.get_sqrt_ratio_at_tick(MIN_TICK).call()
        self.assertEqual(
            tuple(res.call_info.result),
            to_uint(4295128739),
            "MIN_TICK error"
        )

        res = await self.contract.get_sqrt_ratio_at_tick(MIN_TICK + 1).call()
        self.assertEqual(
            tuple(res.call_info.result),
            to_uint(4295343490),
            "MIN_TICK + 1 error"
        )

        res = await self.contract.get_sqrt_ratio_at_tick(MAX_TICK - 1).call()
        self.assertEqual(
            tuple(res.call_info.result),
            to_uint(1461373636630004318706518188784493106690254656249),
            "MAX_TICK - 1 error"
        )

        res = await self.contract.get_sqrt_ratio_at_tick(MAX_TICK - 1).call()
        self.assertEqual(
            tuple(res.call_info.result),
            to_uint(1461373636630004318706518188784493106690254656249),
            "MAX_TICK - 1 error"
        )

        res = await self.contract.get_sqrt_ratio_at_tick(MAX_TICK).call()
        self.assertEqual(
            tuple(res.call_info.result),
            to_uint(1461446703485210103287273052203988822378723970342),
            "MAX_TICK error"
        )

        ticks = [
            50,
            100,
            250,
            500,
            1_000,
            2_500,
            3_000,
            4_000,
            5_000,
            50_000,
            150_000,
            250_000,
            500_000,
            738_203,
        ]
        for tick in ticks:
            for t in [-tick, tick]:
                res = await self.contract.get_sqrt_ratio_at_tick(t).call()
                print(t, res.call_info.result)
                #self.assertEqual(
                #    tuple(res.call_info.result),
                #    to_uint(1461446703485210103287273052203988822378723970342),
                #    "MAX_TICK error"
                #)
