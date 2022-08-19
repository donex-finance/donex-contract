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
    MAX_UINT256, MAX_UINT128, assert_revert, add_uint, sub_uint,
    mul_uint, div_rem_uint, to_uint, contract_path,
    felt_to_int, int_to_felt, from_uint, cached_contract, encode_price_sqrt,
    get_max_tick, get_min_tick, TICK_SPACINGS, FeeAmount, init_contract
)

from test_tickmath import (MIN_SQRT_RATIO, MAX_SQRT_RATIO)

Q128 = to_uint(2 ** 128)
MaxUint256 = to_uint(2 ** 256 - 1)

# The path to the contract source code.
CONTRACT_FILE = os.path.join("tests", "../contracts/swap_pool.cairo")

tick_spacing = TICK_SPACINGS[FeeAmount.MEDIUM]
min_tick = get_min_tick(tick_spacing)
max_tick = get_max_tick(tick_spacing)

address = 111

#async def init_contract():
#    begin = time.time()
#    starknet = await Starknet.empty()
#    print('create starknet time:', time.time() - begin)
#    begin = time.time()
#    compiled_contract = compile_starknet_files(
#        [CONTRACT_FILE], debug_info=True, disable_hint_validation=True
#    )
#    print('compile contract time:', time.time() - begin)
#
#    kwargs = {
#        "contract_class": compiled_contract,
#        "constructor_calldata": [tick_spacing, 0]
#        }
#
#    begin = time.time()
#    contract = await starknet.deploy(**kwargs)
#    print('deploy contract time:', time.time() - begin)
#
#    return compiled_contract, contract

class SwapPoolTest(TestCase):

    @classmethod
    async def setUp(cls):
        if not hasattr(cls, 'contract_def'):
            cls.contract_def, cls.contract = await init_contract(CONTRACT_FILE, [tick_spacing, 0])

    def get_state_contract(self):
        _state = self.contract.state.copy()
        new_contract = cached_contract(_state, self.contract_def, self.contract)
        return new_contract

    '''
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

    @pytest.mark.asyncio
    async def test_add_liquidity_failed(self):

        contract = self.get_state_contract()
        await assert_revert(
            contract.add_liquidity(address, int_to_felt(-tick_spacing), tick_spacing, 1).invoke(),
            'swap is locked'
        )

        contract = self.get_state_contract()
        await contract.initialize(encode_price_sqrt(1, 10)).invoke()
        await contract.add_liquidity(address, min_tick, max_tick, 3161).invoke()

        await assert_revert(
            contract.add_liquidity(address, int_to_felt(1), 0, 1).invoke(),
            'tick lower is greater than tick upper'
        )

        await assert_revert(
            contract.add_liquidity(address, int_to_felt(-887273), 0, 1).invoke(),
            'tick is too low'
        )

        await assert_revert(
            contract.add_liquidity(address, 0, 887273, 1).invoke(),
            'tick is too high'
        )

        res = await contract.get_max_liquidity_per_tick().call()
        max_liquidity_gross = res.call_info.result[0]
        await assert_revert(
            contract.add_liquidity(address, min_tick + tick_spacing, max_tick - tick_spacing, max_liquidity_gross + 1).invoke(),
            'update: liq_gross_after > max_liquidity'
        )
        state = contract.state.copy()
        new_contract = cached_contract(state, self.contract_def, self.contract)
        await new_contract.add_liquidity(address, min_tick + tick_spacing, max_tick - tick_spacing, max_liquidity_gross).invoke()

        # fails if total amount at tick exceeds the max
        await contract.add_liquidity(address, min_tick + tick_spacing, max_tick - tick_spacing, 1000).invoke()
        await assert_revert(
            contract.add_liquidity(address, min_tick + tick_spacing, max_tick - tick_spacing, max_liquidity_gross - 1000 + 1).invoke(),
            'update: liq_gross_after > max_liquidity'
        )
        await assert_revert(
            contract.add_liquidity(address, min_tick + tick_spacing * 2, max_tick - tick_spacing, max_liquidity_gross - 1000 + 1).invoke(),
            'update: liq_gross_after > max_liquidity'
        )
        await assert_revert(
            contract.add_liquidity(address, min_tick + tick_spacing, max_tick - tick_spacing * 2, max_liquidity_gross - 1000 + 1).invoke(),
            'update: liq_gross_after > max_liquidity'
        ) 
        
        await contract.add_liquidity(address, min_tick + tick_spacing, max_tick - tick_spacing, max_liquidity_gross - 1000).invoke()

        await assert_revert(
            contract.add_liquidity(address, min_tick + tick_spacing, max_tick - tick_spacing, 0).invoke(),
            ''
        )

    @pytest.mark.asyncio
    async def test_add_liquidity_succuss(self):
        contract = self.get_state_contract()
        price = to_uint(25054144837504793118650146401)
        await contract.initialize(price).invoke()
        res = await contract.add_liquidity(address, min_tick, max_tick, 3161).invoke()
        amount0 = from_uint(res.call_info.result[0: 2])
        amount1 = from_uint(res.call_info.result[2: 4])
        self.assertEqual(amount0, 9996)
        self.assertEqual(amount1, 1000)

        res = await contract.get_cur_slot().call()
        tick = felt_to_int(res.call_info.result[2])
        self.assertEqual(tick, -23028)

        new_contract = cached_contract(contract.state.copy(), self.contract_def, self.contract)
        res = await new_contract.add_liquidity(address, int_to_felt(-22980), 0, 10000).invoke()
        amount0 = from_uint(res.call_info.result[0: 2])
        amount1 = from_uint(res.call_info.result[2: 4])
        self.assertEqual(amount0, 21549)
        self.assertEqual(amount1, 0)

        # max tick with max leverage
        new_contract = cached_contract(contract.state.copy(), self.contract_def, self.contract)
        res = await new_contract.add_liquidity(address, max_tick - tick_spacing, max_tick, 2 ** 102).invoke()
        amount0 = from_uint(res.call_info.result[0: 2])
        amount1 = from_uint(res.call_info.result[2: 4])
        self.assertEqual(amount0, 828011525)
        self.assertEqual(amount1, 0)

        # works for max tick
        new_contract = cached_contract(contract.state.copy(), self.contract_def, self.contract)
        res = await new_contract.add_liquidity(address, int_to_felt(-22980), max_tick, 10000).invoke()
        amount0 = from_uint(res.call_info.result[0: 2])
        amount1 = from_uint(res.call_info.result[2: 4])
        self.assertEqual(amount0, 31549)
        self.assertEqual(amount1, 0)

        # removing works
        new_contract = cached_contract(contract.state.copy(), self.contract_def, self.contract)
        res = await new_contract.add_liquidity(address, int_to_felt(-240), 0, 10000).invoke()
        print('add_liquidity:', res.call_info.result)
        res = await new_contract.remove_liquidity(address, int_to_felt(-240), 0, 10000).invoke()
        print('remove_liquidity:', res.call_info.result)
        res = await new_contract.collect(address, int_to_felt(-240), 0, MAX_UINT128, MAX_UINT128).invoke()
        print('collect:', res.call_info.result)
        amount0 = res.call_info.result[0]
        amount1 = res.call_info.result[1]
        self.assertEqual(amount0, 120)
        self.assertEqual(amount1, 0)

        # adds liquidity to liquidityGross
        new_contract = cached_contract(contract.state.copy(), self.contract_def, self.contract)
        res = await new_contract.add_liquidity(address, int_to_felt(-240), 0, 100).invoke()
        res = await new_contract.get_tick(int_to_felt(-240)).call()
        liquidity_gross = res.call_info.result[0]
        self.assertEqual(liquidity_gross, 100)
        res = await new_contract.get_tick(0).call()
        liquidity_gross = res.call_info.result[0]
        self.assertEqual(liquidity_gross, 100)
        res = await new_contract.get_tick(tick_spacing).call()
        liquidity_gross = res.call_info.result[0]
        self.assertEqual(liquidity_gross, 0)
        res = await new_contract.get_tick(tick_spacing * 2).call()
        liquidity_gross = res.call_info.result[0]
        self.assertEqual(liquidity_gross, 0)

        res = await new_contract.add_liquidity(address, int_to_felt(-240), tick_spacing, 150).invoke()
        res = await new_contract.get_tick(int_to_felt(-240)).call()
        liquidity_gross = res.call_info.result[0]
        self.assertEqual(liquidity_gross, 250)
        res = await new_contract.get_tick(int_to_felt(0)).call()
        liquidity_gross = res.call_info.result[0]
        self.assertEqual(liquidity_gross, 100)
        res = await new_contract.get_tick(tick_spacing).call()
        liquidity_gross = res.call_info.result[0]
        self.assertEqual(liquidity_gross, 150)
        res = await new_contract.get_tick(tick_spacing * 2).call()
        liquidity_gross = res.call_info.result[0]
        self.assertEqual(liquidity_gross, 0)

        res = await new_contract.add_liquidity(address, 0, tick_spacing * 2, 60).invoke()
        res = await new_contract.get_tick(int_to_felt(-240)).call()
        liquidity_gross = res.call_info.result[0]
        self.assertEqual(liquidity_gross, 250)
        res = await new_contract.get_tick(int_to_felt(0)).call()
        liquidity_gross = res.call_info.result[0]
        self.assertEqual(liquidity_gross, 160)
        res = await new_contract.get_tick(tick_spacing).call()
        liquidity_gross = res.call_info.result[0]
        self.assertEqual(liquidity_gross, 150)
        res = await new_contract.get_tick(tick_spacing * 2).call()
        liquidity_gross = res.call_info.result[0]
        self.assertEqual(liquidity_gross, 60)

        # removes liquidity from liquidityGross
        new_contract = cached_contract(contract.state.copy(), self.contract_def, self.contract)
        res = await new_contract.add_liquidity(address, int_to_felt(-240), 0, 100).invoke()
        res = await new_contract.add_liquidity(address, int_to_felt(-240), 0, 40).invoke()
        res = await new_contract.remove_liquidity(address, int_to_felt(-240), 0, 90).invoke()
        res = await new_contract.get_tick(int_to_felt(-240)).call()
        liquidity_gross = res.call_info.result[0]
        self.assertEqual(liquidity_gross, 50)
        res = await new_contract.get_tick(int_to_felt(0)).call()
        liquidity_gross = res.call_info.result[0]
        self.assertEqual(liquidity_gross, 50)

        # removes liquidity from liquidityGross
        new_contract = cached_contract(contract.state.copy(), self.contract_def, self.contract)
        res = await new_contract.add_liquidity(address, int_to_felt(-240), 0, 100).invoke()
        res = await new_contract.add_liquidity(address, int_to_felt(-240), 0, 40).invoke()
        res = await new_contract.remove_liquidity(address, int_to_felt(-240), 0, 90).invoke()
        res = await new_contract.get_tick(int_to_felt(-240)).call()
        liquidity_gross = res.call_info.result[0]
        self.assertEqual(liquidity_gross, 50)
        res = await new_contract.get_tick(int_to_felt(0)).call()
        liquidity_gross = res.call_info.result[0]
        self.assertEqual(liquidity_gross, 50)

        # clears tick upper if last position is removed
        new_contract = cached_contract(contract.state.copy(), self.contract_def, self.contract)
        res = await new_contract.add_liquidity(address, int_to_felt(-240), 0, 100).invoke()
        res = await new_contract.remove_liquidity(address, int_to_felt(-240), 0, 100).invoke()
        res = await new_contract.get_tick(int_to_felt(0)).call()
        liquidity_gross = res.call_info.result[0]
        fee_growth_outside0 = from_uint(res.call_info.result[2: 4])
        fee_growth_outside1 = from_uint(res.call_info.result[4: 6])
        self.assertEqual(liquidity_gross, 0)
        self.assertEqual(fee_growth_outside0, 0)
        self.assertEqual(fee_growth_outside1, 0)
        
        # only clears the tick that is not used at all
        new_contract = cached_contract(contract.state.copy(), self.contract_def, self.contract)
        res = await new_contract.add_liquidity(address, int_to_felt(-240), 0, 100).invoke()
        res = await new_contract.add_liquidity(address, int_to_felt(-tick_spacing), 0, 250).invoke()
        res = await new_contract.remove_liquidity(address, int_to_felt(-240), 0, 100).invoke()
        res = await new_contract.get_tick(int_to_felt(-240)).call()
        liquidity_gross = res.call_info.result[0]
        fee_growth_outside0 = from_uint(res.call_info.result[2: 4])
        fee_growth_outside1 = from_uint(res.call_info.result[4: 6])
        self.assertEqual(liquidity_gross, 0)
        self.assertEqual(fee_growth_outside0, 0)
        self.assertEqual(fee_growth_outside1, 0)
        res = await new_contract.get_tick(int_to_felt(-tick_spacing)).call()
        liquidity_gross = res.call_info.result[0]
        fee_growth_outside0 = from_uint(res.call_info.result[2: 4])
        fee_growth_outside1 = from_uint(res.call_info.result[4: 6])
        self.assertEqual(liquidity_gross, 250)
        self.assertEqual(fee_growth_outside0, 0)
        self.assertEqual(fee_growth_outside1, 0)
    '''