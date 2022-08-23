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
    get_max_tick, get_min_tick, TICK_SPACINGS, FeeAmount, init_contract,
    expand_to_18decimals
)

from test_tickmath import (MIN_SQRT_RATIO, MAX_SQRT_RATIO)

Q128 = to_uint(2 ** 128)
MaxUint256 = to_uint(2 ** 256 - 1)

# The path to the contract source code.
CONTRACT_FILE = os.path.join("tests", "../contracts/swap_pool.cairo")

FEE = FeeAmount.MEDIUM
tick_spacing = TICK_SPACINGS[FEE]
min_tick = get_min_tick(tick_spacing)
max_tick = get_max_tick(tick_spacing)

address = 111
other_address = 222

async def swap_exact0_for1(contract, amount, address):
    sqrt_price_limit = MIN_SQRT_RATIO + 1
    res = await contract.swap(address, 1, to_uint(amount), to_uint(sqrt_price_limit)).invoke()
    return res

async def swap_exact1_for0(contract, amount, address):
    sqrt_price_limit = MAX_SQRT_RATIO - 1
    res = await contract.swap(address, 0, to_uint(amount), to_uint(sqrt_price_limit)).invoke()
    return res

async def initialize_at_zero_tick(contract):
    res = await contract.get_tick_spacing().call()
    tick_spacing = res.call_info.result[0]
    min_tick, max_tick = get_min_tick(tick_spacing), get_max_tick(tick_spacing)
    await contract.initialize(encode_price_sqrt(1, 1)).invoke()
    await contract.add_liquidity(address, min_tick, max_tick, expand_to_18decimals(2)).invoke()

class SwapPoolTest(TestCase):

    @classmethod
    async def setUp(cls):
        if not hasattr(cls, 'contract_def'):
            cls.contract_def, cls.contract = await init_contract(CONTRACT_FILE, [tick_spacing, FEE])

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
            contract.add_liquidity(address, -3, 3, expand_to_18decimals(2)).invoke(),
            "tick must be multiples of tick_spacing"
        )

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

        # price within range: transfers current price of both tokens
        new_contract = cached_contract(contract.state.copy(), self.contract_def, self.contract)
        res = await new_contract.add_liquidity(address, int_to_felt(min_tick + tick_spacing), max_tick - tick_spacing, 100).invoke()
        amount0 = from_uint(res.call_info.result[0: 2])
        amount1 = from_uint(res.call_info.result[2: 4])
        self.assertEqual(amount0, 317)
        self.assertEqual(amount1, 32)

        # initializes lower tick
        res = await new_contract.get_tick(int_to_felt(min_tick + tick_spacing)).call()
        liquidity_gross = res.call_info.result[0]
        self.assertEqual(liquidity_gross, 100)
        res = await new_contract.get_tick(int_to_felt(max_tick - tick_spacing)).call()
        liquidity_gross = res.call_info.result[0]
        self.assertEqual(liquidity_gross, 100)

        # initializes upper tick
        new_contract = cached_contract(contract.state.copy(), self.contract_def, self.contract)
        res = await new_contract.add_liquidity(address, int_to_felt(min_tick), max_tick, 10000).invoke()
        amount0 = from_uint(res.call_info.result[0: 2])
        amount1 = from_uint(res.call_info.result[2: 4])
        self.assertEqual(amount0, 31623)
        self.assertEqual(amount1, 3163)

        # removing works
        new_contract = cached_contract(contract.state.copy(), self.contract_def, self.contract)
        res = await new_contract.add_liquidity(address, int_to_felt(min_tick + tick_spacing), max_tick - tick_spacing, 100).invoke()
        res = await new_contract.remove_liquidity(address, int_to_felt(min_tick + tick_spacing), max_tick - tick_spacing, 100).invoke()
        res = await new_contract.collect(address, int_to_felt(min_tick + tick_spacing), max_tick - tick_spacing, MAX_UINT128, MAX_UINT128).invoke()
        amount0 = res.call_info.result[0]
        amount1 = res.call_info.result[1]
        self.assertEqual(amount0, 316)
        self.assertEqual(amount1, 31)

        # transfers token1 only
        new_contract = cached_contract(contract.state.copy(), self.contract_def, self.contract)
        res = await new_contract.add_liquidity(address, int_to_felt(-46080), int_to_felt(-23040), 10000).invoke()
        amount0 = from_uint(res.call_info.result[0: 2])
        amount1 = from_uint(res.call_info.result[2: 4])
        self.assertEqual(amount0, 0)
        self.assertEqual(amount1, 2162)

        # min tick with max leverage
        new_contract = cached_contract(contract.state.copy(), self.contract_def, self.contract)
        res = await new_contract.add_liquidity(address, int_to_felt(min_tick), int_to_felt(min_tick + tick_spacing), 2 ** 102).invoke()
        amount0 = from_uint(res.call_info.result[0: 2])
        amount1 = from_uint(res.call_info.result[2: 4])
        self.assertEqual(amount0, 0)
        self.assertEqual(amount1, 828011520)

        # works for min tick
        new_contract = cached_contract(contract.state.copy(), self.contract_def, self.contract)
        res = await new_contract.add_liquidity(address, int_to_felt(min_tick), int_to_felt(-23040), 10000).invoke()
        amount0 = from_uint(res.call_info.result[0: 2])
        amount1 = from_uint(res.call_info.result[2: 4])
        self.assertEqual(amount0, 0)
        self.assertEqual(amount1, 3161)

        # removing works
        new_contract = cached_contract(contract.state.copy(), self.contract_def, self.contract)
        res = await new_contract.add_liquidity(address, int_to_felt(-46080), int_to_felt(-46020), 10000).invoke()
        res = await new_contract.remove_liquidity(address, int_to_felt(-46080), int_to_felt(-46020), 10000).invoke()
        res = await new_contract.collect(address, int_to_felt(-46080), int_to_felt(-46020), MAX_UINT128, MAX_UINT128).invoke()
        amount0 = res.call_info.result[0]
        amount1 = res.call_info.result[1]
        self.assertEqual(amount0, 0)
        self.assertEqual(amount1, 3)


    @pytest.mark.asyncio
    async def test_protocol_fee(self):
        contract = self.get_state_contract()
        price = to_uint(25054144837504793118650146401)
        await contract.initialize(price).invoke()
        res = await contract.add_liquidity(address, min_tick, max_tick, 3161).invoke()

        # protocol fees accumulate as expected during swap
        new_contract = cached_contract(contract.state.copy(), self.contract_def, self.contract)
        await new_contract.set_fee_protocol(6, 6).invoke()
        res = await new_contract.add_liquidity(address, int_to_felt(min_tick + tick_spacing), max_tick - tick_spacing, expand_to_18decimals(1)).invoke()
        print('add_liquidity', res.call_info.result)
        res = await swap_exact0_for1(new_contract, expand_to_18decimals(1) // 10, address)
        print('swap_exact0_for1', res.call_info.result)
        res = await swap_exact1_for0(new_contract, expand_to_18decimals(1) // 100, address)
        print('swap_exact1_for0', res.call_info.result)
        res = await new_contract.get_protocol_fees().call()
        token0_fee = from_uint(res.call_info.result[0: 2])
        token1_fee = from_uint(res.call_info.result[2: 4]) 
        self.assertEqual(token0_fee, 50000000000000)
        self.assertEqual(token1_fee, 5000000000000)

        # positions are protected before protocol fee is turned on
        new_contract = cached_contract(contract.state.copy(), self.contract_def, self.contract)
        res = await new_contract.add_liquidity(address, int_to_felt(min_tick + tick_spacing), max_tick - tick_spacing, expand_to_18decimals(1)).invoke()
        res = await swap_exact0_for1(new_contract, expand_to_18decimals(1) // 10, address)
        res = await swap_exact1_for0(new_contract, expand_to_18decimals(1) // 100, address)
        res = await new_contract.get_protocol_fees().call()
        token0_fee = from_uint(res.call_info.result[0: 2])
        token1_fee = from_uint(res.call_info.result[2: 4]) 
        self.assertEqual(token0_fee, 0)
        self.assertEqual(token1_fee, 0)

        await new_contract.set_fee_protocol(6, 6).invoke()
        res = await new_contract.get_protocol_fees().call()
        token0_fee = from_uint(res.call_info.result[0: 2])
        token1_fee = from_uint(res.call_info.result[2: 4]) 
        self.assertEqual(token0_fee, 0)
        self.assertEqual(token1_fee, 0)

        # poke is not allowed on uninitialized position
        new_contract = cached_contract(contract.state.copy(), self.contract_def, self.contract)
        res = await new_contract.add_liquidity(other_address, int_to_felt(min_tick + tick_spacing), max_tick - tick_spacing, expand_to_18decimals(1)).invoke()
        res = await swap_exact0_for1(new_contract, expand_to_18decimals(1) // 10, address)
        res = await swap_exact1_for0(new_contract, expand_to_18decimals(1) // 100, address)

        await assert_revert(
            new_contract.remove_liquidity(address, int_to_felt(min_tick + tick_spacing), max_tick - tick_spacing, 0).invoke(),
            ""
        )
        res = await new_contract.add_liquidity(address, int_to_felt(min_tick + tick_spacing), max_tick - tick_spacing, 1).invoke()

        res = await new_contract.get_position(address, int_to_felt(min_tick + tick_spacing), max_tick - tick_spacing).call()
        liquidity = res.call_info.result[0]
        fee_growth_inside0_x128 = from_uint(res.call_info.result[1: 3])
        fee_growth_inside1_x128 = from_uint(res.call_info.result[3: 5])
        tokens_owed0 = res.call_info.result[5]
        tokens_owed1 = res.call_info.result[6]
        self.assertEqual(liquidity, 1)
        self.assertEqual(fee_growth_inside0_x128, 102084710076281216349243831104605583)
        self.assertEqual(fee_growth_inside1_x128, 10208471007628121634924383110460558)
        self.assertEqual(tokens_owed0, 0)
        self.assertEqual(tokens_owed1, 0)

        await new_contract.remove_liquidity(address, int_to_felt(min_tick + tick_spacing), max_tick - tick_spacing, 1).invoke()
        res = await new_contract.get_position(address, int_to_felt(min_tick + tick_spacing), max_tick - tick_spacing).call()
        liquidity = res.call_info.result[0]
        fee_growth_inside0_x128 = from_uint(res.call_info.result[1: 3])
        fee_growth_inside1_x128 = from_uint(res.call_info.result[3: 5])
        tokens_owed0 = res.call_info.result[5]
        tokens_owed1 = res.call_info.result[6]
        self.assertEqual(liquidity, 0)
        self.assertEqual(fee_growth_inside0_x128, 102084710076281216349243831104605583)
        self.assertEqual(fee_growth_inside1_x128, 10208471007628121634924383110460558)
        self.assertEqual(tokens_owed0, 3)
        self.assertEqual(tokens_owed1, 0)

    async def check_tick_is_clear(self, contract, tick):
        res = await contract.get_tick(int_to_felt(tick)).call()
        liquidity_gross = res.call_info.result[0]
        liquidity_net = res.call_info.result[1]
        fee_growth_outside0 = from_uint(res.call_info.result[2: 4])
        fee_growth_outside1 = from_uint(res.call_info.result[4: 6])
        self.assertEqual(liquidity_gross, 0)
        self.assertEqual(liquidity_net, 0)
        self.assertEqual(fee_growth_outside0, 0)
        self.assertEqual(fee_growth_outside1, 0)

    async def check_tick_is_not_clear(self, contract, tick):
        res = await contract.get_tick(int_to_felt(tick)).call()
        liquidity_gross = res.call_info.result[0]
        self.assertEqual(liquidity_gross != 0, True)

    @pytest.mark.asyncio
    async def test_remove_liquidity(self):

        contract = self.get_state_contract()
        price = encode_price_sqrt(1, 1)
        await contract.initialize(price).invoke()
        res = await contract.add_liquidity(address, int_to_felt(min_tick), max_tick, expand_to_18decimals(2)).invoke()

        # does not clear the position fee growth snapshot if no more liquidity
        new_contract = cached_contract(contract.state.copy(), self.contract_def, self.contract)
        res = await new_contract.add_liquidity(other_address, int_to_felt(min_tick), max_tick, expand_to_18decimals(1)).invoke()
        print('add_liquidity', res.call_info.result)
        res = await swap_exact0_for1(new_contract, expand_to_18decimals(1), address)
        print('min_tick', min_tick, 'max_tick', max_tick)
        print('swap_exact0_for1:', res.call_info.result)
        res = await swap_exact1_for0(new_contract, expand_to_18decimals(1), address)
        print('swap_exact1_for0:', res.call_info.result)

        res = await new_contract.remove_liquidity(other_address, int_to_felt(min_tick), max_tick, expand_to_18decimals(1)).invoke()
        res = await new_contract.get_position(other_address, int_to_felt(min_tick), max_tick).call()
        liquidity = res.call_info.result[0]
        fee_growth_inside0_x128 = from_uint(res.call_info.result[1: 3])
        fee_growth_inside1_x128 = from_uint(res.call_info.result[3: 5])
        tokens_owed0 = res.call_info.result[5]
        tokens_owed1 = res.call_info.result[6]
        self.assertEqual(liquidity, 0)
        self.assertEqual(fee_growth_inside0_x128, 340282366920938463463374607431768211)
        self.assertEqual(fee_growth_inside1_x128, 340282366920938576890830247744589365)
        self.assertNotEqual(tokens_owed0, 0)
        self.assertNotEqual(tokens_owed1, 0)

        # clears the tick if its the last position using it
        tick_lower, tick_upper = min_tick + tick_spacing, max_tick - tick_spacing
        new_contract = cached_contract(contract.state.copy(), self.contract_def, self.contract)
        res = await new_contract.add_liquidity(address, tick_lower, tick_upper, 1).invoke()
        res = await swap_exact0_for1(new_contract, expand_to_18decimals(1), address)
        res = await new_contract.remove_liquidity(address, tick_lower, tick_upper, 1).invoke()
        await self.check_tick_is_clear(new_contract, tick_lower)
        await self.check_tick_is_clear(new_contract, tick_upper)

        # clears only the lower tick if upper is still used
        new_contract = cached_contract(contract.state.copy(), self.contract_def, self.contract)
        res = await new_contract.add_liquidity(address, tick_lower, tick_upper, 1).invoke()
        res = await new_contract.add_liquidity(address, tick_lower + tick_spacing, tick_upper, 1).invoke()
        res = await swap_exact0_for1(new_contract, expand_to_18decimals(1), address)
        res = await new_contract.remove_liquidity(address, tick_lower, tick_upper, 1).invoke()
        await self.check_tick_is_clear(new_contract, tick_lower)
        await self.check_tick_is_not_clear(new_contract, tick_upper)

        # clears only the upper tick if lower is still used
        new_contract = cached_contract(contract.state.copy(), self.contract_def, self.contract)
        res = await new_contract.add_liquidity(address, tick_lower, tick_upper, 1).invoke()
        res = await new_contract.add_liquidity(address, tick_lower, tick_upper - tick_spacing, 1).invoke()
        res = await swap_exact0_for1(new_contract, expand_to_18decimals(1), address)
        res = await new_contract.remove_liquidity(address, tick_lower, tick_upper, 1).invoke()
        await self.check_tick_is_not_clear(new_contract, tick_lower)
        await self.check_tick_is_clear(new_contract, tick_upper)

    '''

    @pytest.mark.asyncio
    async def test_add_liquidity2(self):
        FEE = FeeAmount.LOW
        tick_spacing = TICK_SPACINGS[FeeAmount.LOW]
        contract_def, contract = await init_contract(CONTRACT_FILE, [tick_spacing, FEE])
        price = encode_price_sqrt(1, 1)
        await contract.initialize(price).invoke()
        min_tick, max_tick = get_min_tick(tick_spacing), get_max_tick(tick_spacing)
        res = await contract.add_liquidity(address, int_to_felt(min_tick), max_tick, expand_to_18decimals(2)).invoke()

        liquidity_delta = 1000
        tick_lower = tick_spacing
        tick_upper = tick_spacing * 2

        res = await contract.get_liquidity().call()
        liquidity_before = res.call_info.result[0]

        # mint to the right of the current price
        new_contract = cached_contract(contract.state.copy(), self.contract_def, contract)
        res = await new_contract.add_liquidity(address, tick_lower, tick_upper, liquidity_delta).invoke()
        amount0 = from_uint(res.call_info.result[0: 2])
        amount1 = from_uint(res.call_info.result[2: 4])
        self.assertEqual(amount0, 1)
        self.assertEqual(amount1, 0)
        
        res = await new_contract.get_liquidity().call()
        liquidity_after = res.call_info.result[0]
        self.assertEqual(liquidity_after >= liquidity_before, True)

        # mint to the left of the current price
        tick_lower = -tick_spacing * 2
        tick_upper = -tick_spacing

        new_contract = cached_contract(contract.state.copy(), self.contract_def, contract)
        res = await new_contract.add_liquidity(address, tick_lower, tick_upper, liquidity_delta).invoke()
        amount0 = from_uint(res.call_info.result[0: 2])
        amount1 = from_uint(res.call_info.result[2: 4])
        self.assertEqual(amount0, 0)
        self.assertEqual(amount1, 1)

        res = await new_contract.get_liquidity().call()
        liquidity_after = res.call_info.result[0]
        self.assertEqual(liquidity_after >= liquidity_before, True)

        # mint within the current price
        tick_lower = - tick_spacing
        tick_upper = tick_spacing

        new_contract = cached_contract(contract.state.copy(), self.contract_def, contract)
        res = await new_contract.add_liquidity(address, tick_lower, tick_upper, liquidity_delta).invoke()
        amount0 = from_uint(res.call_info.result[0: 2])
        amount1 = from_uint(res.call_info.result[2: 4])
        self.assertEqual(amount0, 1)
        self.assertEqual(amount1, 1)

        res = await new_contract.get_liquidity().call()
        liquidity_after = res.call_info.result[0]
        self.assertEqual(liquidity_after >= liquidity_before, True)

        # cannot remove more than the entire position
        tick_lower = -tick_spacing
        tick_upper = tick_spacing

        new_contract = cached_contract(contract.state.copy(), self.contract_def, contract)
        res = await new_contract.add_liquidity(address, tick_lower, tick_upper, expand_to_18decimals(1000)).invoke()

        await assert_revert(
            new_contract.remove_liquidity(address, tick_lower, tick_upper, expand_to_18decimals(1001)).invoke(), 
            ""
        )

        # collect fees within the current price after swap
        liquidity_delta = expand_to_18decimals(100)
        tick_lower = -tick_spacing * 100
        tick_upper = tick_spacing * 100

        new_contract = cached_contract(contract.state.copy(), self.contract_def, contract)
        res = await new_contract.add_liquidity(address, tick_lower, tick_upper, liquidity_delta).invoke()

        res = await new_contract.get_liquidity().call()
        liquidity_before = res.call_info.result[0]

        amount0_in = expand_to_18decimals(1)
        await swap_exact0_for1(new_contract, amount0_in, address)

        res = await new_contract.get_liquidity().call()
        liquidity_after = res.call_info.result[0]
        self.assertEqual(liquidity_after >= liquidity_before, True)

        res = await new_contract.remove_liquidity(address, tick_lower, tick_upper, 0).invoke()
        res = await new_contract.collect(address, tick_lower, tick_upper, MAX_UINT128, MAX_UINT128).invoke()

        res = await new_contract.remove_liquidity(address, tick_lower, tick_upper, 0).invoke()

        res = await new_contract.collect(address, int_to_felt(-46080), int_to_felt(-46020), MAX_UINT128, MAX_UINT128).invoke()
        amount0 = res.call_info.result[0]
        amount1 = res.call_info.result[1]
        self.assertEqual(amount0, 0)
        self.assertEqual(amount1, 0)
        #TODO: check token balance befere and after

    # post-initialize at medium fee
    @pytest.mark.asyncio
    async def test_add_liquidity3(self):
        contract = self.get_state_contract()
        #initialize_at_zero_tick(contract)
        price = encode_price_sqrt(1, 1)
        await contract.initialize(price).invoke()
        res = await contract.add_liquidity(address, int_to_felt(min_tick), max_tick, expand_to_18decimals(2)).invoke()

        res = await contract.get_liquidity().call()
        liquidity = res.call_info.result[0]
        self.assertEqual(liquidity, expand_to_18decimals(2))

        # returns in supply in range        
        new_contract = cached_contract(contract.state.copy(), self.contract_def, self.contract)
        res = await new_contract.add_liquidity(address, -tick_spacing, tick_spacing, expand_to_18decimals(3)).invoke()
        res = await new_contract.get_liquidity().call()
        liquidity = res.call_info.result[0]
        self.assertEqual(liquidity, expand_to_18decimals(5))

        # excludes supply at tick above current tick
        new_contract = cached_contract(contract.state.copy(), self.contract_def, self.contract)
        res = await new_contract.add_liquidity(address, tick_spacing, tick_spacing * 2, expand_to_18decimals(3)).invoke()
        res = await new_contract.get_liquidity().call()
        liquidity = res.call_info.result[0]
        self.assertEqual(liquidity, expand_to_18decimals(2))

        # excludes supply at tick below current tick
        new_contract = cached_contract(contract.state.copy(), self.contract_def, self.contract)
        res = await new_contract.add_liquidity(address, -tick_spacing * 2, -tick_spacing, expand_to_18decimals(3)).invoke()
        res = await new_contract.get_liquidity().call()
        liquidity = res.call_info.result[0]
        self.assertEqual(liquidity, expand_to_18decimals(2))

        # updates correctly when exiting range
        new_contract = cached_contract(contract.state.copy(), self.contract_def, self.contract)
        res = await new_contract.get_liquidity().call()
        liquidity_before = res.call_info.result[0]
        self.assertEqual(liquidity_before, expand_to_18decimals(2))

        liquidity_delta = expand_to_18decimals(1)
        tick_lower = 0
        tick_upper = tick_spacing

        res = await new_contract.add_liquidity(address, tick_lower, tick_upper, liquidity_delta).invoke()

        res = await new_contract.get_liquidity().call()
        liquidity_after = res.call_info.result[0]
        self.assertEqual(liquidity_after, expand_to_18decimals(3))

        res = await swap_exact0_for1(new_contract, 1, address)
        res = await new_contract.get_cur_slot().call()
        tick = felt_to_int(res.call_info.result[2])
        self.assertEqual(tick, -1)

        res = await new_contract.get_liquidity().call()
        liquidity_after = res.call_info.result[0]
        self.assertEqual(liquidity_after, expand_to_18decimals(2))

        # updates correctly when entering range
        new_contract = cached_contract(contract.state.copy(), self.contract_def, self.contract)
        res = await new_contract.get_liquidity().call()
        liquidity_before = res.call_info.result[0]

        liquidity_delta = expand_to_18decimals(1)
        tick_lower = -tick_spacing
        tick_upper = 0
        res = await new_contract.add_liquidity(address, tick_lower, tick_upper, liquidity_delta).invoke()
        res = await new_contract.get_liquidity().call()
        liquidity_after = res.call_info.result[0]
        self.assertEqual(liquidity_after, liquidity_before)

        res = await swap_exact0_for1(new_contract, 1, address)
        res = await new_contract.get_cur_slot().call()
        tick = felt_to_int(res.call_info.result[2])
        self.assertEqual(tick, -1)

        res = await new_contract.get_liquidity().call()
        liquidity_after = res.call_info.result[0]
        self.assertEqual(liquidity_after, expand_to_18decimals(3))