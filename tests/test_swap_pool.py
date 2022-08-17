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
    felt_to_int, from_uint, cached_contract, encode_price_sqrt
)

Q128 = to_uint(2 ** 128)
MaxUint256 = to_uint(2 ** 256 - 1)

# The path to the contract source code.
CONTRACT_FILE = os.path.join("tests", "../contracts/swap_pool.cairo")

tick_spacing = 10

class SwapPoolTest(TestCase):
    @classmethod
    async def setUp(cls):
        cls.starknet = await Starknet.empty()
        compiled_contract = compile_starknet_files(
            [CONTRACT_FILE], debug_info=True, disable_hint_validation=True
        )
        #kwargs = (
        #    {"contract_def": compiled_contract}
        #    if "contract_def" in signature(cls.starknet.deploy).parameters
        #    else {"contract_class": compiled_contract},
        #)
        kwargs = {
            "contract_class": compiled_contract,
            "constructor_calldata": [tick_spacing, 0]
            }

        #kwargs["constructor_calldata"] = [len(PRODUCT_ARRAY), *PRODUCT_ARRAY]

        cls.contract_def = compiled_contract

        cls.contract = await cls.starknet.deploy(**kwargs)

    def get_state_contract(self):
        _state = self.contract.state.copy()
        contract = cached_contract(_state, self.contract_def, self.contract)
        return contract

    @pytest.mark.asyncio
    async def test_initialize(self):

        contract = self.get_state_contract()

        res = await contract.initialize(encode_price_sqrt(1, 1)).invoke()
        print(res.call_info.result)
        await assert_revert(
            contract.initialize(encode_price_sqrt(1, 1)).invoke(),
            "initialize more than once"
        )
