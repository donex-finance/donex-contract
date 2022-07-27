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
        sqrt_price = tuple(res.call_info.result[:2])
        amount_in = tuple(res.call_info.result[2: 4])
        amount_out = tuple(res.call_info.result[4: 6])
        fee_amount = tuple(res.call_info.result[6: 8])
        self.assertEqual(
            amount_in,
            to_uint(9975124224178055)
        )
        self.assertEqual(
            amount_out,
            to_uint(9925619580021728)
        )
        self.assertEqual(
            fee_amount,
            to_uint(5988667735148)
        )

        #priceAfterWholeInputAmount = await self.sqrtPriceMath.getNextSqrtPriceFromInput(price, liquidity, amount, zero_for_one)
        self.assertEqual(sqrt_price, price_target)
        #self.assertEqual(sqrt_price < priceAfterWholeInputAmount, True)