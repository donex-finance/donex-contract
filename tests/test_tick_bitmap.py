"""contract.cairo test file."""
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
    felt_to_int, from_uint, int_to_felt, cached_contract
)
from decimal import *

# The path to the contract source code.
CONTRACT_FILE = os.path.join("tests", "mocks/tick_bitmap_mock.cairo")

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

        cls.contract_def = compiled_contract
        cls.contract = await cls.starknet.deploy(**kwargs)

    def get_state_contract(self):
        _state = self.contract.state.copy()
        contract = cached_contract(_state, self.contract_def, self.contract)
        return contract

    @pytest.mark.asyncio
    async def test_flip_tick(self):
        
        contract = self.get_state_contract()
        tick = int_to_felt(-230)
        await self.contract.flip_tick(tick).execute()

        res = await self.contract.is_initialized(tick).call()
        self.assertEqual(res.call_info.result[0], 1)

        tick = int_to_felt(-231)
        res = await self.contract.is_initialized(tick).call()
        self.assertEqual(res.call_info.result[0], 0)

        tick = int_to_felt(-229)
        res = await self.contract.is_initialized(tick).call()
        self.assertEqual(res.call_info.result[0], 0)

        tick = int_to_felt(-230 + 256)
        res = await self.contract.is_initialized(tick).call()
        self.assertEqual(res.call_info.result[0], 0)

        tick = int_to_felt(-230 - 256)
        res = await self.contract.is_initialized(tick).call()
        self.assertEqual(res.call_info.result[0], 0)

        tick = int_to_felt(-230)
        await self.contract.flip_tick(tick).execute()

        res = await self.contract.is_initialized(tick).call()
        self.assertEqual(res.call_info.result[0], 0)

        tick = int_to_felt(-231)
        res = await self.contract.is_initialized(tick).call()
        self.assertEqual(res.call_info.result[0], 0)

        tick = int_to_felt(-229)
        res = await self.contract.is_initialized(tick).call()
        self.assertEqual(res.call_info.result[0], 0)

        tick = int_to_felt(-230 + 256)
        res = await self.contract.is_initialized(tick).call()
        self.assertEqual(res.call_info.result[0], 0)

        tick = int_to_felt(-230 - 256)
        res = await self.contract.is_initialized(tick).call()
        self.assertEqual(res.call_info.result[0], 0)

    @pytest.mark.asyncio
    async def test_next_initialize(self):
        contract = self.get_state_contract()

        inits = [-200, -55, -4, 70, 78, 84, 139, 240, 535]
        for t in inits:
            await contract.flip_tick(int_to_felt(t)).execute()

        res = await contract.next_valid_tick_within_one_word(78, 1, 0).call()
        self.assertEqual(res.call_info.result[0], 84)
        self.assertEqual(res.call_info.result[1], 1)

        res = await contract.next_valid_tick_within_one_word(int_to_felt(-55), 1, 0).call()
        self.assertEqual(felt_to_int(res.call_info.result[0]), -4)
        self.assertEqual(res.call_info.result[1], 1)

        res = await contract.next_valid_tick_within_one_word(77, 1, 0).call()
        self.assertEqual(res.call_info.result[0], 78)
        self.assertEqual(res.call_info.result[1], 1)

        res = await contract.next_valid_tick_within_one_word(int_to_felt(-56), 1, 0).call()
        self.assertEqual(felt_to_int(res.call_info.result[0]), -55)
        self.assertEqual(res.call_info.result[1], 1)

        res = await contract.next_valid_tick_within_one_word(255, 1, 0).call()
        print(res.call_info.result)
        self.assertEqual(res.call_info.result[0], 511)
        self.assertEqual(res.call_info.result[1], 0)

        res = await contract.next_valid_tick_within_one_word(int_to_felt(-257), 1, 0).call()
        self.assertEqual(felt_to_int(res.call_info.result[0]), -200)
        self.assertEqual(res.call_info.result[1], 1)

        await contract.flip_tick(int_to_felt(340)).execute()
        res = await contract.next_valid_tick_within_one_word(int_to_felt(328), 1, 0).call()
        self.assertEqual(felt_to_int(res.call_info.result[0]), 340)
        self.assertEqual(res.call_info.result[1], 1)
        await contract.flip_tick(int_to_felt(340)).execute()

        res = await contract.next_valid_tick_within_one_word(int_to_felt(508), 1, 0).call()
        self.assertEqual(felt_to_int(res.call_info.result[0]), 511)
        self.assertEqual(res.call_info.result[1], 0)

        res = await contract.next_valid_tick_within_one_word(int_to_felt(255), 1, 0).call()
        self.assertEqual(felt_to_int(res.call_info.result[0]), 511)
        self.assertEqual(res.call_info.result[1], 0)

        res = await contract.next_valid_tick_within_one_word(int_to_felt(383), 1, 0).call()
        self.assertEqual(felt_to_int(res.call_info.result[0]), 511)
        self.assertEqual(res.call_info.result[1], 0)

        # lte = true
        res = await contract.next_valid_tick_within_one_word(int_to_felt(78), 1, 1).call()
        self.assertEqual(felt_to_int(res.call_info.result[0]), 78)
        self.assertEqual(res.call_info.result[1], 1)

        res = await contract.next_valid_tick_within_one_word(int_to_felt(79), 1, 1).call()
        self.assertEqual(felt_to_int(res.call_info.result[0]), 78)
        self.assertEqual(res.call_info.result[1], 1)

        res = await contract.next_valid_tick_within_one_word(int_to_felt(258), 1, 1).call()
        self.assertEqual(felt_to_int(res.call_info.result[0]), 256)
        self.assertEqual(res.call_info.result[1], 0)

        res = await contract.next_valid_tick_within_one_word(int_to_felt(256), 1, 1).call()
        self.assertEqual(felt_to_int(res.call_info.result[0]), 256)
        self.assertEqual(res.call_info.result[1], 0)

        res = await contract.next_valid_tick_within_one_word(int_to_felt(72), 1, 1).call()
        self.assertEqual(felt_to_int(res.call_info.result[0]), 70)
        self.assertEqual(res.call_info.result[1], 1)

        res = await contract.next_valid_tick_within_one_word(int_to_felt(-257), 1, 1).call()
        self.assertEqual(felt_to_int(res.call_info.result[0]), -512)
        self.assertEqual(res.call_info.result[1], 0)

        res = await contract.next_valid_tick_within_one_word(int_to_felt(1023), 1, 1).call()
        self.assertEqual(felt_to_int(res.call_info.result[0]), 768)
        self.assertEqual(res.call_info.result[1], 0)

        res = await contract.next_valid_tick_within_one_word(int_to_felt(900), 1, 1).call()
        self.assertEqual(felt_to_int(res.call_info.result[0]), 768)
        self.assertEqual(res.call_info.result[1], 0)

        await contract.flip_tick(329).execute()
        res = await contract.next_valid_tick_within_one_word(int_to_felt(456), 1, 1).call()
        self.assertEqual(felt_to_int(res.call_info.result[0]), 329)
        self.assertEqual(res.call_info.result[1], 1)