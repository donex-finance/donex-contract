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
    felt_to_int, from_uint
)

Q128 = to_uint(2 ** 128)
MaxUint256 = to_uint(2 ** 256 - 1)

# The path to the contract source code.
CONTRACT_FILE = os.path.join("tests", "mocks/bitmath_mock.cairo")

class BitmathTest(TestCase):
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
    async def test_most_significant_bit(self):
        await assert_revert(
            self.contract.most_significant_bit(to_uint(0)).call(),
            ""
        )

        res = await self.contract.most_significant_bit(to_uint(1)).call()
        self.assertEqual(
            res.call_info.result[0],
            0
        )

        res = await self.contract.most_significant_bit(to_uint(2)).call()
        self.assertEqual(
            res.call_info.result[0],
            1
        )

        for i in range(255):
            res = await self.contract.most_significant_bit(to_uint(2 ** i)).call()
            self.assertEqual(
                res.call_info.result[0],
                i
            )

        res = await self.contract.most_significant_bit(to_uint(2 ** 256 - 1)).call()
        self.assertEqual(
            res.call_info.result[0],
            255
        )

    @pytest.mark.asyncio
    async def test_least_significant_bit(self):
        await assert_revert(
            self.contract.least_significant_bit(to_uint(0)).call(),
            ""
        )

        res = await self.contract.least_significant_bit(to_uint(1)).call()
        self.assertEqual(
            res.call_info.result[0],
            0
        )

        res = await self.contract.least_significant_bit(to_uint(2)).call()
        self.assertEqual(
            res.call_info.result[0],
            1
        )

        for i in range(255):
            res = await self.contract.least_significant_bit(to_uint(2 ** i)).call()
            self.assertEqual(
                res.call_info.result[0],
                i
            )

        res = await self.contract.least_significant_bit(to_uint(2 ** 256 - 1)).call()
        self.assertEqual(
            res.call_info.result[0],
            0
        )