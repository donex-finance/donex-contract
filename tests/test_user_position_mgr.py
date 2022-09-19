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

token0 = 0
token1 = 1

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

async def init_swap_pool(starknet):
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

    async def get_user_position_contract(self):
        if not hasattr(self, 'user_position'):
            self.starknet = await Starknet.empty()
            self.user_position_def, self.user_position = await init_user_position_contract(self.starknet)

            # erc721
            self.erc721_def, self.erc721 = await init_erc721(self.starknet, self.user_position.contract_address)
            await self.user_position.initialize(self.erc721.contract_address).execute(caller_address=address)

            # swap pool
            self.swap_pool_def, self.swap_pool = await init_swap_pool(self.starknet)
            await self.swap_pool.initialize(encode_price_sqrt(1, 1)).execute()
            await self.user_position.register_pool_address(token0, token1, FeeAmount.MEDIUM, self.swap_pool.contract_address).execute(caller_address=address)

        state = self.user_position.state.copy()
        user_position = cached_contract(state, self.user_position_def, self.user_position)

        swap_pool = cached_contract(state, self.swap_pool_def, self.swap_pool)

        erc721 = cached_contract(state, self.erc721_def, self.erc721)

        return user_position, swap_pool, erc721 

    @pytest.mark.asyncio
    async def test_mint(self):

        user_position, swap_pool, erc721  = await self.get_user_position_contract()
        res = await user_position.mint(other_address, token0, token1, FeeAmount.MEDIUM, min_tick, max_tick, to_uint(15), to_uint(15), to_uint(0), to_uint(0)).execute()
        print('mint res:', res)

        res = await erc721.balanceOf(other_address).call()
        self.assertEqual(res.call_info.result[0], 1)
        res = await erc721.tokenOfOwnerByIndex(other_address, to_uint(0)).call()
        self.assertEqual(from_uint(res.call_info.result[0: 2]), 1)

        #TODO: check nft
        res = await user_position.get_token_position(to_uint(1)).call()
        position = res.call_info.result
        self.assertEqual(felt_to_int(position[1]), min_tick)
        self.assertEqual(position[2], max_tick)
        self.assertEqual(position[3], 15)
        self.assertEqual(from_uint(position[4: 6]), 0)
        self.assertEqual(from_uint(position[6: 8]), 0)
        self.assertEqual(position[8], 0)
        self.assertEqual(position[9], 0)
