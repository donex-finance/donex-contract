import os
import pytest
import math
from functools import reduce
from starkware.starknet.testing.starknet import Starknet
from asynctest import TestCase
from starkware.starknet.compiler.compile import compile_starknet_files
from inspect import signature
from utils import (
    MAX_UINT256, assert_revert, add_uint, sub_uint,
    mul_uint, div_rem_uint, to_uint, contract_path,
    felt_to_int, from_uint, encode_price_sqrt as encodePriceSqrt
)

CONTRACT_FILE = os.path.join("tests", "mocks/liquidity_amounts_mock.cairo")

async def init_contract():
    starknet = await Starknet.empty()
    compiled_contract = compile_starknet_files(
        [CONTRACT_FILE], debug_info=True, disable_hint_validation=True
    )
    kwargs = (
        {"contract_def": compiled_contract}
        if "contract_def" in signature(starknet.deploy).parameters
        else {"contract_class": compiled_contract}
    )
    #kwargs["constructor_calldata"] = [len(PRODUCT_ARRAY), *PRODUCT_ARRAY]

    contract = await starknet.deploy(**kwargs)
    return contract


class LiquidityAmountsTest(TestCase):
    @classmethod
    async def setUp(cls):
        if not hasattr(cls, 'contract'):
            cls.contract = await init_contract()

    @pytest.mark.asyncio
    async def test_get_liquidity_for_amounts(self):
        # amounts for price inside
        sqrtPriceX96 = encodePriceSqrt(1, 1)
        sqrtPriceAX96 = encodePriceSqrt(100, 110)
        sqrtPriceBX96 = encodePriceSqrt(110, 100)
        res = await self.contract.get_liquidity_for_amounts(
            sqrtPriceX96,
            sqrtPriceAX96,
            sqrtPriceBX96,
            to_uint(100),
            to_uint(200)
        ).call()
        liquidity = res.call_info.result[0]
        self.assertEqual(liquidity, 2148)

    @pytest.mark.asyncio
    async def test_get_liquidity_for_amounts2(self):
        # amounts for price below
        sqrtPriceX96 = encodePriceSqrt(99, 110)
        sqrtPriceAX96 = encodePriceSqrt(100, 110)
        sqrtPriceBX96 = encodePriceSqrt(110, 100)
        res = await self.contract.get_liquidity_for_amounts(
            sqrtPriceX96,
            sqrtPriceAX96,
            sqrtPriceBX96,
            to_uint(100),
            to_uint(200)
        ).call()
        liquidity = res.call_info.result[0]
        self.assertEqual(liquidity, 1048)

    @pytest.mark.asyncio
    async def test_get_liquidity_for_amounts3(self):
        # amounts for price above
        sqrtPriceX96 = encodePriceSqrt(111, 100)
        sqrtPriceAX96 = encodePriceSqrt(100, 110)
        sqrtPriceBX96 = encodePriceSqrt(110, 100)
        res = await self.contract.get_liquidity_for_amounts(
            sqrtPriceX96,
            sqrtPriceAX96,
            sqrtPriceBX96,
            to_uint(100),
            to_uint(200)
        ).call()
        liquidity = res.call_info.result[0]
        self.assertEqual(liquidity, 2097)

    @pytest.mark.asyncio
    async def test_get_liquidity_for_amounts4(self):
        # amounts for price equal to lower boundary
        sqrtPriceAX96 = encodePriceSqrt(100, 110)
        sqrtPriceX96 = sqrtPriceAX96
        sqrtPriceBX96 = encodePriceSqrt(110, 100)
        res = await self.contract.get_liquidity_for_amounts(
            sqrtPriceX96,
            sqrtPriceAX96,
            sqrtPriceBX96,
            to_uint(100),
            to_uint(200)
        ).call()
        liquidity = res.call_info.result[0]
        self.assertEqual(liquidity, 1048)

    @pytest.mark.asyncio
    async def test_get_liquidity_for_amounts5(self):
        # amounts for price equal to upper boundary
        sqrtPriceAX96 = encodePriceSqrt(100, 110)
        sqrtPriceBX96 = encodePriceSqrt(110, 100)
        sqrtPriceX96 = sqrtPriceBX96
        res = await self.contract.get_liquidity_for_amounts(
            sqrtPriceX96,
            sqrtPriceAX96,
            sqrtPriceBX96,
            to_uint(100),
            to_uint(200)
        ).call()
        liquidity = res.call_info.result[0]
        self.assertEqual(liquidity, 2097)

    @pytest.mark.asyncio
    async def test_get_amounts_for_liquidity1(self):
        # amounts for price inside
        sqrtPriceX96 = encodePriceSqrt(1, 1)
        sqrtPriceAX96 = encodePriceSqrt(100, 110)
        sqrtPriceBX96 = encodePriceSqrt(110, 100)
        res = await self.contract.get_amounts_for_liquidity(
            sqrtPriceX96,
            sqrtPriceAX96,
            sqrtPriceBX96,
            2148
        ).call()
        amount0 = from_uint(res.call_info.result[0: 2])
        amount1 = from_uint(res.call_info.result[2: 4])
        self.assertEqual(amount0, 99)
        self.assertEqual(amount1, 99)

    @pytest.mark.asyncio
    async def test_get_amounts_for_liquidity2(self):
        # amounts for price below
        sqrtPriceX96 = encodePriceSqrt(99, 110)
        sqrtPriceAX96 = encodePriceSqrt(100, 110)
        sqrtPriceBX96 = encodePriceSqrt(110, 100)
        res = await self.contract.get_amounts_for_liquidity(
            sqrtPriceX96,
            sqrtPriceAX96,
            sqrtPriceBX96,
            1048
        ).call()
        amount0 = from_uint(res.call_info.result[0: 2])
        amount1 = from_uint(res.call_info.result[2: 4])
        self.assertEqual(amount0, 99)
        self.assertEqual(amount1, 0)

    @pytest.mark.asyncio
    async def test_get_amounts_for_liquidity3(self):
        # amounts for price above
        sqrtPriceX96 = encodePriceSqrt(111, 100)
        sqrtPriceAX96 = encodePriceSqrt(100, 110)
        sqrtPriceBX96 = encodePriceSqrt(110, 100)
        res = await self.contract.get_amounts_for_liquidity(
            sqrtPriceX96,
            sqrtPriceAX96,
            sqrtPriceBX96,
            2097
        ).call()
        amount0 = from_uint(res.call_info.result[0: 2])
        amount1 = from_uint(res.call_info.result[2: 4])
        self.assertEqual(amount0, 0)
        self.assertEqual(amount1, 199)

    @pytest.mark.asyncio
    async def test_get_amounts_for_liquidity4(self):
        # amounts for price on lower boundary
        sqrtPriceAX96 = encodePriceSqrt(100, 110)
        sqrtPriceX96 = sqrtPriceAX96
        sqrtPriceBX96 = encodePriceSqrt(110, 100)
        res = await self.contract.get_amounts_for_liquidity(
            sqrtPriceX96,
            sqrtPriceAX96,
            sqrtPriceBX96,
            1048
        ).call()
        amount0 = from_uint(res.call_info.result[0: 2])
        amount1 = from_uint(res.call_info.result[2: 4])
        self.assertEqual(amount0, 99)
        self.assertEqual(amount1, 0)

    @pytest.mark.asyncio
    async def test_get_amounts_for_liquidity5(self):
        # amounts for price on upper boundary
        sqrtPriceAX96 = encodePriceSqrt(100, 110)
        sqrtPriceBX96 = encodePriceSqrt(110, 100)
        sqrtPriceX96 = sqrtPriceBX96
        res = await self.contract.get_amounts_for_liquidity(
            sqrtPriceX96,
            sqrtPriceAX96,
            sqrtPriceBX96,
            2097
        ).call()
        amount0 = from_uint(res.call_info.result[0: 2])
        amount1 = from_uint(res.call_info.result[2: 4])
        self.assertEqual(amount0, 0)
        self.assertEqual(amount1, 199)