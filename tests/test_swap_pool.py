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
    MAX_UINT256, assert_revert, add_uint, sub_uint,
    mul_uint, div_rem_uint, to_uint, contract_path,
    felt_to_int, int_to_felt, from_uint, cached_contract, encode_price_sqrt,
    get_max_tick, get_min_tick, TICK_SPACINGS, FeeAmount
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

async def init_contract():
    begin = time.time()
    starknet = await Starknet.empty()
    print('create starknet time:', time.time() - begin)
    begin = time.time()
    compiled_contract = compile_starknet_files(
        [CONTRACT_FILE], debug_info=True, disable_hint_validation=True
    )
    print('compile contract time:', time.time() - begin)

    kwargs = {
        "contract_class": compiled_contract,
        "constructor_calldata": [tick_spacing, 0]
        }

    begin = time.time()
    contract = await starknet.deploy(**kwargs)
    print('deploy contract time:', time.time() - begin)

    return compiled_contract, contract

class SwapPoolTest(TestCase):

    @classmethod
    async def setUp(cls):
        if not hasattr(cls, 'contract_def'):
            cls.contract_def, cls.contract = await init_contract()

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
    '''

    @pytest.mark.asyncio
    async def test_add_liquidity_succuss(self):
        contract = self.get_state_contract()
        price = to_uint(25054144837504793118650146401)
        await contract.initialize(price).invoke()
        await contract.add_liquidity(address, min_tick, max_tick, 3161).invoke()

        res = await contract.get_cur_slot().call()
        tick = felt_to_int(res.call_info.result[2])
        self.assertEqual(tick, -23028)

        await contract.add_liquidity(address, -22980, 0, 10000).invoke()

    '''
    it('initial balances', async () => {
          expect(await token0.balanceOf(pool.address)).to.eq(9996)
          expect(await token1.balanceOf(pool.address)).to.eq(1000)
        })

        describe('above current price', () => {
          it('transfers token0 only', async () => {
            await expect(mint(wallet.address, -22980, 0, 10000))
              .to.emit(token0, 'Transfer')
              .withArgs(wallet.address, pool.address, 21549)
              .to.not.emit(token1, 'Transfer')
            expect(await token0.balanceOf(pool.address)).to.eq(9996 + 21549)
            expect(await token1.balanceOf(pool.address)).to.eq(1000)
          })

          it('max tick with max leverage', async () => {
            await mint(wallet.address, max_tick - tickSpacing, max_tick, BigNumber.from(2).pow(102))
            expect(await token0.balanceOf(pool.address)).to.eq(9996 + 828011525)
            expect(await token1.balanceOf(pool.address)).to.eq(1000)
          })

          it('works for max tick', async () => {
            await expect(mint(wallet.address, -22980, max_tick, 10000))
              .to.emit(token0, 'Transfer')
              .withArgs(wallet.address, pool.address, 31549)
            expect(await token0.balanceOf(pool.address)).to.eq(9996 + 31549)
            expect(await token1.balanceOf(pool.address)).to.eq(1000)
          })

          it('removing works', async () => {
            await mint(wallet.address, -240, 0, 10000)
            await pool.burn(-240, 0, 10000)
            const { amount0, amount1 } = await pool.callStatic.collect(wallet.address, -240, 0, MaxUint128, MaxUint128)
            expect(amount0, 'amount0').to.eq(120)
            expect(amount1, 'amount1').to.eq(0)
          })

          it('adds liquidity to liquidityGross', async () => {
            await mint(wallet.address, -240, 0, 100)
            expect((await pool.ticks(-240)).liquidityGross).to.eq(100)
            expect((await pool.ticks(0)).liquidityGross).to.eq(100)
            expect((await pool.ticks(tickSpacing)).liquidityGross).to.eq(0)
            expect((await pool.ticks(tickSpacing * 2)).liquidityGross).to.eq(0)
            await mint(wallet.address, -240, tickSpacing, 150)
            expect((await pool.ticks(-240)).liquidityGross).to.eq(250)
            expect((await pool.ticks(0)).liquidityGross).to.eq(100)
            expect((await pool.ticks(tickSpacing)).liquidityGross).to.eq(150)
            expect((await pool.ticks(tickSpacing * 2)).liquidityGross).to.eq(0)
            await mint(wallet.address, 0, tickSpacing * 2, 60)
            expect((await pool.ticks(-240)).liquidityGross).to.eq(250)
            expect((await pool.ticks(0)).liquidityGross).to.eq(160)
            expect((await pool.ticks(tickSpacing)).liquidityGross).to.eq(150)
            expect((await pool.ticks(tickSpacing * 2)).liquidityGross).to.eq(60)
          })

          it('removes liquidity from liquidityGross', async () => {
            await mint(wallet.address, -240, 0, 100)
            await mint(wallet.address, -240, 0, 40)
            await pool.burn(-240, 0, 90)
            expect((await pool.ticks(-240)).liquidityGross).to.eq(50)
            expect((await pool.ticks(0)).liquidityGross).to.eq(50)
          })

          it('clears tick lower if last position is removed', async () => {
            await mint(wallet.address, -240, 0, 100)
            await pool.burn(-240, 0, 100)
            const { liquidityGross, feeGrowthOutside0X128, feeGrowthOutside1X128 } = await pool.ticks(-240)
            expect(liquidityGross).to.eq(0)
            expect(feeGrowthOutside0X128).to.eq(0)
            expect(feeGrowthOutside1X128).to.eq(0)
          })

          it('clears tick upper if last position is removed', async () => {
            await mint(wallet.address, -240, 0, 100)
            await pool.burn(-240, 0, 100)
            const { liquidityGross, feeGrowthOutside0X128, feeGrowthOutside1X128 } = await pool.ticks(0)
            expect(liquidityGross).to.eq(0)
            expect(feeGrowthOutside0X128).to.eq(0)
            expect(feeGrowthOutside1X128).to.eq(0)
          })
          it('only clears the tick that is not used at all', async () => {
            await mint(wallet.address, -240, 0, 100)
            await mint(wallet.address, -tickSpacing, 0, 250)
            await pool.burn(-240, 0, 100)

            let { liquidityGross, feeGrowthOutside0X128, feeGrowthOutside1X128 } = await pool.ticks(-240)
            expect(liquidityGross).to.eq(0)
            expect(feeGrowthOutside0X128).to.eq(0)
            expect(feeGrowthOutside1X128).to.eq(0)
            ;({ liquidityGross, feeGrowthOutside0X128, feeGrowthOutside1X128 } = await pool.ticks(-tickSpacing))
            expect(liquidityGross).to.eq(250)
            expect(feeGrowthOutside0X128).to.eq(0)
            expect(feeGrowthOutside1X128).to.eq(0)
          })

          it('does not write an observation', async () => {
            checkObservationEquals(await pool.observations(0), {
              tickCumulative: 0,
              blockTimestamp: TEST_POOL_START_TIME,
              initialized: true,
              secondsPerLiquidityCumulativeX128: 0,
            })
            await pool.advanceTime(1)
            await mint(wallet.address, -240, 0, 100)
            checkObservationEquals(await pool.observations(0), {
              tickCumulative: 0,
              blockTimestamp: TEST_POOL_START_TIME,
              initialized: true,
              secondsPerLiquidityCumulativeX128: 0,
            })
          })
    '''