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

tick_spacing = TICK_SPACINGS[FeeAmount.MEDIUM]
min_tick = get_min_tick(tick_spacing)
max_tick = get_max_tick(tick_spacing)

address = 11111111111111
other_address = 222222222222222

async def init_user_position_contract(starknet):
    begin = time.time()
    compiled_contract = compile_starknet_files(
        ['contracts/user_position_mgr.cairo'], debug_info=True, disable_hint_validation=True
    )
    print('compile user_position time:', time.time() - begin)

    kwargs = {
        "contract_class": compiled_contract,
        "constructor_calldata": []
        }

    begin = time.time()
    contract = await starknet.deploy(**kwargs)
    print('deploy user_position time:', time.time() - begin)

    return compiled_contract, contract

async def init_swap_pool(starknet, token0, token1):
    begin = time.time()
    compiled_contract = compile_starknet_files(
        ['contracts/swap_pool.cairo'], debug_info=True, disable_hint_validation=True
    )
    print('compile swap_pool time:', time.time() - begin)

    kwargs = {
        "contract_class": compiled_contract,
        "constructor_calldata": [tick_spacing, FeeAmount.MEDIUM, token0, token1, address]
        }

    begin = time.time()
    contract = await starknet.deploy(**kwargs)
    print('deploy swap_pool time:', time.time() - begin)

    return compiled_contract, contract

async def init_erc721(starknet, owner):
    begin = time.time()
    compiled_contract = compile_starknet_files(
        ['tests/mocks/ERC721_mock.cairo'], debug_info=True, disable_hint_validation=True
    )
    print('compile erc721 time:', time.time() - begin)

    kwargs = {
        "contract_class": compiled_contract,
        "constructor_calldata": [0, 1, owner]
        }

    begin = time.time()
    contract = await starknet.deploy(**kwargs)
    print('deploy erc721 time:', time.time() - begin)

    return compiled_contract, contract

class UserPositionMgrTest(TestCase):

    @classmethod
    async def setUp(cls):
        pass

    async def check_starknet(self):
        if not hasattr(self, 'starknet'):
            self.starknet = await Starknet.empty()
            self.token0_def, self.token0 = await init_contract(os.path.join("tests", "mocks/ERC20_mock.cairo"), [1, 1, 18, MAX_UINT128, MAX_UINT128, address], starknet=self.starknet)
            await self.token0.transfer(other_address, (MAX_UINT128, 2 ** 127)).execute(caller_address=address)
            self.token1_def, self.token1 = await init_contract(os.path.join("tests", "mocks/ERC20_mock.cairo"), [2, 2, 18, MAX_UINT128, MAX_UINT128, address], starknet=self.starknet)
            await self.token1.transfer(other_address, (MAX_UINT128, 2 ** 127)).execute(caller_address=address)


    async def get_user_position_contract(self):
        await self.check_starknet()

        if not hasattr(self, 'user_position'):
            self.user_position_def, self.user_position = await init_user_position_contract(self.starknet)

            # erc721
            self.erc721_def, self.erc721 = await init_erc721(self.starknet, self.user_position.contract_address)
            await self.user_position.initialize(self.erc721.contract_address).execute(caller_address=address)

            # swap pool
            self.swap_pool_def, self.swap_pool = await init_swap_pool(self.starknet, self.token0.contract_address, self.token1.contract_address)
            await self.swap_pool.initialize(encode_price_sqrt(1, 1)).execute()
            await self.user_position.register_pool_address(self.token0.contract_address, self.token1.contract_address, FeeAmount.MEDIUM, self.swap_pool.contract_address).execute(caller_address=address)

            await self.token0.approve(self.user_position.contract_address, to_uint(2 ** 256 - 1)).execute(caller_address=address)
            await self.token1.approve(self.user_position.contract_address, to_uint(2 ** 256 - 1)).execute(caller_address=address)

            await self.token0.approve(self.user_position.contract_address, to_uint(2 ** 256 - 1)).execute(caller_address=other_address)
            await self.token1.approve(self.user_position.contract_address, to_uint(2 ** 256 - 1)).execute(caller_address=other_address)

        state = self.user_position.state.copy()
        user_position = cached_contract(state, self.user_position_def, self.user_position)

        swap_pool = cached_contract(state, self.swap_pool_def, self.swap_pool)

        erc721 = cached_contract(state, self.erc721_def, self.erc721)

        return user_position, swap_pool, erc721 

    @pytest.mark.asyncio
    async def test_mint(self):

        user_position, swap_pool, erc721  = await self.get_user_position_contract()
        res = await user_position.mint(other_address, self.token0.contract_address, self.token1.contract_address, FeeAmount.MEDIUM, min_tick, max_tick, to_uint(15), to_uint(15), to_uint(0), to_uint(0)).execute(caller_address=other_address)

        # check nft
        res = await erc721.balanceOf(other_address).call()
        self.assertEqual(res.call_info.result[0], 1)
        res = await erc721.tokenOfOwnerByIndex(other_address, to_uint(0)).call()
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
        user_position, swap_pool, erc721  = await self.get_user_position_contract()
        res = await user_position.mint(other_address, self.token0.contract_address, self.token1.contract_address, FeeAmount.MEDIUM, min_tick, max_tick, to_uint(1000), to_uint(1000), to_uint(0), to_uint(0)).execute(caller_address=other_address)

        token_id = to_uint(1)

        # increases position liquidity
        res = await user_position.increase_liquidity(token_id, to_uint(100), to_uint(100), to_uint(0), to_uint(0)).execute(caller_address=other_address)
        res = await user_position.get_token_position(to_uint(1)).call()
        position = res.call_info.result
        self.assertEqual(position[3], 1100) # liquidity

    @pytest.mark.asyncio
    async def test_decrease_liquidity(self):
        user_position, swap_pool, erc721  = await self.get_user_position_contract()
        res = await user_position.mint(other_address, self.token0.contract_address, self.token1.contract_address, FeeAmount.MEDIUM, min_tick, max_tick, to_uint(100), to_uint(100), to_uint(0), to_uint(0)).execute(caller_address=other_address)

        token_id = to_uint(1)

        # cannot be called by other addresses
        await assert_revert(
            user_position.decrease_liquidity(token_id, 50, to_uint(0), to_uint(0)).execute(caller_address=address),
            "_check_approverd_or_owner failed"
        )

        # cannot decrease for more than all the liquidity
        await assert_revert(
            user_position.decrease_liquidity(token_id, 101, to_uint(0), to_uint(0)).execute(caller_address=other_address),
            "liquidity must be less than or equal to the position liquidity"
        )

        # decreases position liquidity
        new_user_position = cached_contract(user_position.state.copy(), self.user_position_def, user_position)
        res = await new_user_position.decrease_liquidity(token_id, 25, to_uint(0), to_uint(0)).execute(caller_address=other_address)
        res = await new_user_position.get_token_position(to_uint(1)).call()
        position = res.call_info.result
        self.assertEqual(position[3], 75)
        self.assertEqual(position[8], 24) # tokens_owed0
        self.assertEqual(position[9], 24) # tokens_owed1

        # can decrease for all the liquidity
        new_user_position = cached_contract(user_position.state.copy(), self.user_position_def, user_position)
        res = await new_user_position.decrease_liquidity(token_id, 100, to_uint(0), to_uint(0)).execute(caller_address=other_address)
        res = await new_user_position.get_token_position(to_uint(1)).call()
        position = res.call_info.result
        self.assertEqual(position[3], 0)

        # cannot decrease for more than the liquidity of the nft position
        new_user_position = cached_contract(user_position.state.copy(), self.user_position_def, user_position)
        res = await new_user_position.mint(other_address, self.token0.contract_address, self.token1.contract_address, FeeAmount.MEDIUM, min_tick, max_tick, to_uint(200), to_uint(100), to_uint(0), to_uint(0)).execute(caller_address=other_address)
        await assert_revert(
            new_user_position.decrease_liquidity(token_id, 101, to_uint(0), to_uint(0)).execute(caller_address=other_address),
            "liquidity must be less than or equal to the position liquidity"
        )

    @pytest.mark.asyncio
    async def test_collect(self):
        user_position, swap_pool, erc721  = await self.get_user_position_contract()
        res = await user_position.mint(other_address, self.token0.contract_address, self.token1.contract_address, FeeAmount.MEDIUM, min_tick, max_tick, to_uint(50), to_uint(50), to_uint(0), to_uint(0)).execute(caller_address=other_address)
        res = await user_position.mint(address, self.token0.contract_address, self.token1.contract_address, FeeAmount.MEDIUM, min_tick, max_tick, to_uint(50), to_uint(50), to_uint(0), to_uint(0)).execute(caller_address=address)

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
        res = await user_position.decrease_liquidity(token_id, 50, to_uint(0), to_uint(0)).execute(caller_address=other_address)
        res = await user_position.collect(token_id, address, MAX_UINT128, MAX_UINT128).execute(caller_address=other_address)
        assert_event_emitted(
            res,
            from_address=swap_pool.contract_address,
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
            from_address=swap_pool.contract_address,
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
        user_position, swap_pool, erc721  = await self.get_user_position_contract()
        res = await user_position.mint(other_address, self.token0.contract_address, self.token1.contract_address, FeeAmount.MEDIUM, min_tick, max_tick, to_uint(100), to_uint(100), to_uint(0), to_uint(0)).execute(caller_address=other_address)

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
        res = await new_user_position.decrease_liquidity(token_id, 50, to_uint(0), to_uint(0)).execute(caller_address=other_address)
        await assert_revert(
            new_user_position.burn(token_id).execute(caller_address=other_address),
            "user_position_mgr: position not clear"
        )

        # cannot be called while there is still tokens owed
        new_user_position = cached_contract(user_position.state.copy(), self.user_position_def, user_position)
        res = await new_user_position.decrease_liquidity(token_id, 100, to_uint(0), to_uint(0)).execute(caller_address=other_address)
        await assert_revert(
            new_user_position.burn(token_id).execute(caller_address=other_address),
            "user_position_mgr: position not clear"
        )

        # cannot be called while there is still tokens owed
        res = await user_position.decrease_liquidity(token_id, 100, to_uint(0), to_uint(0)).execute(caller_address=other_address)
        res = await user_position.collect(token_id, address, MAX_UINT128, MAX_UINT128).execute(caller_address=other_address)
        #await erc721.approve(user_position.contract_address, token_id).execute(caller_address=other_address)
        res = await user_position.burn(token_id).execute(caller_address=other_address)
        await assert_revert(
            user_position.get_token_position(token_id).call(),
            "invalid token id"
        )