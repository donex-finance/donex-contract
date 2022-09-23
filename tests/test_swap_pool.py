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
    expand_to_18decimals, assert_event_emitted
)

from test_tickmath import (MIN_SQRT_RATIO, MAX_SQRT_RATIO)
from signers import MockSigner

signer = MockSigner(123456789987654321)
other_signer = MockSigner(2343424234234)

Q128 = to_uint(2 ** 128)
MaxUint256 = to_uint(2 ** 256 - 1)

# The path to the contract source code.
CONTRACT_FILE = os.path.join("tests", "../contracts/swap_pool.cairo")

tick_spacing = TICK_SPACINGS[FeeAmount.MEDIUM]
min_tick = get_min_tick(tick_spacing)
max_tick = get_max_tick(tick_spacing)

address = 11111111111111
other_address = 222222222222222

class SwapPoolTest(TestCase):

    @classmethod
    async def setUp(cls):
        pass
        #if not hasattr(cls, 'account'):
        #    account_cls = Account.get_class
        #    cls.account = await Account.deploy(signer.public_key)
        #    cls.other_account = await Account.deploy(other_signer.public_key)
        #    global address, other_address
        #    address = cls.account.contract_address
        #    other_address = cls.other_account.contract_address
        #    print('setUp:', signer.public_key, address, other_signer.public_key, other_address)

    async def check_starknet(self):
        if not hasattr(self, 'starknet'):
            self.starknet = await Starknet.empty()
            self.token0_def, self.token0 = await init_contract(os.path.join("tests", "mocks/ERC20_mock.cairo"), [1, 1, 18, MAX_UINT128, MAX_UINT128, address], starknet=self.starknet)
            await self.token0.transfer(other_address, (MAX_UINT128, 2 ** 127)).execute(caller_address=address)
            self.token1_def, self.token1 = await init_contract(os.path.join("tests", "mocks/ERC20_mock.cairo"), [2, 2, 18, MAX_UINT128, MAX_UINT128, address], starknet=self.starknet)
            await self.token1.transfer(other_address, (MAX_UINT128, 2 ** 127)).execute(caller_address=address)
            if self.token0.contract_address > self.token1.contract_address:
                self.token0, self.token1 = self.token1, self.token0
                self.token0_def, self.token1_def = self.token1_def, self.token0_def
                print('!!!!!!!!!!!!!!!!!!!!!!!!!!change address', self.token0.contract_address, self.token1.contract_address)

            self.swap_target_def, self.swap_target = await init_contract("tests/mocks/swap_target.cairo", [self.token0.contract_address, self.token1.contract_address], starknet=self.starknet)

            await self.token0.approve(self.swap_target.contract_address, to_uint(2 ** 256 - 1)).execute(caller_address=address)
            await self.token1.approve(self.swap_target.contract_address, to_uint(2 ** 256 - 1)).execute(caller_address=address)

            await self.token0.approve(self.swap_target.contract_address, to_uint(2 ** 256 - 1)).execute(caller_address=other_address)
            await self.token1.approve(self.swap_target.contract_address, to_uint(2 ** 256 - 1)).execute(caller_address=other_address)

    async def get_state_contract(self, state=None):
        await self.check_starknet()

        if not hasattr(self, 'contract'):
            FEE = FeeAmount.MEDIUM
            tick_spacing = TICK_SPACINGS[FEE]
            self.contract_def, self.contract = await init_contract(CONTRACT_FILE, [tick_spacing, FEE, self.token0.contract_address, self.token1.contract_address, address], starknet=self.starknet)

        if not state:
            state = self.contract.state.copy()
        swap_pool = cached_contract(state, self.contract_def, self.contract)
        swap_target = cached_contract(state, self.swap_target_def, self.swap_target)
        return swap_pool, swap_target

    async def get_state_contract_low(self, state=None):
        await self.check_starknet()

        if not hasattr(self, 'contract_low'):
            self.contract_def, self.contract_low = await init_contract(CONTRACT_FILE, [TICK_SPACINGS[FeeAmount.LOW], FeeAmount.LOW, self.token0.contract_address, self.token1.contract_address, address], self.starknet)

        if not state:
            state = self.contract_low.state.copy()
        swap_pool = cached_contract(state, self.contract_def, self.contract_low)
        swap_target = cached_contract(state, self.swap_target_def, self.swap_target)
        return swap_pool, swap_target

    async def initialize_at_zero_tick(self, contract, swap_target):
        res = await contract.get_tick_spacing().call()
        tick_spacing = res.call_info.result[0]
        min_tick, max_tick = get_min_tick(tick_spacing), get_max_tick(tick_spacing)
        await contract.initialize(encode_price_sqrt(1, 1)).execute()
        await self.add_liquidity(swap_target, contract, address, min_tick, max_tick, expand_to_18decimals(2))
        return contract

    async def swap_exact0_for1(self, swap_pool, amount, address):
        swap_target = cached_contract(swap_pool.state, self.swap_target_def, self.swap_target)
        sqrt_price_limit = MIN_SQRT_RATIO + 1

        res = await swap_target.swap(address, 1, to_uint(amount), to_uint(sqrt_price_limit), swap_pool.contract_address).execute(caller_address=address)
        return res

    async def swap_exact1_for0(self, swap_pool, amount, address):
        swap_target = cached_contract(swap_pool.state, self.swap_target_def, self.swap_target)
        sqrt_price_limit = MAX_SQRT_RATIO - 1
        res = await swap_target.swap(address, 0, to_uint(amount), to_uint(sqrt_price_limit), swap_pool.contract_address).execute(caller_address=address)
        return res

    @pytest.mark.asyncio
    async def test_initialize(self):

        contract, swap_target = await self.get_state_contract()
        begin = time.time()
        await contract.initialize(encode_price_sqrt(1, 1)).execute()
        print('initial call time:', time.time() - begin)
        await assert_revert(
            contract.initialize(encode_price_sqrt(1, 1)).execute(),
            "initialize more than once"
        )

        contract, swap_target = await self.get_state_contract()
        await assert_revert(
            contract.initialize(to_uint(1)).execute(),
            "tick is too low"
        )
        await assert_revert(
            contract.initialize(to_uint(MIN_SQRT_RATIO - 1)).execute(),
            "tick is too low"
        )

        await assert_revert(
            contract.initialize(to_uint(MAX_SQRT_RATIO)).execute(),
            "tick is too high"
        )
        await assert_revert(
            contract.initialize(to_uint(2 ** 160 - 1)).execute(),
            "tick is too high"
        )

        # can be initialized at MIN_SQRT_RATIO
        contract, swap_target = await self.get_state_contract()
        await contract.initialize(to_uint(MIN_SQRT_RATIO)).execute()
        res = await contract.get_cur_slot().call()
        tick = felt_to_int(res.call_info.result[2])
        self.assertEqual(tick, get_min_tick(1))

        contract, swap_target = await self.get_state_contract()
        await contract.initialize(to_uint(MAX_SQRT_RATIO - 1)).execute()
        res = await contract.get_cur_slot().call()
        tick = felt_to_int(res.call_info.result[2])
        self.assertEqual(tick, get_max_tick(1) - 1)

        contract, swap_target = await self.get_state_contract()
        price = encode_price_sqrt(1, 2)
        await contract.initialize(price).execute()
        res = await contract.get_cur_slot().call()
        sqrt_price_x96 = tuple(res.call_info.result[0: 2])
        tick = felt_to_int(res.call_info.result[2])
        self.assertEqual(price, sqrt_price_x96)
        self.assertEqual(tick, -6932)

    async def add_liquidity(self, swap_target, swap_pool, caller, tick_lower, tick_upper, liquidity):
        res = await swap_target.add_liquidity(caller, tick_lower, tick_upper, liquidity, swap_pool.contract_address).execute(caller_address=caller)
        return res

    @pytest.mark.asyncio
    async def test_add_liquidity_failed(self):

        contract, swap_target = await self.get_state_contract()
        await assert_revert(
            contract.add_liquidity(address, int_to_felt(-tick_spacing), tick_spacing, 1, address).execute(),
            'swap is locked'
        )

        await contract.initialize(encode_price_sqrt(1, 10)).execute()
        await self.add_liquidity(swap_target, contract, address, min_tick, max_tick, 3161)

        await assert_revert(
            contract.add_liquidity(address, -3, 3, expand_to_18decimals(2), address).execute(),
            "tick must be multiples of tick_spacing"
        )

        await assert_revert(
            contract.add_liquidity(address, int_to_felt(1), 0, 1, address).execute(),
            'tick lower is greater than tick upper'
        )

        await assert_revert(
            contract.add_liquidity(address, int_to_felt(-887273), 0, 1, address).execute(),
            'tick is too low'
        )

        await assert_revert(
            contract.add_liquidity(address, 0, 887273, 1, address).execute(),
            'tick is too high'
        )

        res = await contract.get_max_liquidity_per_tick().call()
        max_liquidity_gross = res.call_info.result[0]
        await assert_revert(
            contract.add_liquidity(address, min_tick + tick_spacing, max_tick - tick_spacing, max_liquidity_gross + 1, address).execute(),
            'update: liq_gross_after > max_liquidity'
        )
        print('max_liquidity_gross:', max_liquidity_gross)
        new_contract, new_swap_target = await self.get_state_contract(contract.state.copy())
        await self.add_liquidity(new_swap_target, new_contract, address, min_tick + tick_spacing, max_tick - tick_spacing, max_liquidity_gross)

        # fails if total amount at tick exceeds the max
        await self.add_liquidity(swap_target, contract, address, min_tick + tick_spacing, max_tick - tick_spacing, 1000)
        await assert_revert(
            contract.add_liquidity(address, min_tick + tick_spacing, max_tick - tick_spacing, max_liquidity_gross - 1000 + 1, address).execute(),
            'update: liq_gross_after > max_liquidity'
        )
        await assert_revert(
            contract.add_liquidity(address, min_tick + tick_spacing * 2, max_tick - tick_spacing, max_liquidity_gross - 1000 + 1, address).execute(),
            'update: liq_gross_after > max_liquidity'
        )
        await assert_revert(
            contract.add_liquidity(address, min_tick + tick_spacing, max_tick - tick_spacing * 2, max_liquidity_gross - 1000 + 1, address).execute(),
            'update: liq_gross_after > max_liquidity'
        ) 
        
        await self.add_liquidity(swap_target, contract, address, min_tick + tick_spacing, max_tick - tick_spacing, max_liquidity_gross - 1000)

        await assert_revert(
            contract.add_liquidity(address, min_tick + tick_spacing, max_tick - tick_spacing, 0, address).execute(),
            ''
        )

    @pytest.mark.asyncio
    async def test_add_liquidity_succuss(self):
        contract, swap_target = await self.get_state_contract()
        state = contract.state.copy()
        contract, swap_target = await self.get_state_contract(state)
        token0 = cached_contract(state, self.token0_def, self.token0)
        token1 = cached_contract(state, self.token1_def, self.token1)
        price = to_uint(25054144837504793118650146401)
        await contract.initialize(price).execute()
        res = await self.add_liquidity(swap_target, contract, address, min_tick, max_tick, 3161)
        amount0 = from_uint(res.call_info.result[0: 2])
        amount1 = from_uint(res.call_info.result[2: 4])
        self.assertEqual(amount0, 9996)
        self.assertEqual(amount1, 1000)
        res = await token0.balanceOf(contract.contract_address).call()
        self.assertEqual(res.call_info.result[0], 9996)
        res = await token1.balanceOf(contract.contract_address).call()
        self.assertEqual(res.call_info.result[0], 1000)

        res = await contract.get_cur_slot().call()
        tick = felt_to_int(res.call_info.result[2])
        self.assertEqual(tick, -23028)

        new_contract, new_swap_target = await self.get_state_contract(contract.state.copy())
        res = await self.add_liquidity(new_swap_target, new_contract, address, int_to_felt(-22980), 0, 10000)
        amount0 = from_uint(res.call_info.result[0: 2])
        amount1 = from_uint(res.call_info.result[2: 4])
        self.assertEqual(amount0, 21549)
        self.assertEqual(amount1, 0)

        # max tick with max leverage
        new_contract, new_swap_target = await self.get_state_contract(contract.state.copy())
        res = await self.add_liquidity(new_swap_target, new_contract, address, max_tick - tick_spacing, max_tick, 2 ** 102)
        amount0 = from_uint(res.call_info.result[0: 2])
        amount1 = from_uint(res.call_info.result[2: 4])
        self.assertEqual(amount0, 828011525)
        self.assertEqual(amount1, 0)

        # works for max tick
        new_contract, new_swap_target = await self.get_state_contract(contract.state.copy())
        res = await self.add_liquidity(new_swap_target, new_contract, address, int_to_felt(-22980), max_tick, 10000)
        amount0 = from_uint(res.call_info.result[0: 2])
        amount1 = from_uint(res.call_info.result[2: 4])
        self.assertEqual(amount0, 31549)
        self.assertEqual(amount1, 0)

        # removing works
        new_contract, new_swap_target = await self.get_state_contract(contract.state.copy())
        res = await self.add_liquidity(new_swap_target, new_contract, address, int_to_felt(-240), 0, 10000)
        print('add_liquidity:', res.call_info.result)
        res = await new_contract.remove_liquidity(int_to_felt(-240), 0, 10000).execute(caller_address=address)
        print('remove_liquidity:', res.call_info.result)
        res = await new_contract.collect(address, int_to_felt(-240), 0, MAX_UINT128, MAX_UINT128).execute(caller_address=address)
        amount0 = res.call_info.result[0]
        amount1 = res.call_info.result[1]
        self.assertEqual(amount0, 120)
        self.assertEqual(amount1, 0)

        # adds liquidity to liquidityGross
        new_contract, new_swap_target = await self.get_state_contract(contract.state.copy())
        await self.add_liquidity(new_swap_target, new_contract, address, int_to_felt(-240), 0, 100)
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

        await self.add_liquidity(new_swap_target, new_contract, address, int_to_felt(-240), tick_spacing, 150)
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

        await self.add_liquidity(new_swap_target, new_contract, address, 0, tick_spacing * 2, 60)
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
        new_contract, new_swap_target = await self.get_state_contract(contract.state.copy())
        await self.add_liquidity(new_swap_target, new_contract, address, int_to_felt(-240), 0, 100)
        await self.add_liquidity(new_swap_target, new_contract, address, int_to_felt(-240), 0, 40)
        res = await new_contract.remove_liquidity(int_to_felt(-240), 0, 90).execute(caller_address=address)
        res = await new_contract.get_tick(int_to_felt(-240)).call()
        liquidity_gross = res.call_info.result[0]
        self.assertEqual(liquidity_gross, 50)
        res = await new_contract.get_tick(int_to_felt(0)).call()
        liquidity_gross = res.call_info.result[0]
        self.assertEqual(liquidity_gross, 50)

        # removes liquidity from liquidityGross
        new_contract, new_swap_target = await self.get_state_contract(contract.state.copy())
        await self.add_liquidity(new_swap_target, new_contract, address, int_to_felt(-240), 0, 100)
        await self.add_liquidity(new_swap_target, new_contract, address, int_to_felt(-240), 0, 40)
        res = await new_contract.remove_liquidity(int_to_felt(-240), 0, 90).execute(caller_address=address)
        res = await new_contract.get_tick(int_to_felt(-240)).call()
        liquidity_gross = res.call_info.result[0]
        self.assertEqual(liquidity_gross, 50)
        res = await new_contract.get_tick(int_to_felt(0)).call()
        liquidity_gross = res.call_info.result[0]
        self.assertEqual(liquidity_gross, 50)

        # clears tick upper if last position is removed
        new_contract, new_swap_target = await self.get_state_contract(contract.state.copy())
        await self.add_liquidity(new_swap_target, new_contract, address, int_to_felt(-240), 0, 100)
        res = await new_contract.remove_liquidity(int_to_felt(-240), 0, 100).execute(caller_address=address)
        res = await new_contract.get_tick(int_to_felt(0)).call()
        liquidity_gross = res.call_info.result[0]
        fee_growth_outside0 = from_uint(res.call_info.result[2: 4])
        fee_growth_outside1 = from_uint(res.call_info.result[4: 6])
        self.assertEqual(liquidity_gross, 0)
        self.assertEqual(fee_growth_outside0, 0)
        self.assertEqual(fee_growth_outside1, 0)
        
        # only clears the tick that is not used at all
        new_contract, new_swap_target = await self.get_state_contract(contract.state.copy())
        await self.add_liquidity(new_swap_target, new_contract, address, int_to_felt(-240), 0, 100)
        await self.add_liquidity(new_swap_target, new_contract, address, int_to_felt(-tick_spacing), 0, 250)
        res = await new_contract.remove_liquidity(int_to_felt(-240), 0, 100).execute(caller_address=address)
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
        new_contract, new_swap_target = await self.get_state_contract(contract.state.copy())
        res = await self.add_liquidity(new_swap_target, new_contract, address, int_to_felt(min_tick + tick_spacing), max_tick - tick_spacing, 100)
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
        new_contract, new_swap_target = await self.get_state_contract(contract.state.copy())
        res = await self.add_liquidity(new_swap_target, new_contract, address, int_to_felt(min_tick), max_tick, 10000)
        amount0 = from_uint(res.call_info.result[0: 2])
        amount1 = from_uint(res.call_info.result[2: 4])
        self.assertEqual(amount0, 31623)
        self.assertEqual(amount1, 3163)

        # removing works
        new_contract, new_swap_target = await self.get_state_contract(contract.state.copy())
        res = await self.add_liquidity(new_swap_target, new_contract, address, int_to_felt(min_tick + tick_spacing), max_tick - tick_spacing, 100)
        res = await new_contract.remove_liquidity(int_to_felt(min_tick + tick_spacing), max_tick - tick_spacing, 100).execute(caller_address=address)
        res = await new_contract.collect(address, int_to_felt(min_tick + tick_spacing), max_tick - tick_spacing, MAX_UINT128, MAX_UINT128).execute(caller_address=address)
        amount0 = res.call_info.result[0]
        amount1 = res.call_info.result[1]
        self.assertEqual(amount0, 316)
        self.assertEqual(amount1, 31)

        # transfers token1 only
        new_contract, new_swap_target = await self.get_state_contract(contract.state.copy())
        res = await self.add_liquidity(new_swap_target, new_contract, address, int_to_felt(-46080), int_to_felt(-23040), 10000)
        amount0 = from_uint(res.call_info.result[0: 2])
        amount1 = from_uint(res.call_info.result[2: 4])
        self.assertEqual(amount0, 0)
        self.assertEqual(amount1, 2162)

        # min tick with max leverage
        new_contract, new_swap_target = await self.get_state_contract(contract.state.copy())
        res = await self.add_liquidity(new_swap_target, new_contract, address, int_to_felt(min_tick), int_to_felt(min_tick + tick_spacing), 2 ** 102)
        amount0 = from_uint(res.call_info.result[0: 2])
        amount1 = from_uint(res.call_info.result[2: 4])
        self.assertEqual(amount0, 0)
        self.assertEqual(amount1, 828011520)

        # works for min tick
        new_contract, new_swap_target = await self.get_state_contract(contract.state.copy())
        res = await self.add_liquidity(new_swap_target, new_contract, address, int_to_felt(min_tick), int_to_felt(-23040), 10000)
        amount0 = from_uint(res.call_info.result[0: 2])
        amount1 = from_uint(res.call_info.result[2: 4])
        self.assertEqual(amount0, 0)
        self.assertEqual(amount1, 3161)

        # removing works
        new_contract, new_swap_target = await self.get_state_contract(contract.state.copy())
        res = await self.add_liquidity(new_swap_target, new_contract, address, int_to_felt(-46080), int_to_felt(-46020), 10000)
        res = await new_contract.remove_liquidity(int_to_felt(-46080), int_to_felt(-46020), 10000).execute(caller_address=address)
        res = await new_contract.collect(address, int_to_felt(-46080), int_to_felt(-46020), MAX_UINT128, MAX_UINT128).execute(caller_address=address)
        amount0 = res.call_info.result[0]
        amount1 = res.call_info.result[1]
        self.assertEqual(amount0, 0)
        self.assertEqual(amount1, 3)


    @pytest.mark.asyncio
    async def test_protocol_fee(self):
        contract, swap_target = await self.get_state_contract()
        price = to_uint(25054144837504793118650146401)
        await contract.initialize(price).execute()
        await self.add_liquidity(swap_target, contract, address, min_tick, max_tick, 3161)

        # protocol fees accumulate as expected during swap
        new_contract, new_swap_target = await self.get_state_contract(contract.state.copy())
        await new_contract.set_fee_protocol(6, 6).execute(caller_address=address)
        res = await self.add_liquidity(new_swap_target, new_contract, address, int_to_felt(min_tick + tick_spacing), max_tick - tick_spacing, expand_to_18decimals(1))
        print('add_liquidity', res.call_info.result)
        res = await self.swap_exact0_for1(new_contract, expand_to_18decimals(1) // 10, address)
        print('swap_exact0_for1', res.call_info.result)
        res = await self.swap_exact1_for0(new_contract, expand_to_18decimals(1) // 100, address)
        print('swap_exact1_for0', res.call_info.result)
        res = await new_contract.get_protocol_fees().call()
        token0_fee = res.call_info.result[0]
        token1_fee = res.call_info.result[1]
        self.assertEqual(token0_fee, 50000000000000)
        self.assertEqual(token1_fee, 5000000000000)

        # positions are protected before protocol fee is turned on
        new_contract, new_swap_target = await self.get_state_contract(contract.state.copy())
        res = await self.add_liquidity(new_swap_target, new_contract, address, int_to_felt(min_tick + tick_spacing), max_tick - tick_spacing, expand_to_18decimals(1))
        res = await self.swap_exact0_for1(new_contract, expand_to_18decimals(1) // 10, address)
        res = await self.swap_exact1_for0(new_contract, expand_to_18decimals(1) // 100, address)
        res = await new_contract.get_protocol_fees().call()
        token0_fee = res.call_info.result[0]
        token1_fee = res.call_info.result[1]
        self.assertEqual(token0_fee, 0)
        self.assertEqual(token1_fee, 0)

        await new_contract.set_fee_protocol(6, 6).execute(caller_address=address)
        res = await new_contract.get_protocol_fees().call()
        token0_fee = res.call_info.result[0]
        token1_fee = res.call_info.result[1]
        self.assertEqual(token0_fee, 0)
        self.assertEqual(token1_fee, 0)

        # poke is not allowed on uninitialized position
        new_contract, new_swap_target = await self.get_state_contract(contract.state.copy())
        res = await self.add_liquidity(new_swap_target, new_contract, other_address, int_to_felt(min_tick + tick_spacing), max_tick - tick_spacing, expand_to_18decimals(1))
        res = await self.swap_exact0_for1(new_contract, expand_to_18decimals(1) // 10, address)
        res = await self.swap_exact1_for0(new_contract, expand_to_18decimals(1) // 100, address)

        await assert_revert(
            new_contract.remove_liquidity(int_to_felt(min_tick + tick_spacing), max_tick - tick_spacing, 0).execute(caller_address=address),
            ""
        )
        res = await self.add_liquidity(new_swap_target, new_contract, address, int_to_felt(min_tick + tick_spacing), max_tick - tick_spacing, 1)

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

        await new_contract.remove_liquidity(int_to_felt(min_tick + tick_spacing), max_tick - tick_spacing, 1).execute(caller_address=address)
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

        contract, swap_target = await self.get_state_contract()
        price = encode_price_sqrt(1, 1)
        await contract.initialize(price).execute()
        res = await self.add_liquidity(swap_target, contract, address, int_to_felt(min_tick), max_tick, expand_to_18decimals(2))

        # remove more liquidity more than have
        new_contract = cached_contract(contract.state.copy(), self.contract_def, self.contract)
        await assert_revert(
            new_contract.remove_liquidity(int_to_felt(min_tick), max_tick, expand_to_18decimals(3)).execute(caller_address=address),
            "safe_add: minus result"
        )

        # does not clear the position fee growth snapshot if no more liquidity
        new_contract, new_swap_target = await self.get_state_contract(contract.state.copy())
        res = await self.add_liquidity(new_swap_target, new_contract, other_address, int_to_felt(min_tick), max_tick, expand_to_18decimals(1))
        print('add_liquidity', res.call_info.result)
        res = await self.swap_exact0_for1(new_contract, expand_to_18decimals(1), address)
        print('min_tick', min_tick, 'max_tick', max_tick)
        print('swap_exact0_for1:', res.call_info.result)
        res = await self.swap_exact1_for0(new_contract, expand_to_18decimals(1), address)
        print('swap_exact1_for0:', res.call_info.result)

        res = await new_contract.remove_liquidity(int_to_felt(min_tick), max_tick, expand_to_18decimals(1)).execute(caller_address=other_address)
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
        new_contract, new_swap_target = await self.get_state_contract(contract.state.copy())
        res = await self.add_liquidity(new_swap_target, new_contract, address, tick_lower, tick_upper, 1)
        res = await self.swap_exact0_for1(new_contract, expand_to_18decimals(1), address)
        res = await new_contract.remove_liquidity(tick_lower, tick_upper, 1).execute(caller_address=address)
        await self.check_tick_is_clear(new_contract, tick_lower)
        await self.check_tick_is_clear(new_contract, tick_upper)

        # clears only the lower tick if upper is still used
        new_contract, new_swap_target = await self.get_state_contract(contract.state.copy())
        res = await self.add_liquidity(new_swap_target, new_contract, address, tick_lower, tick_upper, 1)
        res = await self.add_liquidity(new_swap_target, new_contract, address, tick_lower + tick_spacing, tick_upper, 1)
        res = await self.swap_exact0_for1(new_contract, expand_to_18decimals(1), address)
        res = await new_contract.remove_liquidity(tick_lower, tick_upper, 1).execute(caller_address=address)
        await self.check_tick_is_clear(new_contract, tick_lower)
        await self.check_tick_is_not_clear(new_contract, tick_upper)

        # clears only the upper tick if lower is still used
        new_contract, new_swap_target = await self.get_state_contract(contract.state.copy())
        res = await self.add_liquidity(new_swap_target, new_contract, address, tick_lower, tick_upper, 1)
        res = await self.add_liquidity(new_swap_target, new_contract, address, tick_lower, tick_upper - tick_spacing, 1)
        res = await self.swap_exact0_for1(new_contract, expand_to_18decimals(1), address)
        res = await new_contract.remove_liquidity(tick_lower, tick_upper, 1).execute(caller_address=address)
        await self.check_tick_is_not_clear(new_contract, tick_lower)
        await self.check_tick_is_clear(new_contract, tick_upper)

    @pytest.mark.asyncio
    async def test_add_liquidity2(self):
        tick_spacing = TICK_SPACINGS[FeeAmount.LOW]
        min_tick, max_tick = get_min_tick(tick_spacing), get_max_tick(tick_spacing)
        contract, swap_target = await self.get_state_contract_low()
        contract = await self.initialize_at_zero_tick(contract, swap_target)

        liquidity_delta = 1000
        tick_lower = tick_spacing
        tick_upper = tick_spacing * 2

        res = await contract.get_liquidity().call()
        liquidity_before = res.call_info.result[0]

        # mint to the right of the current price
        new_contract, new_swap_target = await self.get_state_contract_low(contract.state.copy())
        res = await self.add_liquidity(new_swap_target, new_contract, address, tick_lower, tick_upper, liquidity_delta)
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

        new_contract, new_swap_target = await self.get_state_contract_low(contract.state.copy())
        res = await self.add_liquidity(new_swap_target, new_contract, address, tick_lower, tick_upper, liquidity_delta)
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

        new_contract, new_swap_target = await self.get_state_contract_low(contract.state.copy())
        res = await self.add_liquidity(new_swap_target, new_contract, address, tick_lower, tick_upper, liquidity_delta)
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

        new_contract, new_swap_target = await self.get_state_contract_low(contract.state.copy())
        res = await self.add_liquidity(new_swap_target, new_contract, address, tick_lower, tick_upper, expand_to_18decimals(1000))

        await assert_revert(
            new_contract.remove_liquidity(tick_lower, tick_upper, expand_to_18decimals(1001)).execute(caller_address=address), 
            ""
        )

        # collect fees within the current price after swap
        liquidity_delta = expand_to_18decimals(100)
        tick_lower = -tick_spacing * 100
        tick_upper = tick_spacing * 100

        new_contract, new_swap_target = await self.get_state_contract_low(contract.state.copy())
        res = await self.add_liquidity(new_swap_target, new_contract, address, tick_lower, tick_upper, liquidity_delta)

        res = await new_contract.get_liquidity().call()
        liquidity_before = res.call_info.result[0]

        amount0_in = expand_to_18decimals(1)
        await self.swap_exact0_for1(new_contract, amount0_in, address)

        res = await new_contract.get_liquidity().call()
        liquidity_after = res.call_info.result[0]
        self.assertEqual(liquidity_after >= liquidity_before, True)

        res = await new_contract.remove_liquidity(tick_lower, tick_upper, 0).execute(caller_address=address)
        res = await new_contract.collect(address, tick_lower, tick_upper, MAX_UINT128, MAX_UINT128).execute(caller_address=address)

        res = await new_contract.remove_liquidity(tick_lower, tick_upper, 0).execute(caller_address=address)

        res = await new_contract.collect(address, int_to_felt(-46080), int_to_felt(-46020), MAX_UINT128, MAX_UINT128).execute(caller_address=address)
        amount0 = res.call_info.result[0]
        amount1 = res.call_info.result[1]
        self.assertEqual(amount0, 0)
        self.assertEqual(amount1, 0)
        #TODO: check token balance befere and after

    # post-initialize at medium fee
    @pytest.mark.asyncio
    async def test_add_liquidity3(self):
        contract, swap_target = await self.get_state_contract()
        price = encode_price_sqrt(1, 1)
        await contract.initialize(price).execute()
        res = await self.add_liquidity(swap_target, contract, address, int_to_felt(min_tick), max_tick, expand_to_18decimals(2))

        res = await contract.get_liquidity().call()
        liquidity = res.call_info.result[0]
        self.assertEqual(liquidity, expand_to_18decimals(2))

        # returns in supply in range        
        new_contract, new_swap_target = await self.get_state_contract(contract.state.copy())
        res = await self.add_liquidity(new_swap_target, new_contract, address, -tick_spacing, tick_spacing, expand_to_18decimals(3))
        res = await new_contract.get_liquidity().call()
        liquidity = res.call_info.result[0]
        self.assertEqual(liquidity, expand_to_18decimals(5))

        # excludes supply at tick above current tick
        new_contract, new_swap_target = await self.get_state_contract(contract.state.copy())
        res = await self.add_liquidity(new_swap_target, new_contract, address, tick_spacing, tick_spacing * 2, expand_to_18decimals(3))
        res = await new_contract.get_liquidity().call()
        liquidity = res.call_info.result[0]
        self.assertEqual(liquidity, expand_to_18decimals(2))

        # excludes supply at tick below current tick
        new_contract, new_swap_target = await self.get_state_contract(contract.state.copy())
        res = await self.add_liquidity(new_swap_target, new_contract, address, -tick_spacing * 2, -tick_spacing, expand_to_18decimals(3))
        res = await new_contract.get_liquidity().call()
        liquidity = res.call_info.result[0]
        self.assertEqual(liquidity, expand_to_18decimals(2))

        # updates correctly when exiting range
        new_contract, new_swap_target = await self.get_state_contract(contract.state.copy())
        res = await new_contract.get_liquidity().call()
        liquidity_before = res.call_info.result[0]
        self.assertEqual(liquidity_before, expand_to_18decimals(2))

        liquidity_delta = expand_to_18decimals(1)
        tick_lower = 0
        tick_upper = tick_spacing

        res = await self.add_liquidity(new_swap_target, new_contract, address, tick_lower, tick_upper, liquidity_delta)

        res = await new_contract.get_liquidity().call()
        liquidity_after = res.call_info.result[0]
        self.assertEqual(liquidity_after, expand_to_18decimals(3))

        res = await self.swap_exact0_for1(new_contract, 1, address)
        res = await new_contract.get_cur_slot().call()
        tick = felt_to_int(res.call_info.result[2])
        self.assertEqual(tick, -1)

        res = await new_contract.get_liquidity().call()
        liquidity_after = res.call_info.result[0]
        self.assertEqual(liquidity_after, expand_to_18decimals(2))

        # updates correctly when entering range
        new_contract, new_swap_target = await self.get_state_contract(contract.state.copy())
        res = await new_contract.get_liquidity().call()
        liquidity_before = res.call_info.result[0]

        liquidity_delta = expand_to_18decimals(1)
        tick_lower = -tick_spacing
        tick_upper = 0
        res = await self.add_liquidity(new_swap_target, new_contract, address, tick_lower, tick_upper, liquidity_delta)
        res = await new_contract.get_liquidity().call()
        liquidity_after = res.call_info.result[0]
        self.assertEqual(liquidity_after, liquidity_before)

        res = await self.swap_exact0_for1(new_contract, 1, address)
        res = await new_contract.get_cur_slot().call()
        tick = felt_to_int(res.call_info.result[2])
        self.assertEqual(tick, -1)

        res = await new_contract.get_liquidity().call()
        liquidity_after = res.call_info.result[0]
        self.assertEqual(liquidity_after, expand_to_18decimals(3))

    @pytest.mark.asyncio
    async def test_limit_orders(self):
        contract, swap_target = await self.get_state_contract()
        price = encode_price_sqrt(1, 1)
        await contract.initialize(price).execute()
        res = await self.add_liquidity(swap_target, contract, address, int_to_felt(min_tick), max_tick, expand_to_18decimals(2))

        # limit selling 0 for 1 at tick 0 thru 1
        new_contract, new_swap_target = await self.get_state_contract(contract.state.copy())
        res = await self.add_liquidity(new_swap_target, new_contract, address, 0, 120, expand_to_18decimals(1))
        res = await self.swap_exact1_for0(new_contract, expand_to_18decimals(2), other_address)
        res = await new_contract.remove_liquidity(0, 120, expand_to_18decimals(1)).execute(caller_address=address)
        assert_event_emitted(
            res,
            from_address=new_contract.contract_address,
            name='RemoveLiquidity',
            data=[
                address,
                0, 
                120,
                expand_to_18decimals(1),
                0,
                0,
                6017734268818165,
                0
            ]
        )

        res = await new_contract.collect(address, 0, 120, MAX_UINT128, MAX_UINT128).execute(caller_address=other_address)
        assert_event_emitted(
            res,
            from_address=new_contract.contract_address,
            name = 'Collect',
            data=[
                other_address,
                address,
                0, 
                120,
                MAX_UINT128,
                MAX_UINT128,
                0,
                0,
            ]
        )

        res = await new_contract.collect(address, 0, 120, MAX_UINT128, MAX_UINT128).execute(caller_address=address)
        assert_event_emitted(
            res,
            from_address=new_contract.contract_address,
            name = 'Collect',
            data=[
                address,
                address,
                0, 
                120,
                MAX_UINT128,
                MAX_UINT128,
                0,
                6017734268818165 + 18107525382602,
            ]
        )
        res = await new_contract.get_cur_slot().call()
        tick = felt_to_int(res.call_info.result[2])
        self.assertEqual(tick >= 120, True)

        # limit selling 1 for 0 at tick 0 thru -1
        new_contract, new_swap_target = await self.get_state_contract(contract.state.copy())
        res = await self.add_liquidity(new_swap_target, new_contract, address, -120, 0, expand_to_18decimals(1))

        res = await self.swap_exact0_for1(new_contract, expand_to_18decimals(2), other_address)

        res = await new_contract.remove_liquidity(-120, 0, expand_to_18decimals(1)).execute(caller_address=address)
        assert_event_emitted(
            res,
            from_address=new_contract.contract_address,
            name='RemoveLiquidity',
            data=[
                address,
                int_to_felt(-120), 
                0,
                expand_to_18decimals(1),
                6017734268818165,
                0,
                0,
                0
            ]
        )

        res = await new_contract.collect(address, -120, 0, MAX_UINT128, MAX_UINT128).execute(caller_address=address)
        print(res.raw_events)
        assert_event_emitted(
            res,
            from_address=new_contract.contract_address,
            name = 'Collect',
            data=[
                address,
                address,
                int_to_felt(-120), 
                0,
                MAX_UINT128,
                MAX_UINT128,
                6017734268818165 + 18107525382602,
                0,
            ]
        )
        res = await new_contract.get_cur_slot().call()
        tick = felt_to_int(res.call_info.result[2])
        self.assertEqual(tick < -120, True)

        # fee is on
        res = await contract.set_fee_protocol(6, 6).execute(caller_address=address)

        # limit selling 0 for 1 at tick 0 thru 1
        new_contract, new_swap_target = await self.get_state_contract(contract.state.copy())
        res = await self.add_liquidity(new_swap_target, new_contract, address, 0, 120, expand_to_18decimals(1))
        res = await self.swap_exact1_for0(new_contract, expand_to_18decimals(2), other_address)
        res = await new_contract.remove_liquidity(0, 120, expand_to_18decimals(1)).execute(caller_address=address)
        assert_event_emitted(
            res,
            from_address=new_contract.contract_address,
            name='RemoveLiquidity',
            data=[
                address,
                0, 
                120,
                expand_to_18decimals(1),
                0,
                0,
                6017734268818165,
                0
            ]
        )

        res = await new_contract.collect(address, 0, 120, MAX_UINT128, MAX_UINT128).execute(caller_address=address)
        assert_event_emitted(
            res,
            from_address=new_contract.contract_address,
            name = 'Collect',
            data=[
                address,
                address,
                0, 
                120,
                MAX_UINT128,
                MAX_UINT128,
                0,
                6017734268818165 + 15089604485501,
            ]
        )
        res = await new_contract.get_cur_slot().call()
        tick = felt_to_int(res.call_info.result[2])
        self.assertEqual(tick >= 120, True)

        # limit selling 1 for 0 at tick 0 thru -1
        new_contract, new_swap_target = await self.get_state_contract(contract.state.copy())
        res = await self.add_liquidity(new_swap_target, new_contract, address, -120, 0, expand_to_18decimals(1))

        res = await self.swap_exact0_for1(new_contract, expand_to_18decimals(2), other_address)

        res = await new_contract.remove_liquidity(-120, 0, expand_to_18decimals(1)).execute(caller_address=address)
        assert_event_emitted(
            res,
            from_address=new_contract.contract_address,
            name='RemoveLiquidity',
            data=[
                address,
                int_to_felt(-120), 
                0,
                expand_to_18decimals(1),
                6017734268818165,
                0,
                0,
                0
            ]
        )

        res = await new_contract.collect(other_address, -120, 0, MAX_UINT128, MAX_UINT128).execute(caller_address=address)
        print(res.raw_events)
        assert_event_emitted(
            res,
            from_address=new_contract.contract_address,
            name = 'Collect',
            data=[
                address,
                other_address,
                int_to_felt(-120), 
                0,
                MAX_UINT128,
                MAX_UINT128,
                6017734268818165 + 15089604485501,
                0,
            ]
        )
        res = await new_contract.get_cur_slot().call()
        tick = felt_to_int(res.call_info.result[2])
        self.assertEqual(tick < -120, True)

    #TODO: test
    @pytest.mark.asyncio
    async def test_collect(self):
        tick_spacing = TICK_SPACINGS[FeeAmount.LOW]
        min_tick, max_tick = get_min_tick(tick_spacing), get_max_tick(tick_spacing)
        contract, swap_target = await self.get_state_contract_low()
        constract = await self.initialize_at_zero_tick(contract, swap_target)

        # works with multiple LPs
        new_contract, new_swap_target = await self.get_state_contract_low(contract.state.copy())
        res = await self.add_liquidity(new_swap_target, new_contract, address, min_tick, max_tick, expand_to_18decimals(1))
        res = await self.add_liquidity(new_swap_target, new_contract, address, min_tick + tick_spacing, max_tick - tick_spacing, expand_to_18decimals(2))

        res = await self.swap_exact0_for1(new_contract, expand_to_18decimals(1), address)
        res = await new_contract.remove_liquidity(min_tick, max_tick, 0).execute(caller_address=address)
        await new_contract.remove_liquidity(min_tick + tick_spacing, max_tick - tick_spacing, 0).execute(caller_address=address)

        res = await new_contract.get_position(address, int_to_felt(min_tick), max_tick).call()
        print(res.call_info.result, tick_spacing, min_tick, max_tick)
        tokens_owed0 = res.call_info.result[5]
        self.assertEqual(tokens_owed0, 166666666666667)

        res = await new_contract.get_position(address, int_to_felt(min_tick + tick_spacing), max_tick - tick_spacing).call()
        print(res.call_info.result, tick_spacing, min_tick, max_tick)
        tokens_owed0 = res.call_info.result[5]
        self.assertEqual(tokens_owed0, 333333333333334)

        #TODO: works across large increases
        '''
        res = await contract.add_liquidity(address, min_tick, max_tick, expand_to_18decimals(1)).execute()

        magic_num = 115792089237316195423570985008687907852929702298719625575994

        # works just before the cap binds
        new_contract = cached_contract(contract.state.copy(), self.contract_def, contract)
        res = await new_contract.add_liquidity(address, min_tick, max_tick, expand_to_18decimals(1)).execute()
        #TODO: set_fee
        res = await new_contract.set_fee_growth_global0_x128(to_uint(magic_num)).execute()

        res = await new_contract.remove_liquidity(min_tick, max_tick, 0).execute(caller_address=address)

        res = await new_contract.get_position(address, int_to_felt(min_tick ), max_tick).call()
        tokens_owed0 = res.call_info.result[5]
        tokens_owed1 = res.call_info.result[6]
        self.assertEqual(tokens_owed0, MAX_UINT128 - 1)
        self.assertEqual(tokens_owed1, 0)

        # works just after the cap binds
        new_contract = cached_contract(contract.state.copy(), self.contract_def, contract)
        #TODO: set_fee
        res = await new_contract.set_fee_growth_global0_x128(to_uint(magic_num + 1)).execute()

        res = await new_contract.remove_liquidity(min_tick, max_tick, 0).execute(caller_address=address)

        res = await new_contract.get_position(address, int_to_felt(min_tick ), max_tick).call()
        tokens_owed0 = res.call_info.result[5]
        tokens_owed1 = res.call_info.result[6]
        self.assertEqual(tokens_owed0, MAX_UINT128)
        self.assertEqual(tokens_owed1, 0)

        # worksworks well after the cap binds
        new_contract = cached_contract(contract.state.copy(), self.contract_def, contract)
        #TODO: set_fee
        res = await new_contract.set_fee_growth_global0_x128(to_uint(2 ** 256 - 1)).execute()

        res = await new_contract.remove_liquidity(min_tick, max_tick, 0).execute(caller_address=address)

        res = await new_contract.get_position(address, int_to_felt(min_tick ), max_tick).call()
        tokens_owed0 = res.call_info.result[5]
        tokens_owed1 = res.call_info.result[6]
        self.assertEqual(tokens_owed0, MAX_UINT128)
        self.assertEqual(tokens_owed1, 0)
        '''

    async def swap_and_get_fees_owed(self, contract, amount, zeroForOne, poke, min_tick, max_tick):
        if zeroForOne:
            await self.swap_exact0_for1(contract, amount, address)
        else:
            await self.swap_exact1_for0(contract, amount, address)

        if poke:
            await contract.remove_liquidity(min_tick, max_tick, 0).execute(caller_address=address)

        new_contract = cached_contract(contract.state.copy(), self.contract_def, contract)
        res = await new_contract.collect(address, min_tick, max_tick, MAX_UINT128, MAX_UINT128).execute(caller_address=address)
        amount0 = res.call_info.result[0]
        amount1 = res.call_info.result[1]

        assert amount0 >= 0
        assert amount1 >= 0
        return amount0, amount1

    @pytest.mark.asyncio
    async def test_fee_protocol(self):
        liquidity_amount = expand_to_18decimals(1000)
        tick_spacing = TICK_SPACINGS[FeeAmount.LOW]
        min_tick, max_tick = get_min_tick(tick_spacing), get_max_tick(tick_spacing)
        contract, swap_target = await self.get_state_contract_low()
        await contract.initialize(encode_price_sqrt(1, 1)).execute()
        res = await self.add_liquidity(swap_target, contract, address, min_tick, max_tick, liquidity_amount)

        # is initially set to 0
        res = await contract.get_fee_protocol().call()
        self.assertEqual(res.call_info.result[0], 0)

        # can be changed by the owner
        new_contract = cached_contract(contract.state.copy(), self.contract_def, contract)
        res = await new_contract.set_fee_protocol(6, 6).execute(caller_address=address)
        res = await new_contract.get_fee_protocol().call()
        self.assertEqual(res.call_info.result[0], 102)

        # can be changed by the owner
        new_contract = cached_contract(contract.state.copy(), self.contract_def, contract)
        await assert_revert(
            new_contract.set_fee_protocol(3, 3).execute(caller_address=address),
            ''
        )
        await assert_revert(
            new_contract.set_fee_protocol(11, 11).execute(caller_address=address),
            ''
        )

        # cannot be changed by addresses that are not owner
        await assert_revert(
            new_contract.set_fee_protocol(6, 6).execute(caller_address=other_address),
            ''
        )

        # cannot be collect by addresses that are not owner
        await assert_revert(
            new_contract.collect_protocol(address, MAX_UINT128, MAX_UINT128).execute(caller_address=other_address),
            ''
        )

        # position owner gets full fees when protocol fee is off
        # swap fees accumulate as expected (0 for 1)
        new_contract = cached_contract(contract.state.copy(), self.contract_def, contract)
        token0_fees, token1_fees = await self.swap_and_get_fees_owed(new_contract, expand_to_18decimals(1), True, True, min_tick, max_tick)
        self.assertEqual(token0_fees, 499999999999999)
        self.assertEqual(token1_fees, 0)

        token0_fees, token1_fees = await self.swap_and_get_fees_owed(new_contract, expand_to_18decimals(1), True, True, min_tick, max_tick)
        self.assertEqual(token0_fees, 999999999999998)
        self.assertEqual(token1_fees, 0)

        token0_fees, token1_fees = await self.swap_and_get_fees_owed(new_contract, expand_to_18decimals(1), True, True, min_tick, max_tick)
        self.assertEqual(token0_fees, 1499999999999997)
        self.assertEqual(token1_fees, 0)

        # swap fees accumulate as expected (1 for 0)
        new_contract = cached_contract(contract.state.copy(), self.contract_def, contract)
        token0_fees, token1_fees = await self.swap_and_get_fees_owed(new_contract, expand_to_18decimals(1), False, True, min_tick, max_tick)
        self.assertEqual(token0_fees, 0)
        self.assertEqual(token1_fees, 499999999999999)

        # swap fees accumulate as expected (0 for 1)
        token0_fees, token1_fees = await self.swap_and_get_fees_owed(new_contract, expand_to_18decimals(1), False, True, min_tick, max_tick)
        self.assertEqual(token0_fees, 0)
        self.assertEqual(token1_fees, 999999999999998)

        token0_fees, token1_fees = await self.swap_and_get_fees_owed(new_contract, expand_to_18decimals(1), False, True, min_tick, max_tick)
        self.assertEqual(token0_fees, 0)
        self.assertEqual(token1_fees, 1499999999999997)

        # position owner gets partial fees when protocol fee is on
        new_contract = cached_contract(contract.state.copy(), self.contract_def, contract)
        res = await new_contract.set_fee_protocol(6, 6).execute(caller_address=address)
        token0_fees, token1_fees = await self.swap_and_get_fees_owed(new_contract, expand_to_18decimals(1), True, True, min_tick, max_tick)
        self.assertEqual(token0_fees, 416666666666666)
        self.assertEqual(token1_fees, 0)

        # collectProtocol
        # returns 0 if no fees
        new_contract = cached_contract(contract.state.copy(), self.contract_def, contract)
        res = await new_contract.set_fee_protocol(6, 6).execute(caller_address=address)
        res = await new_contract.collect_protocol(address, MAX_UINT128, MAX_UINT128).execute(caller_address=address)
        self.assertEqual(res.call_info.result[0], 0)
        self.assertEqual(res.call_info.result[1], 0)

        # can collect fees
        new_contract = cached_contract(contract.state.copy(), self.contract_def, contract)
        res = await new_contract.set_fee_protocol(6, 6).execute(caller_address=address)
        res = await self.swap_and_get_fees_owed(new_contract, expand_to_18decimals(1), True, True, min_tick, max_tick)

        res = await new_contract.collect_protocol(other_address, MAX_UINT128, MAX_UINT128).execute(caller_address=address)
        print(res.raw_events)
        assert_event_emitted(
            res,
            from_address=new_contract.contract_address,
            name='TransferToken',
            data=[
                self.token0.contract_address,
                other_address, 
                83333333333332,
                0
            ]
        )

        # fees collected can differ between token0 and token1
        new_contract = cached_contract(contract.state.copy(), self.contract_def, contract)
        res = await new_contract.set_fee_protocol(8, 5).execute(caller_address=address)
        await self.swap_and_get_fees_owed(new_contract, expand_to_18decimals(1), True, False, min_tick, max_tick)
        await self.swap_and_get_fees_owed(new_contract, expand_to_18decimals(1), False, False, min_tick, max_tick)
        res = await new_contract.collect_protocol(other_address, MAX_UINT128, MAX_UINT128).execute(caller_address=address)
        print(res.raw_events)
        assert_event_emitted(
            res,
            from_address=new_contract.contract_address,
            name='TransferToken',
            data=[
                self.token0.contract_address,
                other_address, 
                62499999999999,
                0
            ]
        )
        assert_event_emitted(
            res,
            from_address=new_contract.contract_address,
            name='TransferToken',
            data=[
                self.token1.contract_address,
                other_address, 
                99999999999998,
                0
            ]
        )

        # fees collected by lp after two swaps should be double one swap
        new_contract = cached_contract(contract.state.copy(), self.contract_def, contract)
        await self.swap_and_get_fees_owed(new_contract, expand_to_18decimals(1), True, True, min_tick, max_tick)
        res = await self.swap_and_get_fees_owed(new_contract, expand_to_18decimals(1), True, True, min_tick, max_tick)
        self.assertEqual(res[0], 999999999999998)
        self.assertEqual(res[1], 0)

        # fees collected after two swaps with fee turned on in middle are fees from last swap (not confiscatory)
        new_contract = cached_contract(contract.state.copy(), self.contract_def, contract)
        await self.swap_and_get_fees_owed(new_contract, expand_to_18decimals(1), True, False, min_tick, max_tick)

        await new_contract.set_fee_protocol(6, 6).execute(caller_address=address)
        res = await self.swap_and_get_fees_owed(new_contract, expand_to_18decimals(1), True, True, min_tick, max_tick)
        self.assertEqual(res[0], 916666666666666)
        self.assertEqual(res[1], 0)

        # fees collected by lp after two swaps with intermediate withdrawal
        new_contract = cached_contract(contract.state.copy(), self.contract_def, contract)
        await new_contract.set_fee_protocol(6, 6).execute(caller_address=address)
        res = await self.swap_and_get_fees_owed(new_contract, expand_to_18decimals(1), True, True, min_tick, max_tick)
        self.assertEqual(res[0], 416666666666666)
        self.assertEqual(res[1], 0)

        res = await new_contract.collect(address, min_tick, max_tick, MAX_UINT128, MAX_UINT128).execute(caller_address=address)
        res = await self.swap_and_get_fees_owed(new_contract, expand_to_18decimals(1), True, False, min_tick, max_tick)
        self.assertEqual(res[0], 0)
        self.assertEqual(res[1], 0)

        res = await new_contract.get_protocol_fees().call()
        token0_fee = res.call_info.result[0]
        token1_fee = res.call_info.result[1] 
        self.assertEqual(token0_fee, 166666666666666)
        self.assertEqual(token1_fee, 0)

        await new_contract.remove_liquidity(min_tick, max_tick, 0).execute(caller_address=address)
        res = await new_contract.collect(address, min_tick, max_tick, MAX_UINT128, MAX_UINT128).execute(caller_address=address)
        assert_event_emitted(
            res,
            from_address=new_contract.contract_address,
            name='TransferToken',
            data=[
                self.token0.contract_address,
                address, 
                416666666666666,
                0
            ]
        )

        res = await new_contract.get_protocol_fees().call()
        token0_fee = res.call_info.result[0]
        token1_fee = res.call_info.result[1] 
        self.assertEqual(token0_fee, 166666666666666)
        self.assertEqual(token1_fee, 0)

    @pytest.mark.asyncio
    async def test_tick_spacing(self):
        tick_spacing = 12
        await self.check_starknet()
        contract_def, contract = await init_contract(CONTRACT_FILE, [tick_spacing, FeeAmount.MEDIUM, self.token0.contract_address, self.token1.contract_address, address], self.starknet)
        min_tick, max_tick = get_min_tick(tick_spacing), get_max_tick(tick_spacing)
        await contract.initialize(encode_price_sqrt(1, 1)).execute()

        # mint can only be called for multiples of 12
        await assert_revert(
            contract.add_liquidity(address, -6, 0, 1, address).execute(),
            'tick must be multiples of tick_spacing'
        )
        await assert_revert(
            contract.add_liquidity(address, 0, 6, 1, address).execute(),
            'tick must be multiples of tick_spacing'
        )

        # mint can be called with multiples of 12
        state = contract.state.copy()
        new_contract = cached_contract(state, contract_def, contract)
        new_swap_target = cached_contract(state, self.swap_target_def, self.swap_target)
        res = await self.add_liquidity(new_swap_target, new_contract, address, 12, 24, 1)
        res = await self.add_liquidity(new_swap_target, new_contract, address, -144, -120, 1)

        #TODO: swapping across gaps works in 1 for 0 direction
        #new_contract = cached_contract(contract.state.copy(), contract_def, contract)
        #liquidity_amount = expand_to_18decimals(1) // 4
        #await new_contract.add_liquidity(address, 120000, 121200, liquidity_amount).execute()
        #await self.swap_exact1_for0(contract, expand_to_18decimals(1), address)
        #res = await new_contract.remove_liquidity(120000, 121200, liquidity_amount).execute(caller_address=address)
        #await assert_event_emitted(
        #    res,
        #    from_address=new_contract.contract_address,
        #    name='RemoveLiquidity',
        #    data=[
        #        address,
        #        120000, 
        #        121200,
        #        liquidity_amount,
        #        30027458295511,
        #        0,
        #        996999999999999999,
        #        0
        #    ]
        #)
        #res = await new_contract.get_cur_slot().call()
        #tick = felt_to_int(res.call_info.result[2])
        #self.assertEqual(tick, 120196)

        # swapping across gaps works in 0 for 1 direction
        #new_contract = cached_contract(contract.state.copy(), contract_def, contract)
        #liquidity_amount = expand_to_18decimals(1) // 4
        #await new_contract.add_liquidity(address, -121200, 120000, liquidity_amount).execute()
        #await self.swap_exact0_for1(contract, expand_to_18decimals(1), address)
        #res = await new_contract.remove_liquidity(-121200, 120000, liquidity_amount).execute(caller_address=address)
        #await assert_event_emitted(
        #    res,
        #    from_address=new_contract.contract_address,
        #    name='RemoveLiquidity',
        #    data=[
        #        address,
        #        120000, 
        #        121200,
        #        liquidity_amount,
        #        996999999999999999,
        #        0,
        #        30027458295511,
        #        0,
        #    ]
        #)
        #res = await new_contract.get_cur_slot().call()
        #tick = felt_to_int(res.call_info.result[2])
        #self.assertEqual(tick, -120197)

    '''
    @pytest.mark.asyncio
    async def test_issue(self):

        # tick transition cannot run twice if zero for one swap ends at fractional price just below tick
        tick_spacing = 1
        contract_def, contract = await init_contract(CONTRACT_FILE, [tick_spacing, FeeAmount.MEDIUM, token0, token1])
        min_tick, max_tick = get_min_tick(tick_spacing), get_max_tick(tick_spacing)
        await contract.initialize(encode_price_sqrt(1, 1)).execute()

        # mint can only be called for multiples of 12

        it('tick transition cannot run twice if zero for one swap ends at fractional price just below tick', async () => {
    pool = await createPool(FeeAmount.MEDIUM, 1)
    const sqrtTickMath = (await (await ethers.getContractFactory('TickMathTest')).deploy()) as TickMathTest
    const swapMath = (await (await ethers.getContractFactory('SwapMathTest')).deploy()) as SwapMathTest
    const p0 = (await sqrtTickMath.getSqrtRatioAtTick(-24081)).add(1)
    // initialize at a price of ~0.3 token1/token0
    // meaning if you swap in 2 token0, you should end up getting 0 token1
    await pool.initialize(p0)
    expect(await pool.liquidity(), 'current pool liquidity is 1').to.eq(0)
    expect((await pool.slot0()).tick, 'pool tick is -24081').to.eq(-24081)

    // add a bunch of liquidity around current price
    const liquidity = expandTo18Decimals(1000)
    await mint(wallet.address, -24082, -24080, liquidity)
    expect(await pool.liquidity(), 'current pool liquidity is now liquidity + 1').to.eq(liquidity)

    await mint(wallet.address, -24082, -24081, liquidity)
    expect(await pool.liquidity(), 'current pool liquidity is still liquidity + 1').to.eq(liquidity)

    // check the math works out to moving the price down 1, sending no amount out, and having some amount remaining
    {
      const { feeAmount, amountIn, amountOut, sqrtQ } = await swapMath.computeSwapStep(
        p0,
        p0.sub(1),
        liquidity,
        3,
        FeeAmount.MEDIUM
      )
      expect(sqrtQ, 'price moves').to.eq(p0.sub(1))
      expect(feeAmount, 'fee amount is 1').to.eq(1)
      expect(amountIn, 'amount in is 1').to.eq(1)
      expect(amountOut, 'zero amount out').to.eq(0)
    }

    // swap 2 amount in, should get 0 amount out
    await expect(swapExact0For1(3, wallet.address))
      .to.emit(token0, 'Transfer')
      .withArgs(wallet.address, pool.address, 3)
      .to.not.emit(token1, 'Transfer')

    const { tick, sqrtPriceX96 } = await pool.slot0()

    expect(tick, 'pool is at the next tick').to.eq(-24082)
    expect(sqrtPriceX96, 'pool price is still on the p0 boundary').to.eq(p0.sub(1))
    expect(await pool.liquidity(), 'pool has run tick transition and liquidity changed').to.eq(liquidity.mul(2))
  })
    '''

    @pytest.mark.asyncio
    async def test_set_fee_protocol(self):
        contract, swap_target = await self.get_state_contract()
        constract = await self.initialize_at_zero_tick(contract, swap_target)

        # fails if fee is lt 4 or gt 10
        await assert_revert(
            contract.set_fee_protocol(3, 3).execute(caller_address=address),
            ""
        )
        await assert_revert(
            contract.set_fee_protocol(6, 3).execute(caller_address=address),
            ""
        )
        await assert_revert(
            contract.set_fee_protocol(3, 6).execute(caller_address=address),
            ""
        )
        await assert_revert(
            contract.set_fee_protocol(11, 11).execute(caller_address=address),
            ""
        )
        await assert_revert(
            contract.set_fee_protocol(6, 11).execute(caller_address=address),
            ""
        )
        await assert_revert(
            contract.set_fee_protocol(11, 6).execute(caller_address=address),
            ""
        )

        await assert_revert(
            contract.set_fee_protocol(6, 6).execute(caller_address=other_address),
            ""
        )

        await contract.set_fee_protocol(10, 10).execute(caller_address=address)

        await contract.set_fee_protocol(7, 7).execute(caller_address=address)
        res = await contract.get_fee_protocol().call()
        self.assertEqual(res.call_info.result[0], 119)

        await contract.set_fee_protocol(5, 8).execute(caller_address=address)
        res = await contract.get_fee_protocol().call()
        self.assertEqual(res.call_info.result[0], 133)

        await contract.set_fee_protocol(0, 0).execute(caller_address=address)
        res = await contract.get_fee_protocol().call()
        self.assertEqual(res.call_info.result[0], 0)

        res = await contract.set_fee_protocol(5, 8).execute(caller_address=address)
        assert_event_emitted(
            res,
            from_address=contract.contract_address,
            name='SetFeeProtocol',
            data=[
                5,
                8,
                133
            ]
        )
