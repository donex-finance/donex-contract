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
    MAX_UINT128, assert_revert, add_uint, sub_uint,
    mul_uint, div_rem_uint, to_uint, contract_path,
    felt_to_int, from_uint, int_to_felt, cached_contract,
    TICK_SPACINGS, FeeAmount
)
from decimal import *

# The path to the contract source code.
CONTRACT_FILE = os.path.join("tests", "mocks/tick_mgr_mock.cairo")

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
    async def test_get_max_liquidity_per_tick(self):
        
        contract = self.get_state_contract()

        res = await contract.get_max_liquidity_per_tick(TICK_SPACINGS[FeeAmount.LOW]).call()
        self.assertEqual(res.call_info.result[0], 1917569901783203986719870431555990)

        res = await contract.get_max_liquidity_per_tick(TICK_SPACINGS[FeeAmount.MEDIUM]).call()
        self.assertEqual(res.call_info.result[0], 11505743598341114571880798222544994)

        res = await contract.get_max_liquidity_per_tick(TICK_SPACINGS[FeeAmount.HIGH]).call()
        self.assertEqual(res.call_info.result[0], 38350317471085141830651933667504588)

        res = await contract.get_max_liquidity_per_tick(887272).call()
        self.assertEqual(res.call_info.result[0], MAX_UINT128 // 3)

        res = await contract.get_max_liquidity_per_tick(2302).call()
        self.assertEqual(res.call_info.result[0], 441351967472034323558203122479595605)

    @pytest.mark.asyncio
    async def test_get_fee_growth_inside(self):
        
        contract = self.get_state_contract()

        res = await contract.get_fee_growth_inside(int_to_felt(-2), 2, 0, to_uint(15), to_uint(15)).call()
        feeGrowthInside0X128 = from_uint(res.call_info.result[0: 2])
        feeGrowthInside1X128 = from_uint(res.call_info.result[2: 4])
        self.assertEqual(feeGrowthInside0X128, 15)
        self.assertEqual(feeGrowthInside1X128, 15)

        res = await contract.get_fee_growth_inside(int_to_felt(-2), 2, 4, to_uint(15), to_uint(15)).call()
        feeGrowthInside0X128 = from_uint(res.call_info.result[0: 2])
        feeGrowthInside1X128 = from_uint(res.call_info.result[2: 4])
        self.assertEqual(feeGrowthInside0X128, 0)
        self.assertEqual(feeGrowthInside1X128, 0)

        res = await contract.get_fee_growth_inside(int_to_felt(-2), 2, int_to_felt(4), to_uint(15), to_uint(15)).call()
        feeGrowthInside0X128 = from_uint(res.call_info.result[0: 2])
        feeGrowthInside1X128 = from_uint(res.call_info.result[2: 4])
        self.assertEqual(feeGrowthInside0X128, 0)
        self.assertEqual(feeGrowthInside1X128, 0)

        res = await contract.set_tick(2, (0, 0, to_uint(2), to_uint(3), 1)).invoke()
        res = await contract.get_fee_growth_inside(int_to_felt(-2), 2, int_to_felt(0), to_uint(15), to_uint(15)).call()
        feeGrowthInside0X128 = from_uint(res.call_info.result[0: 2])
        feeGrowthInside1X128 = from_uint(res.call_info.result[2: 4])
        self.assertEqual(feeGrowthInside0X128, 13)
        self.assertEqual(feeGrowthInside1X128, 12)

        contract = self.get_state_contract()
        res = await contract.set_tick(int_to_felt(-2), (0, 0, to_uint(2), to_uint(3), 1)).invoke()
        res = await contract.get_fee_growth_inside(int_to_felt(-2), 2, int_to_felt(0), to_uint(15), to_uint(15)).call()
        feeGrowthInside0X128 = from_uint(res.call_info.result[0: 2])
        feeGrowthInside1X128 = from_uint(res.call_info.result[2: 4])
        self.assertEqual(feeGrowthInside0X128, 13)
        self.assertEqual(feeGrowthInside1X128, 12)

        contract = self.get_state_contract()
        res = await contract.set_tick(int_to_felt(-2), (0, 0, to_uint(2), to_uint(3), 1)).invoke()
        res = await contract.set_tick(int_to_felt(2), (0, 0, to_uint(4), to_uint(1), 1)).invoke()
        res = await contract.get_fee_growth_inside(int_to_felt(-2), 2, int_to_felt(0), to_uint(15), to_uint(15)).call()
        feeGrowthInside0X128 = from_uint(res.call_info.result[0: 2])
        feeGrowthInside1X128 = from_uint(res.call_info.result[2: 4])
        self.assertEqual(feeGrowthInside0X128, 9)
        self.assertEqual(feeGrowthInside1X128, 11)

        contract = self.get_state_contract()
        res = await contract.set_tick(int_to_felt(-2), (0, 0, to_uint(2 ** 256 - 1 - 3), to_uint(2 ** 256 - 1 - 2), 1)).invoke()
        res = await contract.set_tick(int_to_felt(2), (0, 0, to_uint(3), to_uint(5), 1)).invoke()
        res = await contract.get_fee_growth_inside(int_to_felt(-2), 2, int_to_felt(0), to_uint(15), to_uint(15)).call()
        feeGrowthInside0X128 = from_uint(res.call_info.result[0: 2])
        feeGrowthInside1X128 = from_uint(res.call_info.result[2: 4])
        self.assertEqual(feeGrowthInside0X128, 16)
        self.assertEqual(feeGrowthInside1X128, 13)

    @pytest.mark.asyncio
    async def test_update(self):
        contract = self.get_state_contract()
        res = await contract.update(0, 0, 1, to_uint(0), to_uint(0), 0, 3).invoke()
        self.assertEqual(res.call_info.result[0], 1)

        contract = self.get_state_contract()
        res = await contract.update(0, 0, 1, to_uint(0), to_uint(0), 0, 3).invoke()
        res = await contract.update(0, 0, 1, to_uint(0), to_uint(0), 0, 3).invoke()
        self.assertEqual(res.call_info.result[0], 0)

        contract = self.get_state_contract()
        res = await contract.update(0, 0, 1, to_uint(0), to_uint(0), 0, 3).invoke()
        res = await contract.update(0, 0, int_to_felt(-1), to_uint(0), to_uint(0), 0, 3).invoke()
        self.assertEqual(res.call_info.result[0], 1)

        contract = self.get_state_contract()
        res = await contract.update(0, 0, 2, to_uint(0), to_uint(0), 0, 3).invoke()
        res = await contract.update(0, 0, int_to_felt(-1), to_uint(0), to_uint(0), 0, 3).invoke()
        self.assertEqual(res.call_info.result[0], 0)

        contract = self.get_state_contract()
        res = await contract.update(0, 0, 2, to_uint(0), to_uint(0), 0, 3).invoke()
        res = await contract.update(0, 0, 1, to_uint(0), to_uint(0), 1, 3).invoke()
        await assert_revert(
            contract.update(0, 0, 1, to_uint(0), to_uint(0), 0, 3).invoke(),
            'update: liq_gross_after > max_liquidity'
        )

        contract = self.get_state_contract()
        res = await contract.update(0, 0, 2, to_uint(0), to_uint(0), 0, 10).invoke()
        res = await contract.update(0, 0, 1, to_uint(0), to_uint(0), 1, 10).invoke()
        res = await contract.update(0, 0, 3, to_uint(0), to_uint(0), 1, 10).invoke()
        res = await contract.update(0, 0, 1, to_uint(0), to_uint(0), 0, 10).invoke()
        res = await contract.get_tick(0).call()
        print('res', res.call_info.result)
        liquidityGross = res.call_info.result[0]
        liquidityNet = felt_to_int(res.call_info.result[1])
        self.assertEqual(liquidityGross, 2 + 1 + 3 + 1)
        self.assertEqual(liquidityNet, 2 - 1 - 3 + 1)

        contract = self.get_state_contract()
        res = await contract.update(0, 0, MAX_UINT128 // 2 - 1, to_uint(0), to_uint(0), 0, MAX_UINT128).invoke()
        print('res', res.call_info.result)
        res = await contract.update(0, 0, MAX_UINT128 // 2 - 1, to_uint(0), to_uint(0), 0, MAX_UINT128).invoke()
        print('res', res.call_info.result)
        #TODO
        #await assert_revert(
        #    contract.update(0, 0, MAX_UINT128 // 2 - 1, to_uint(0), to_uint(0), 0, MAX_UINT128).invoke()
        #)

        contract = self.get_state_contract()
        res = await contract.update(1, 1, 1, to_uint(1), to_uint(2), 0, MAX_UINT128).invoke()
        res = await contract.get_tick(1).call()
        liquidityGross = res.call_info.result[0]
        liquidityNet = res.call_info.result[1]
        feeGrowthOutside0X128 = from_uint(res.call_info.result[2: 4])
        feeGrowthOutside1X128 = from_uint(res.call_info.result[4: 6])
        initialized = res.call_info.result[6]
        self.assertEqual(feeGrowthOutside0X128, 1)
        self.assertEqual(feeGrowthOutside1X128, 2)
        self.assertEqual(initialized, 1)
        
        contract = self.get_state_contract()
        res = await contract.update(1, 1, 1, to_uint(1), to_uint(2), 0, MAX_UINT128).invoke()
        res = await contract.update(1, 1, 1, to_uint(6), to_uint(7), 0, MAX_UINT128).invoke()
        res = await contract.get_tick(1).call()
        liquidityGross = res.call_info.result[0]
        liquidityNet = res.call_info.result[1]
        feeGrowthOutside0X128 = from_uint(res.call_info.result[2: 4])
        feeGrowthOutside1X128 = from_uint(res.call_info.result[4: 6])
        initialized = res.call_info.result[6]
        self.assertEqual(feeGrowthOutside0X128, 1)
        self.assertEqual(feeGrowthOutside1X128, 2)
        self.assertEqual(initialized, 1)

        contract = self.get_state_contract()
        res = await contract.update(2, 1, 1, to_uint(1), to_uint(2), 0, MAX_UINT128).invoke()
        res = await contract.get_tick(2).call()
        liquidityGross = res.call_info.result[0]
        liquidityNet = res.call_info.result[1]
        feeGrowthOutside0X128 = from_uint(res.call_info.result[2: 4])
        feeGrowthOutside1X128 = from_uint(res.call_info.result[4: 6])
        initialized = res.call_info.result[6]
        self.assertEqual(feeGrowthOutside0X128, 0)
        self.assertEqual(feeGrowthOutside1X128, 0)
        self.assertEqual(initialized, 1)