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
    MAX_UINT128, assert_revert, to_uint,
    felt_to_int, from_uint, cached_contract, encode_price_sqrt,
    get_max_tick, get_min_tick, TICK_SPACINGS, FeeAmount, init_contract,
    assert_event_emitted, Account
)

from test_tickmath import (MIN_SQRT_RATIO, MAX_SQRT_RATIO)
from signers import MockSigner

signer = MockSigner(123456789987654321)
other_signer = MockSigner(2343424234234)

Q128 = to_uint(2 ** 128)
MaxUint256 = to_uint(2 ** 256 - 1)

NFT_NAME = 111
NFT_SYMBOL = 222

# The path to the contract source code.

tick_spacing = TICK_SPACINGS[FeeAmount.MEDIUM]
min_tick = get_min_tick(tick_spacing)
max_tick = get_max_tick(tick_spacing)

address = 11111111111111
other_address = 222222222222222

DEADLINE = int(time.time() + 1000)

#TODO: check two diferent address with same position tick, burn and collect
async def init_user_position_contract(starknet, swap_pool_hash, swap_pool_proxy_hash):
    begin = time.time()
    compiled_contract = compile_starknet_files(
        ['contracts/user_position_mgr.cairo'], debug_info=True, disable_hint_validation=True
    )
    print('compile user_position time:', time.time() - begin)

    begin = time.time()
    declare_class = await starknet.declare(
        contract_class=compiled_contract,
    )
    print('declare user_position_mgr time:', time.time() - begin)

    begin = time.time()
    compiled_proxy = compile_starknet_files(
        ['contracts/user_position_mgr_proxy.cairo'], debug_info=True, disable_hint_validation=True
    )
    print('compile user_position time:', time.time() - begin)

    kwargs = {
        "contract_class": compiled_proxy,
        "constructor_calldata": [declare_class.class_hash, address, swap_pool_hash, swap_pool_proxy_hash, NFT_NAME, NFT_SYMBOL]
        }

    begin = time.time()
    contract = await starknet.deploy(**kwargs)
    print('deploy user_position time:', time.time() - begin)

    # replace api
    contract = contract.replace_abi(compiled_contract.abi)

    return compiled_contract, declare_class, compiled_proxy, contract

async def init_swap_pool_class(starknet):

    begin = time.time()
    compiled_contract = compile_starknet_files(
        ['contracts/swap_pool.cairo'], debug_info=True, disable_hint_validation=True
    )
    print('compile swap_pool time:', time.time() - begin)

    begin = time.time()
    declared_contract = await starknet.declare(
        contract_class=compiled_contract,
    )
    print('declare swap_pool time:', time.time() - begin)

    begin = time.time()
    compiled_proxy = compile_starknet_files(
        ['contracts/swap_pool_proxy.cairo'], debug_info=True, disable_hint_validation=True
    )
    print('compile swap_pool_proxy time:', time.time() - begin)

    begin = time.time()
    declared_proxy = await starknet.declare(
        contract_class=compiled_proxy,
    )
    print('declare swap_pool time:', time.time() - begin)
    return declared_contract, declared_proxy

class UserPositionMgrTest(TestCase):

    @classmethod
    async def setUp(cls):
        pass

    async def check_starknet(self):
        if not hasattr(self, 'starknet'):
            self.starknet = await Starknet.empty()
            # token0
            self.token0_def, self.token0 = await init_contract(os.path.join("tests", "mocks/ERC20_mock.cairo"), [1, 1, 18, MAX_UINT128, MAX_UINT128, address], starknet=self.starknet)
            await self.token0.transfer(other_address, (MAX_UINT128, 2 ** 127)).execute(caller_address=address)
            # token1
            self.token1_def, self.token1 = await init_contract(os.path.join("tests", "mocks/ERC20_mock.cairo"), [2, 2, 18, MAX_UINT128, MAX_UINT128, address], starknet=self.starknet)
            await self.token1.transfer(other_address, (MAX_UINT128, 2 ** 127)).execute(caller_address=address)
            # token2
            self.token2_def, self.token2 = await init_contract(os.path.join("tests", "mocks/ERC20_mock.cairo"), [1, 1, 18, MAX_UINT128, MAX_UINT128, address], starknet=self.starknet)
            await self.token2.transfer(other_address, (MAX_UINT128, 2 ** 127)).execute(caller_address=address)

            if self.token0.contract_address > self.token1.contract_address:
                self.token0, self.token1 = self.token1, self.token0
                self.token0_def, self.token1_def = self.token1_def, self.token0_def


    async def get_user_position_contract(self):
        await self.check_starknet()

        if not hasattr(self, 'user_position'):
            # swap pool
            self.swap_pool_class, self.swap_pool_proxy_class = await init_swap_pool_class(self.starknet)

            self.user_position_def, self.user_position_class, self.proxy_def, self.user_position = await init_user_position_contract(self.starknet, self.swap_pool_class.class_hash, self.swap_pool_proxy_class.class_hash)

            res = await self.user_position.create_and_initialize_pool(self.token0.contract_address, self.token1.contract_address, FeeAmount.MEDIUM, encode_price_sqrt(1, 1)).execute()
            self.swap_pool_address = res.call_info.result[0]

            res = await self.user_position.create_and_initialize_pool(self.token1.contract_address, self.token2.contract_address, FeeAmount.MEDIUM, encode_price_sqrt(1, 1)).execute()

            self.swap_pool_address2 = res.call_info.result[0]

            await self.token0.approve(self.user_position.contract_address, to_uint(2 ** 256 - 1)).execute(caller_address=address)
            await self.token1.approve(self.user_position.contract_address, to_uint(2 ** 256 - 1)).execute(caller_address=address)
            await self.token2.approve(self.user_position.contract_address, to_uint(2 ** 256 - 1)).execute(caller_address=address)

            await self.token0.approve(self.user_position.contract_address, to_uint(2 ** 256 - 1)).execute(caller_address=other_address)
            await self.token1.approve(self.user_position.contract_address, to_uint(2 ** 256 - 1)).execute(caller_address=other_address)
            await self.token2.approve(self.user_position.contract_address, to_uint(2 ** 256 - 1)).execute(caller_address=other_address)

        state = self.user_position.state.copy()
        user_position = cached_contract(state, self.user_position_def, self.user_position)

        #swap_pool = cached_contract(state, self.swap_pool_def, self.swap_pool)

        return user_position

    @pytest.mark.asyncio
    async def test_upgrade(self):
        user_position = await self.get_user_position_contract()

        user_position = user_position.replace_abi(self.proxy_def.abi)

        await assert_revert(
            user_position.upgrade(111).execute(caller_address=other_address),
            ""
        )

        # upgrade wrong class_hash
        await user_position.upgrade(111).execute(caller_address=address)

        user_position = user_position.replace_abi(self.user_position_def.abi)
        await assert_revert(
            user_position.mint(other_address, self.token0.contract_address, self.token1.contract_address, FeeAmount.MEDIUM, min_tick, max_tick, to_uint(15), to_uint(15), to_uint(0), to_uint(0), DEADLINE).execute(caller_address=other_address),
            ''
        )

        # upgrade right class_hash
        user_position = user_position.replace_abi(self.proxy_def.abi)
        await user_position.upgrade(self.user_position_class.class_hash).execute(caller_address=address)

        user_position = user_position.replace_abi(self.user_position_def.abi)
        await user_position.mint(other_address, self.token0.contract_address, self.token1.contract_address, FeeAmount.MEDIUM, min_tick, max_tick, to_uint(15), to_uint(15), to_uint(0), to_uint(0), DEADLINE).execute(caller_address=other_address)

    @pytest.mark.asyncio
    async def test_initializer(self):
        user_position = await self.get_user_position_contract()
        await assert_revert(
            user_position.initializer(address, 111, 222, NFT_NAME, NFT_SYMBOL).execute(caller_address=address),
            ""
        )

    @pytest.mark.asyncio
    async def test_mint(self):

        user_position = await self.get_user_position_contract()

        await assert_revert(
            user_position.mint(other_address, self.token1.contract_address, self.token0.contract_address, FeeAmount.MEDIUM, min_tick, max_tick, to_uint(15), to_uint(15), to_uint(0), to_uint(0), DEADLINE).execute(caller_address=other_address),
            "token0 address should be less than token1 address"
        )

        res = await user_position.mint(other_address, self.token0.contract_address, self.token1.contract_address, FeeAmount.MEDIUM, min_tick, max_tick, to_uint(15), to_uint(15), to_uint(0), to_uint(0), DEADLINE).execute(caller_address=other_address)

        # check nft
        res = await user_position.balanceOf(other_address).call()
        self.assertEqual(res.call_info.result[0], 1)
        res = await user_position.tokenOfOwnerByIndex(other_address, to_uint(0)).call()
        self.assertEqual(from_uint(res.call_info.result[0: 2]), 1)

        res = await user_position.get_token_position(to_uint(1)).call()
        position = res.call_info.result
        self.assertEqual(felt_to_int(position[1]), min_tick) # tick_lower
        self.assertEqual(position[2], max_tick) # tick_upper
        self.assertEqual(position[3], 15) # liquidity
        self.assertEqual(from_uint(position[4: 6]), 0) # feeGrowthInside0LastX128
        self.assertEqual(from_uint(position[6: 8]), 0) # feeGrowthInside1LastX128
        self.assertEqual(position[8], 0) # tokens_owed0
        self.assertEqual(position[9], 0) # tokens_owed1

    @pytest.mark.asyncio
    async def test_increase_liquidity(self):
        user_position = await self.get_user_position_contract()
        res = await user_position.mint(other_address, self.token0.contract_address, self.token1.contract_address, FeeAmount.MEDIUM, min_tick, max_tick, to_uint(1000), to_uint(1000), to_uint(0), to_uint(0), DEADLINE).execute(caller_address=other_address)

        token_id = to_uint(1)

        # increases position liquidity
        res = await user_position.increase_liquidity(token_id, to_uint(100), to_uint(100), to_uint(0), to_uint(0), DEADLINE).execute(caller_address=other_address)
        res = await user_position.get_token_position(to_uint(1)).call()
        position = res.call_info.result
        self.assertEqual(position[3], 1100) # liquidity

    @pytest.mark.asyncio
    async def test_get_position_token(self):
        user_position = await self.get_user_position_contract()
        res = await user_position.mint(other_address, self.token0.contract_address, self.token1.contract_address, FeeAmount.MEDIUM, min_tick, max_tick, to_uint(100000000), to_uint(100000000), to_uint(0), to_uint(0), DEADLINE).execute(caller_address=other_address)
        amount0 = from_uint(res.call_info.result[0: 2])
        amount1 = from_uint(res.call_info.result[2: 4])

        res = await user_position.mint(address, self.token0.contract_address, self.token1.contract_address, FeeAmount.MEDIUM, min_tick, max_tick, to_uint(100000), to_uint(100000), to_uint(0), to_uint(0), DEADLINE).execute(caller_address=address)

        token_id = to_uint(1)

        # check the liquidity amount before swap
        res = await user_position.get_position_token_amounts(token_id).call()
        token0_amount = from_uint(res.call_info.result[0: 2])
        token1_amount = from_uint(res.call_info.result[2: 4])
        token0_fee = res.call_info.result[4]
        token1_fee = res.call_info.result[5]
        print('before_swap:', token0_amount, token1_amount, token0_fee, token1_fee)
        self.assertEqual(token0_amount <= amount0, True)
        self.assertEqual(token1_amount <= amount1, True)
        self.assertEqual(token0_amount >= amount0 - 1, True)
        self.assertEqual(token1_amount >= amount1 - 1, True)
        self.assertEqual(token0_fee, 0)
        self.assertEqual(token1_fee, 0)

        # swap
        amount_in = 300000
        amount_out_min = 1

        price = 4295128740
        res = await user_position.exact_input(self.token0.contract_address, self.token1.contract_address, FeeAmount.MEDIUM, address, to_uint(amount_in), to_uint(price), to_uint(amount_out_min), DEADLINE).execute(caller_address=address)

        price = 1461446703485210103287273052203988822378723970341
        res = await user_position.exact_input(self.token1.contract_address, self.token0.contract_address, FeeAmount.MEDIUM, address, to_uint(amount_in * 2), to_uint(price), to_uint(amount_out_min), DEADLINE).execute(caller_address=address)

        res = await user_position.get_position_token_amounts(token_id).call()
        token0_amount = from_uint(res.call_info.result[0: 2])
        token1_amount = from_uint(res.call_info.result[2: 4])
        token0_fee = res.call_info.result[4]
        token1_fee = res.call_info.result[5]
        print('after_swap:', token0_amount, token1_amount, token0_fee, token1_fee)

        res = await user_position.collect(token_id, address, MAX_UINT128, MAX_UINT128).execute(caller_address=other_address)
        self.assertEqual(token0_fee, from_uint(res.call_info.result[0: 2]))
        self.assertEqual(token1_fee, from_uint(res.call_info.result[2: 4]))

        res = await user_position.get_token_position(token_id).call()
        liquidity = res.call_info.result[3]
        res = await user_position.decrease_liquidity(token_id, liquidity, to_uint(0), to_uint(0), DEADLINE).execute(caller_address=other_address)
        res = await user_position.collect(token_id, address, MAX_UINT128, MAX_UINT128).execute(caller_address=other_address)
        self.assertEqual(token0_amount, from_uint(res.call_info.result[0: 2]))
        self.assertEqual(token1_amount, from_uint(res.call_info.result[2: 4]))

    @pytest.mark.asyncio
    async def test_decrease_liquidity(self):
        user_position = await self.get_user_position_contract()
        res = await user_position.mint(other_address, self.token0.contract_address, self.token1.contract_address, FeeAmount.MEDIUM, min_tick, max_tick, to_uint(100), to_uint(100), to_uint(0), to_uint(0), DEADLINE).execute(caller_address=other_address)

        token_id = to_uint(1)

        # cannot be called by other addresses
        await assert_revert(
            user_position.decrease_liquidity(token_id, 50, to_uint(0), to_uint(0), DEADLINE).execute(caller_address=address),
            "_check_approverd_or_owner failed"
        )

        # cannot decrease for more than all the liquidity
        await assert_revert(
            user_position.decrease_liquidity(token_id, 101, to_uint(0), to_uint(0), DEADLINE).execute(caller_address=other_address),
            "DL: liquidity is more than own"
        )

        # decreases position liquidity
        new_user_position = cached_contract(user_position.state.copy(), self.user_position_def, user_position)
        res = await new_user_position.decrease_liquidity(token_id, 25, to_uint(0), to_uint(0), DEADLINE).execute(caller_address=other_address)
        res = await new_user_position.get_token_position(to_uint(1)).call()
        position = res.call_info.result
        self.assertEqual(position[3], 75)
        self.assertEqual(position[8], 24) # tokens_owed0
        self.assertEqual(position[9], 24) # tokens_owed1

        # can decrease for all the liquidity
        new_user_position = cached_contract(user_position.state.copy(), self.user_position_def, user_position)
        res = await new_user_position.decrease_liquidity(token_id, 100, to_uint(0), to_uint(0), DEADLINE).execute(caller_address=other_address)
        res = await new_user_position.get_token_position(to_uint(1)).call()
        position = res.call_info.result
        self.assertEqual(position[3], 0)

        # cannot decrease for more than the liquidity of the nft position
        new_user_position = cached_contract(user_position.state.copy(), self.user_position_def, user_position)
        res = await new_user_position.mint(other_address, self.token0.contract_address, self.token1.contract_address, FeeAmount.MEDIUM, min_tick, max_tick, to_uint(200), to_uint(100), to_uint(0), to_uint(0), DEADLINE).execute(caller_address=other_address)
        await assert_revert(
            new_user_position.decrease_liquidity(token_id, 101, to_uint(0), to_uint(0), DEADLINE).execute(caller_address=other_address),
            "DL: liquidity is more than own"
        )

    @pytest.mark.asyncio
    async def test_collect(self):
        user_position = await self.get_user_position_contract()
        res = await user_position.mint(other_address, self.token0.contract_address, self.token1.contract_address, FeeAmount.MEDIUM, min_tick, max_tick, to_uint(50), to_uint(50), to_uint(0), to_uint(0), DEADLINE).execute(caller_address=other_address)
        res = await user_position.mint(address, self.token0.contract_address, self.token1.contract_address, FeeAmount.MEDIUM, min_tick, max_tick, to_uint(50), to_uint(50), to_uint(0), to_uint(0), DEADLINE).execute(caller_address=address)

        token_id = to_uint(1)

        # cannot be called by other addresses
        await assert_revert(
            user_position.collect(token_id, address, MAX_UINT128, MAX_UINT128).execute(caller_address=address),
            "_check_approverd_or_owner failed"
        )

        # cannot be called with 0 for both amounts
        await assert_revert(
            user_position.collect(token_id, address, 0, 0).execute(caller_address=address),
            ""
        )

        # transfers tokens owed from burn
        res = await user_position.decrease_liquidity(token_id, 50, to_uint(0), to_uint(0), DEADLINE).execute(caller_address=other_address)
        res = await user_position.collect(token_id, address, MAX_UINT128, MAX_UINT128).execute(caller_address=other_address)
        assert_event_emitted(
            res,
            from_address=self.swap_pool_address,
            name='TransferToken',
            data=[
                self.token0.contract_address,
                address, 
                49,
                0
            ]
        )
        assert_event_emitted(
            res,
            from_address=self.swap_pool_address,
            name='TransferToken',
            data=[
                self.token1.contract_address,
                address, 
                49,
                0
            ]
        )

    @pytest.mark.asyncio
    async def test_burn(self):
        user_position = await self.get_user_position_contract()
        res = await user_position.mint(other_address, self.token0.contract_address, self.token1.contract_address, FeeAmount.MEDIUM, min_tick, max_tick, to_uint(100), to_uint(100), to_uint(0), to_uint(0), DEADLINE).execute(caller_address=other_address)

        token_id = to_uint(1)

        # cannot be called by other addresses
        await assert_revert(
            user_position.burn(token_id).execute(caller_address=address),
            "_check_approverd_or_owner failed"
        )

        # cannot be called while there is still liquidity
        await assert_revert(
            user_position.burn(token_id).execute(caller_address=other_address),
            "user_position_mgr: position not clear"
        )

        # cannot be called while there is still partial liquidity
        new_user_position = cached_contract(user_position.state.copy(), self.user_position_def, user_position)
        res = await new_user_position.decrease_liquidity(token_id, 50, to_uint(0), to_uint(0), DEADLINE).execute(caller_address=other_address)
        await assert_revert(
            new_user_position.burn(token_id).execute(caller_address=other_address),
            "user_position_mgr: position not clear"
        )

        # cannot be called while there is still tokens owed
        new_user_position = cached_contract(user_position.state.copy(), self.user_position_def, user_position)
        res = await new_user_position.decrease_liquidity(token_id, 100, to_uint(0), to_uint(0), DEADLINE).execute(caller_address=other_address)
        await assert_revert(
            new_user_position.burn(token_id).execute(caller_address=other_address),
            "user_position_mgr: position not clear"
        )

        # cannot be called while there is still tokens owed
        res = await user_position.decrease_liquidity(token_id, 100, to_uint(0), to_uint(0), DEADLINE).execute(caller_address=other_address)
        res = await user_position.collect(token_id, address, MAX_UINT128, MAX_UINT128).execute(caller_address=other_address)
        #await erc721.approve(user_position.contract_address, token_id).execute(caller_address=other_address)
        res = await user_position.burn(token_id).execute(caller_address=other_address)
        await assert_revert(
            user_position.get_token_position(token_id).call(),
            "invalid token id"
        )

    async def get_balance(self, token0, token1, address):
        balance0 = from_uint((await token0.balanceOf(address).call()).call_info.result[0: 2])
        balance1 = from_uint((await token1.balanceOf(address).call()).call_info.result[0: 2])
        return balance0, balance1

    @pytest.mark.asyncio
    async def test_exact_input(self):
        user_position = await self.get_user_position_contract()

        res = await user_position.mint(other_address, self.token0.contract_address, self.token1.contract_address, FeeAmount.MEDIUM, min_tick, max_tick, to_uint(1000000), to_uint(1000000), to_uint(0), to_uint(0), DEADLINE).execute(caller_address=address)

        amount_in = 3
        amount_out_min = 1

        price = 4295128740
        if self.token0.contract_address > self.token1.contract_address:
            price = 1461446703485210103287273052203988822378723970341

        # token0 -> token1
        new_user_position = cached_contract(user_position.state.copy(), self.user_position_def, user_position)
        token0 = cached_contract(new_user_position.state, self.token0_def, self.token0)
        token1 = cached_contract(new_user_position.state, self.token1_def, self.token1)
        pool_before = await self.get_balance(token0, token1, self.swap_pool_address)
        trader_before = await self.get_balance(token0, token1, address)
        print('balance:', pool_before, trader_before)

        deadline = int(time.time() + 1000)
        #await assert_revert(
        #    new_user_position.exact_input(self.token0.contract_address, self.token1.contract_address, FeeAmount.MEDIUM, address, to_uint(amount_in), to_uint(price), to_uint(amount_out_min + 1), 0).execute(caller_address=address),
        #    "deadline"
        #)

        await assert_revert(
            new_user_position.exact_input(self.token0.contract_address, self.token1.contract_address, FeeAmount.MEDIUM, address, to_uint(amount_in), to_uint(price), to_uint(amount_out_min + 1), deadline).execute(caller_address=address),
            "too little received"
        )

        res = await new_user_position.get_exact_input(self.token0.contract_address, self.token1.contract_address, FeeAmount.MEDIUM, to_uint(amount_in)).execute(caller_address=address)
        expect_amount_out = from_uint(res.call_info.result[0: 2])

        res = await new_user_position.exact_input(self.token0.contract_address, self.token1.contract_address, FeeAmount.MEDIUM, address, to_uint(amount_in), to_uint(price), to_uint(amount_out_min), deadline).execute(caller_address=address)
        amount_out = from_uint(res.call_info.result[0: 2])
        self.assertEqual(amount_out, expect_amount_out)

        pool_after = await self.get_balance(token0, token1, self.swap_pool_address)
        trader_after = await self.get_balance(token0, token1, address)
        print('balance after:', pool_after, trader_after)

        self.assertEqual(trader_after[0], trader_before[0] - 3)
        self.assertEqual(trader_after[1], trader_before[1] + 1)
        self.assertEqual(pool_after[0], pool_before[0] + 3)
        self.assertEqual(pool_after[1], pool_before[1] - 1)

        # token1 -> token0
        new_user_position = cached_contract(user_position.state.copy(), self.user_position_def, user_position)
        token0 = cached_contract(new_user_position.state, self.token0_def, self.token0)
        token1 = cached_contract(new_user_position.state, self.token1_def, self.token1)
        pool_before = await self.get_balance(token0, token1, self.swap_pool_address)
        trader_before = await self.get_balance(token0, token1, address)
        print('balance:', pool_before, trader_before)

        price = 4295128740
        if self.token1.contract_address > self.token0.contract_address:
            price = 1461446703485210103287273052203988822378723970341

        await assert_revert(
            new_user_position.exact_input(self.token1.contract_address, self.token0.contract_address, FeeAmount.MEDIUM, address, to_uint(amount_in), to_uint(price), to_uint(amount_out_min + 1), deadline).execute(caller_address=address),
            "too little received"
        )

        res = await new_user_position.get_exact_input(self.token1.contract_address, self.token0.contract_address, FeeAmount.MEDIUM, to_uint(amount_in)).execute(caller_address=address)
        expect_amount_out = from_uint(res.call_info.result[0: 2])   

        res = await new_user_position.exact_input(self.token1.contract_address, self.token0.contract_address, FeeAmount.MEDIUM, address, to_uint(amount_in), to_uint(price), to_uint(amount_out_min), deadline).execute(caller_address=address)
        amount_out = from_uint(res.call_info.result[0: 2])
        self.assertEqual(amount_out, expect_amount_out)

        pool_after = await self.get_balance(token0, token1, self.swap_pool_address)
        trader_after = await self.get_balance(token0, token1, address)
        print('balance after:', pool_after, trader_after)

        self.assertEqual(trader_after[0], trader_before[0] + 1)
        self.assertEqual(trader_after[1], trader_before[1] - 3)
        self.assertEqual(pool_after[0], pool_before[0] - 1)
        self.assertEqual(pool_after[1], pool_before[1] + 3)

    async def exact_input_router(self, contract, path, amount_in=3, amount_out_min=1):
        res = await  contract.exact_input_router(path, address, to_uint(amount_in), to_uint(amount_out_min), DEADLINE).execute(caller_address=address)
        return res

    @pytest.mark.asyncio
    async def test_exact_input_router(self):
        user_position = await self.get_user_position_contract()

        fee = FeeAmount.MEDIUM

        res = await user_position.mint(other_address, self.token0.contract_address, self.token1.contract_address, fee, min_tick, max_tick, to_uint(1000000), to_uint(1000000), to_uint(0), to_uint(0), DEADLINE).execute(caller_address=address)

        if self.token1.contract_address < self.token2.contract_address:
            res = await user_position.mint(other_address, self.token1.contract_address, self.token2.contract_address, fee, min_tick, max_tick, to_uint(1000000), to_uint(1000000), to_uint(0), to_uint(0), DEADLINE).execute(caller_address=address)
        else:
            res = await user_position.mint(other_address, self.token2.contract_address, self.token1.contract_address, fee, min_tick, max_tick, to_uint(1000000), to_uint(1000000), to_uint(0), to_uint(0), DEADLINE).execute(caller_address=address)

        print('token address:', self.token0.contract_address, self.token1.contract_address, self.token2.contract_address)

        # single-pool
        # 0 -> 1
        new_user_position = cached_contract(user_position.state.copy(), self.user_position_def, user_position)

        token0 = cached_contract(new_user_position.state, self.token0_def, self.token0)
        token1 = cached_contract(new_user_position.state, self.token1_def, self.token1)
        pool_before = await self.get_balance(token0, token1, self.swap_pool_address)
        trader_before = await self.get_balance(token0, token1, address)

        amount_in = 3
        path = [self.token0.contract_address, fee, self.token1.contract_address]

        res = await new_user_position.get_exact_input_router(path, to_uint(amount_in)).execute(caller_address=address)
        expect_amount_out = from_uint(res.call_info.result[0: 2])

        res = await self.exact_input_router(new_user_position, path, amount_in)
        amount_out = from_uint(res.call_info.result[0: 2])
        self.assertEqual(amount_out, expect_amount_out)

        pool_after = await self.get_balance(token0, token1, self.swap_pool_address)
        trader_after = await self.get_balance(token0, token1, address)

        self.assertEqual(trader_after[0], trader_before[0] - 3)
        self.assertEqual(trader_after[1], trader_before[1] + 1)
        self.assertEqual(pool_after[0], pool_before[0] + 3)
        self.assertEqual(pool_after[1], pool_before[1] - 1)

        # 1-> 0
        new_user_position = cached_contract(user_position.state.copy(), self.user_position_def, user_position)

        token0 = cached_contract(new_user_position.state, self.token0_def, self.token0)
        token1 = cached_contract(new_user_position.state, self.token1_def, self.token1)
        pool_before = await self.get_balance(token0, token1, self.swap_pool_address)
        trader_before = await self.get_balance(token0, token1, address)

        path = [self.token1.contract_address, fee, self.token0.contract_address]
        res = await new_user_position.get_exact_input_router(path, to_uint(amount_in)).execute(caller_address=address)
        expect_amount_out = from_uint(res.call_info.result[0: 2])

        res = await self.exact_input_router(new_user_position, path, amount_in)
        amount_out = from_uint(res.call_info.result[0: 2])
        self.assertEqual(amount_out, expect_amount_out)

        pool_after = await self.get_balance(token0, token1, self.swap_pool_address)
        trader_after = await self.get_balance(token0, token1, address)

        self.assertEqual(trader_after[0], trader_before[0] + 1)
        self.assertEqual(trader_after[1], trader_before[1] - 3)
        self.assertEqual(pool_after[0], pool_before[0] - 1)
        self.assertEqual(pool_after[1], pool_before[1] + 3)

        # multi-pool
        # 0 -> 1 -> 2
        new_user_position = cached_contract(user_position.state.copy(), self.user_position_def, user_position)
        token0 = cached_contract(new_user_position.state, self.token0_def, self.token0)
        token2 = cached_contract(new_user_position.state, self.token2_def, self.token2)
        trader_before = await self.get_balance(token0, token2, address)

        amount_in = 5
        path = [self.token0.contract_address, fee, self.token1.contract_address, fee, self.token2.contract_address]
        res = await new_user_position.get_exact_input_router(path, to_uint(amount_in)).execute(caller_address=address)
        expect_amount_out = from_uint(res.call_info.result[0: 2])
        print('expect_amount_out: ', expect_amount_out)

        res = await self.exact_input_router(new_user_position, path, amount_in, 1)
        amount_out = from_uint(res.call_info.result[0: 2])
        self.assertEqual(amount_out, expect_amount_out)

        trader_after = await self.get_balance(token0, token2, address)

        self.assertEqual(trader_after[0], trader_before[0] - 5)
        self.assertEqual(trader_after[1], trader_before[1] + 1)

        print('raw_events:', res.raw_events, self.swap_pool_address)

        # event
        assert_event_emitted(
            res,
            from_address=self.swap_pool_address,
            name='TransferToken',
            data=[
                self.token1.contract_address,
                new_user_position.contract_address, 
                3,
                0
            ]
        )
        assert_event_emitted(
            res,
            from_address=self.swap_pool_address2,
            name='TransferToken',
            data=[
                self.token2.contract_address,
                address,
                1,
                0
            ]
        )

        # 2 -> 1 -> 0
        new_user_position = cached_contract(user_position.state.copy(), self.user_position_def, user_position)
        token0 = cached_contract(new_user_position.state, self.token0_def, self.token0)
        token2 = cached_contract(new_user_position.state, self.token2_def, self.token2)
        trader_before = await self.get_balance(token0, token2, address)

        amount_in = 5
        path = [self.token2.contract_address, fee, self.token1.contract_address, fee, self.token0.contract_address]
        res = await new_user_position.get_exact_input_router(path, to_uint(amount_in)).execute(caller_address=address)
        expect_amount_out = from_uint(res.call_info.result[0: 2])
        print('expect_amount_out: ', expect_amount_out)

        res = await self.exact_input_router(new_user_position, path, amount_in, 1)
        amount_out = from_uint(res.call_info.result[0: 2])
        self.assertEqual(amount_out, expect_amount_out)

        trader_after = await self.get_balance(token0, token2, address)

        self.assertEqual(trader_after[1], trader_before[1] - 5)
        self.assertEqual(trader_after[0], trader_before[0] + 1)

    @pytest.mark.asyncio
    async def test_exact_output(self):
        user_position = await self.get_user_position_contract()

        res = await user_position.mint(other_address, self.token0.contract_address, self.token1.contract_address, FeeAmount.MEDIUM, min_tick, max_tick, to_uint(1000000), to_uint(1000000), to_uint(0), to_uint(0), DEADLINE).execute(caller_address=address)

        amount_out = 1
        amount_in_max = 3

        # token0-> token1
        new_user_position = cached_contract(user_position.state.copy(), self.user_position_def, user_position)
        token0 = cached_contract(new_user_position.state, self.token0_def, self.token0)
        token1 = cached_contract(new_user_position.state, self.token1_def, self.token1)
        pool_before = await self.get_balance(token0, token1, self.swap_pool_address)
        trader_before = await self.get_balance(token0, token1, address)
        print('balance:', pool_before, trader_before)

        price = 0

        deadline = int(time.time() + 1000)
        #await assert_revert(
        #    new_user_position.exact_output(self.token0.contract_address, self.token1.contract_address, FeeAmount.MEDIUM, address, to_uint(amount_out), to_uint(price), to_uint(amount_in_max - 1), 0).execute(caller_address=address),
        #    "deadline"
        #)

        await assert_revert(
            new_user_position.exact_output(self.token0.contract_address, self.token1.contract_address, FeeAmount.MEDIUM, address, to_uint(amount_out), to_uint(price), to_uint(amount_in_max - 1), deadline).execute(caller_address=address),
            "too much requested"
        )

        res = await new_user_position.get_exact_output(self.token0.contract_address, self.token1.contract_address, FeeAmount.MEDIUM, to_uint(amount_out)).execute(caller_address=address)
        expect_amount_in = from_uint(res.call_info.result[0: 2])

        res = await new_user_position.exact_output(self.token0.contract_address, self.token1.contract_address, FeeAmount.MEDIUM, address, to_uint(amount_out), to_uint(price), to_uint(amount_in_max), deadline).execute(caller_address=address)
        amount_in = from_uint(res.call_info.result[0: 2])
        self.assertEqual(amount_in, expect_amount_in)

        pool_after = await self.get_balance(token0, token1, self.swap_pool_address)
        trader_after = await self.get_balance(token0, token1, address)
        print('balance after:', pool_after, trader_after)

        self.assertEqual(trader_after[0], trader_before[0] - 3)
        self.assertEqual(trader_after[1], trader_before[1] + 1)
        self.assertEqual(pool_after[0], pool_before[0] + 3)
        self.assertEqual(pool_after[1], pool_before[1] - 1)

        # token1 -> token0
        new_user_position = cached_contract(user_position.state.copy(), self.user_position_def, user_position)
        token0 = cached_contract(new_user_position.state, self.token0_def, self.token0)
        token1 = cached_contract(new_user_position.state, self.token1_def, self.token1)
        pool_before = await self.get_balance(token0, token1, self.swap_pool_address)
        trader_before = await self.get_balance(token0, token1, address)
        print('balance:', pool_before, trader_before)

        price = 4295128740
        if self.token1.contract_address > self.token0.contract_address:
            price = 1461446703485210103287273052203988822378723970341

        await assert_revert(
            new_user_position.exact_output(self.token1.contract_address, self.token0.contract_address, FeeAmount.MEDIUM, address, to_uint(amount_out), to_uint(price), to_uint(amount_in_max - 1), deadline).execute(caller_address=address),
            "too much requested"
        )

        res = await new_user_position.get_exact_output(self.token1.contract_address, self.token0.contract_address, FeeAmount.MEDIUM, to_uint(amount_out)).execute(caller_address=address)
        expect_amount_in = from_uint(res.call_info.result[0: 2])

        res = await new_user_position.exact_output(self.token1.contract_address, self.token0.contract_address, FeeAmount.MEDIUM, address, to_uint(amount_out), to_uint(price), to_uint(amount_in_max), deadline).execute(caller_address=address)
        amount_in = from_uint(res.call_info.result[0: 2])
        self.assertEqual(amount_in, expect_amount_in)

        pool_after = await self.get_balance(token0, token1, self.swap_pool_address)
        trader_after = await self.get_balance(token0, token1, address)
        print('balance after:', pool_after, trader_after)

        self.assertEqual(trader_after[0], trader_before[0] + 1)
        self.assertEqual(trader_after[1], trader_before[1] - 3)
        self.assertEqual(pool_after[0], pool_before[0] - 1)
        self.assertEqual(pool_after[1], pool_before[1] + 3)

    @pytest.mark.asyncio
    async def test_upgrade_swap_pool_class_hash(self):
        user_position = await self.get_user_position_contract()
        await assert_revert(
            user_position.upgrade_swap_pool_class_hash(self.token0.contract_address, self.token1.contract_address, FeeAmount.MEDIUM, self.swap_pool_class.class_hash).execute(caller_address=other_address),
            ""
        )
        await user_position.upgrade_swap_pool_class_hash(self.token0.contract_address, self.token1.contract_address, FeeAmount.MEDIUM, self.swap_pool_class.class_hash).execute(caller_address=address)

    @pytest.mark.asyncio
    async def test_update_swap_pool(self):
        user_position = await self.get_user_position_contract()
        await assert_revert(
            user_position.update_swap_pool(self.swap_pool_class.class_hash, self.swap_pool_proxy_class.class_hash).execute(caller_address=other_address),
            ""
        )
        await user_position.update_swap_pool(self.swap_pool_class.class_hash, self.swap_pool_proxy_class.class_hash).execute(caller_address=address)

    #TODO: test fees accounting