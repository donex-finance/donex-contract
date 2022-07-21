"""contract.cairo test file."""
import os
import pytest
import math
from functools import reduce
from starkware.starknet.testing.starknet import Starknet
from asynctest import TestCase
from starkware.starknet.compiler.compile import compile_starknet_files
from inspect import signature
from starkware.starknet.testing.starknet import Starknet
from utils import (
    MAX_UINT256, assert_revert, add_uint, sub_uint,
    mul_uint, div_rem_uint, to_uint, contract_path,
    felt_to_int, from_uint, encode_price_sqrt, expand_to_18decimals
)
from decimal import *

Q128 = to_uint(2 ** 128)
MaxUint256 = to_uint(2 ** 256 - 1)
MAXUint128 = to_uint(2 ** 128 - 1)

# The path to the contract source code.
CONTRACT_FILE = os.path.join("tests", "mocks/sqrt_price_math_mock.cairo")

class FullMathTest(TestCase):
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

    '''
    @pytest.mark.asyncio
    async def test_get_amount0_delta(self):

        res = await self.contract.get_amount0_delta(encode_price_sqrt(1, 1), encode_price_sqrt(2, 1), 0, 1).call()
        self.assertEqual(
            tuple(res.call_info.result),
            to_uint(0),
            "liquidity is 0"
        )

        res = await self.contract.get_amount0_delta(encode_price_sqrt(1, 1), encode_price_sqrt(1, 1), 0, 1).call()
        self.assertEqual(
            tuple(res.call_info.result),
            to_uint(0),
            "price equal"
        )

        res = await self.contract.get_amount0_delta(encode_price_sqrt(1, 1), encode_price_sqrt(121, 100), expand_to_18decimals(1), 1).call()
        self.assertEqual(
            tuple(res.call_info.result),
            to_uint(90909090909090910),
            "return 0.1 amount1 for price of 1 to 1.21"
        )

        res = await self.contract.get_amount0_delta(encode_price_sqrt(2 ** 90, 1), encode_price_sqrt(2 ** 96, 1), expand_to_18decimals(1), 1).call()
        res2 = await self.contract.get_amount0_delta(encode_price_sqrt(2 ** 90, 1), encode_price_sqrt(2 ** 96, 1), expand_to_18decimals(1), 0).call()
        self.assertEqual(
            from_uint(res.call_info.result),
            from_uint(res2.call_info.result) + 1,
            "rounding up down"
        )

    @pytest.mark.asyncio
    async def test_get_amount1_delta(self):

        res = await self.contract.get_amount1_delta(encode_price_sqrt(1, 1), encode_price_sqrt(2, 1), 0, 1).call()
        self.assertEqual(
            tuple(res.call_info.result),
            to_uint(0),
            "liquidity is 0"
        )

        res = await self.contract.get_amount1_delta(encode_price_sqrt(1, 1), encode_price_sqrt(1, 1), 0, 1).call()
        self.assertEqual(
            tuple(res.call_info.result),
            to_uint(0),
            "liquidity is 0"
        )

        res = await self.contract.get_amount1_delta(encode_price_sqrt(1, 1), encode_price_sqrt(121, 100), expand_to_18decimals(1), 1).call()
        self.assertEqual(
            tuple(res.call_info.result),
            to_uint(100000000000000000),
            ""
        )

        res = await self.contract.get_amount1_delta(encode_price_sqrt(1, 1), encode_price_sqrt(121, 100), expand_to_18decimals(1), 0).call()
        self.assertEqual(
            tuple(res.call_info.result),
            to_uint(100000000000000000 - 1),
            ""
        )
    '''

    @pytest.mark.asyncio
    async def test_get_next_sqrt_price_from_input(self):
        await assert_revert(
            self.contract.get_next_sqrt_price_from_input(to_uint(0), 1, to_uint(expand_to_18decimals(1) // 10), 0).call(),
            "sqrt_price_x96 must be greater than 0"
        )

        await assert_revert(
            self.contract.get_next_sqrt_price_from_input(to_uint(1), 0, to_uint(expand_to_18decimals(1) // 10), 0).call(),
            "liquidity must be greater than 0"
        )

        price = 2 ** 160 - 1
        res = await self.contract.get_next_sqrt_price_from_input(to_uint(price), 1024, to_uint(1024), 0).call()
        print(f'res = {res.call_info.result}')

        #TODO:
        #await assert_revert(
        #    self.contract.get_next_sqrt_price_from_input(to_uint(price), 1024, to_uint(1024), 0).call(),
        #)

        res = await self.contract.get_next_sqrt_price_from_input(to_uint(1), 1, to_uint(2 ** 255), 1).call()
        self.assertEqual(
            tuple(res.call_info.result),
            to_uint(1)
        )

        price = encode_price_sqrt(1, 1)
        res = await self.contract.get_next_sqrt_price_from_input(price, expand_to_18decimals(1) // 10, to_uint(0), 1).call()
        self.assertEqual(
            tuple(res.call_info.result),
            price
        )

        price = encode_price_sqrt(1, 1)
        res = await self.contract.get_next_sqrt_price_from_input(price, expand_to_18decimals(1) // 10, to_uint(0), 0).call()
        self.assertEqual(
            tuple(res.call_info.result),
            price
        )

        #TODO:
        #price = 2 ** 160 - 1
        #liquidity = 2 ** 128 - 1
        #amount = 2 ** 256 -  (liquidity * 2 ** 96 // price)
        #res = await self.contract.get_next_sqrt_price_from_input(to_uint(price), 2 ** 128 - 1, to_uint(amount), 1).call()
        #self.assertEqual(
        #    tuple(res.call_info.result),
        #    to_uint(1),
        #    "returns the minimum price for max inputs"
        #)

        price = encode_price_sqrt(1, 1)
        print('price: ', from_uint(price))
        res = await self.contract.get_next_sqrt_price_from_input(encode_price_sqrt(1, 1), expand_to_18decimals(1), to_uint(expand_to_18decimals(1) // 10), 0).call()
        self.assertEqual(
            tuple(res.call_info.result),
            to_uint(87150978765690771352898345369),
            'input amount of 0.1 token1'
        )

        res = await self.contract.get_next_sqrt_price_from_input(encode_price_sqrt(1, 1), expand_to_18decimals(1), to_uint(expand_to_18decimals(1) // 10), 1).call()
        self.assertEqual(
            tuple(res.call_info.result),
            to_uint(72025602285694852357767227579)
        )

        res = await self.contract.get_next_sqrt_price_from_input(encode_price_sqrt(1, 1), expand_to_18decimals(10), to_uint(2 ** 100), 1).call()
        self.assertEqual(
            tuple(res.call_info.result),
            to_uint(624999999995069620),
            "amountIn > type(uint96).max and zeroForOne = true"
        )

        amount = (2 ** 256 - 1) // 2
        res = await self.contract.get_next_sqrt_price_from_input(encode_price_sqrt(1, 1), 1, to_uint(amount), 1).call()
        self.assertEqual(
            tuple(res.call_info.result),
            to_uint(1),
            "can return 1 with enough amountIn and zeroForOne = true"
        )