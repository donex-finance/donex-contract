"""contract.cairo test file."""
import os
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
    felt_to_int, from_uint, encode_price_sqrt, expand_to_18decimals
)

Q128 = to_uint(2 ** 128)
MaxUint256 = to_uint(2 ** 256 - 1)

# The path to the contract source code.
CONTRACT_FILE = os.path.join("tests", "mocks/swapmath_mock.cairo")

class SwapmathTest(TestCase):
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

    @pytest.mark.asyncio
    async def test_compute_swap_step(self):
        #await assert_revert(
        #    self.contract.most_significant_bit(to_uint(0)).call(),
        #    ""
        #)

        price = encode_price_sqrt(1, 1)
        price_target = encode_price_sqrt(101, 100)
        liquidity = expand_to_18decimals(2)
        amount = to_uint(expand_to_18decimals(1))
        fee = 600
        zero_for_one = 0

        res = await self.contract.compute_swap_step(price, price_target, liquidity, amount, fee).call()

        print(res.call_info.result)