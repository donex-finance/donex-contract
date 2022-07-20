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
    felt_to_int, from_uint
)
from decimal import *

Q128 = to_uint(2 ** 128)
MaxUint256 = to_uint(2 ** 256 - 1)

# The path to the contract source code.
CONTRACT_FILE = os.path.join("tests", "mocks/fullmath_mock.cairo")

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

    @pytest.mark.asyncio
    async def test_mul_div(self):
        await assert_revert(
            self.contract.uint256_mul_div(Q128, to_uint(5), to_uint(0)).call(),
            "denominator is zero"
        )

        await assert_revert(
            self.contract.uint256_mul_div(Q128, Q128, to_uint(1)).call(),
            "overflows uint256"
        )

        await assert_revert(
            self.contract.uint256_mul_div(MaxUint256, MaxUint256, to_uint(2 ** 256 - 2)).call(),
            "overflows uint256"
        )

        res = await self.contract.uint256_mul_div(MAX_UINT256, MAX_UINT256, MAX_UINT256).call()
        self.assertEqual(
            tuple(res.call_info.result),
            MAX_UINT256
        )

        a = 2 ** 256 - 2
        b = 2 ** 256 - 2
        c = 2 ** 256 - 1
        res = await self.contract.uint256_mul_div(to_uint(a), to_uint(b), to_uint(c)).call()
        expected = to_uint(a * b // c)
        self.assertEqual(
            tuple(res.call_info.result),
            expected
        )

        res = await self.contract.uint256_mul_div(Q128, to_uint(50 * 2 ** 128), to_uint(150 * 2 ** 128)).call()
        expected = to_uint(2 ** 128 // 3)
        self.assertEqual(
            tuple(res.call_info.result),
            expected
        )

        res = await self.contract.uint256_mul_div(Q128, to_uint(35 * 2 ** 128), to_uint(8 * 2 ** 128)).call()
        expected = to_uint(4375 * 2 ** 128 // 1000)
        print(res.call_info.result, expected)
        self.assertEqual(
            tuple(res.call_info.result),
            expected
        )

        res = await self.contract.uint256_mul_div(Q128, to_uint(1000 * 2 ** 128), to_uint(3000 * 2 ** 128)).call()
        expected = to_uint(2 ** 128 // 3)
        self.assertEqual(
            tuple(res.call_info.result),
            expected
        )