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
    felt_to_int, from_uint, encode_price_sqrt, expand_to_18decimals
)

Q128 = to_uint(2 ** 128)
MaxUint256 = to_uint(2 ** 256 - 1)

# The path to the contract source code.
CONTRACT_FILE = os.path.join("tests", "mocks/swapmath_mock.cairo")
CONTRACT_FILE2 = os.path.join("tests", "mocks/sqrt_price_math_mock.cairo")

class SwapmathTest(TestCase):
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

        cls.contract = await cls.starknet.deploy(**kwargs)

        compiled_contract = compile_starknet_files(
            [CONTRACT_FILE2], debug_info=True, disable_hint_validation=True
        )
        kwargs = (
            {"contract_def": compiled_contract}
            if "contract_def" in signature(cls.starknet.deploy).parameters
            else {"contract_class": compiled_contract}
        )
        cls.sqrt_price_math = await cls.starknet.deploy(**kwargs)

    @pytest.mark.asyncio
    async def test_compute_swap_step(self):

        price = encode_price_sqrt(1, 1)
        price_target = encode_price_sqrt(101, 100)
        liquidity = expand_to_18decimals(2)
        amount = to_uint(expand_to_18decimals(1))
        fee = 600
        zero_for_one = 0

        res = await self.contract.compute_swap_step(price, price_target, liquidity, amount, fee).call()
        sqrt_price = tuple(res.call_info.result[:2])
        amount_in = tuple(res.call_info.result[2: 4])
        amount_out = tuple(res.call_info.result[4: 6])
        fee_amount = tuple(res.call_info.result[6: 8])
        self.assertEqual(
            amount_in,
            to_uint(9975124224178055)
        )
        self.assertEqual(
            amount_out,
            to_uint(9925619580021728)
        )
        self.assertEqual(
            fee_amount,
            to_uint(5988667735148)
        )

        self.assertEqual(sqrt_price, price_target)

        res = await self.sqrt_price_math.get_next_sqrt_price_from_input(price, liquidity, amount, zero_for_one).call()
        self.assertEqual(from_uint(sqrt_price) < from_uint(res.call_info.result), True)

        # exact amount out that gets capped at price target in one for zero
        price = encode_price_sqrt(1, 1)
        price_target = encode_price_sqrt(101, 100)
        liquidity = expand_to_18decimals(2)
        amount_raw = expand_to_18decimals(1) * -1
        amount = to_uint(2 ** 256 + amount_raw)
        fee = 600
        zero_for_one = 0

        res = await self.contract.compute_swap_step(price, price_target, liquidity, amount, fee).call()
        sqrt_price = tuple(res.call_info.result[:2])
        amount_in = tuple(res.call_info.result[2: 4])
        amount_out = tuple(res.call_info.result[4: 6])
        fee_amount = tuple(res.call_info.result[6: 8])
        self.assertEqual(
            amount_in,
            to_uint(9975124224178055)
        )
        self.assertEqual(
            fee_amount,
            to_uint(5988667735148)
        )
        self.assertEqual(
            amount_out,
            to_uint(9925619580021728)
        )
        self.assertEqual(
            from_uint(amount_out) < 2 ** 256 - from_uint(amount),
            True,
        )

        res = await self.sqrt_price_math.get_next_sqrt_price_from_input(price, liquidity, to_uint(-amount_raw), zero_for_one).call()

        self.assertEqual(
            from_uint(sqrt_price),
            from_uint(price_target)
        )
        self.assertEqual(
            from_uint(sqrt_price) < from_uint(res.call_info.result), 
            True
        )

        # exact amount in that is fully spent in one for zero
        price = encode_price_sqrt(1, 1)
        price_target = encode_price_sqrt(1000, 100)
        liquidity = expand_to_18decimals(2)
        amount = to_uint(expand_to_18decimals(1))
        fee = 600
        zero_for_one = 0

        res = await self.contract.compute_swap_step(price, price_target, liquidity, amount, fee).call()
        sqrt_price = tuple(res.call_info.result[:2])
        amount_in = tuple(res.call_info.result[2: 4])
        amount_out = tuple(res.call_info.result[4: 6])
        fee_amount = tuple(res.call_info.result[6: 8])
        print(amount_in, amount_out, fee_amount)
        self.assertEqual(
            amount_in,
            to_uint(999400000000000000)
        )
        self.assertEqual(
            fee_amount,
            to_uint(600000000000000)
        )
        self.assertEqual(
            amount_out,
            to_uint(666399946655997866)
        )
        self.assertEqual(
            from_uint(amount_in) + from_uint(fee_amount),
            from_uint(amount),
        )

        res = await self.sqrt_price_math.get_next_sqrt_price_from_input(price, liquidity, to_uint(from_uint(amount) - from_uint(fee_amount)), zero_for_one).call()
        self.assertEqual(
            from_uint(sqrt_price) < from_uint(price_target), 
            True
        )
        self.assertEqual(
            sqrt_price,
            tuple(res.call_info.result)
        )

        # 4 exact amount out that is fully received in one for zero

        price = encode_price_sqrt(1, 1)
        price_target = encode_price_sqrt(1000, 100)
        liquidity = expand_to_18decimals(2)
        amount_raw = expand_to_18decimals(1) * -1
        amount = to_uint(2 ** 256 + amount_raw)
        fee = 600
        zero_for_one = 0

        res = await self.contract.compute_swap_step(price, price_target, liquidity, amount, fee).call()
        sqrt_price = tuple(res.call_info.result[:2])
        amount_in = tuple(res.call_info.result[2: 4])
        amount_out = tuple(res.call_info.result[4: 6])
        fee_amount = tuple(res.call_info.result[6: 8])
        self.assertEqual(
            amount_in,
            to_uint(2000000000000000000)
        )
        self.assertEqual(
            fee_amount,
            to_uint(1200720432259356)
        )
        self.assertEqual(
            from_uint(amount_out),
            amount_raw * -1
        )

        res = await self.sqrt_price_math.get_next_sqrt_price_from_output(price, liquidity, to_uint(amount_raw * -1), zero_for_one).call()
        self.assertEqual(
            from_uint(sqrt_price) < from_uint(price_target), 
            True
        )
        self.assertEqual(
            sqrt_price,
            tuple(res.call_info.result)
        )

        # amount out is capped at the desired amount out

        price = to_uint(417332158212080721273783715441582)
        price_target = to_uint(1452870262520218020823638996)
        liquidity = 159344665391607089467575320103
        amount = to_uint(2 ** 256  - 1)
        fee = 1
        res = await self.contract.compute_swap_step(price, price_target, liquidity, amount, fee).call()
        sqrt_price = from_uint(res.call_info.result[:2])
        amount_in = from_uint(res.call_info.result[2: 4])
        amount_out = from_uint(res.call_info.result[4: 6])
        fee_amount = from_uint(res.call_info.result[6: 8])

        self.assertEqual(amount_in, 1)
        self.assertEqual(fee_amount, 1)
        self.assertEqual(amount_out, 2) #TODO: would be 2 if not capped
        self.assertEqual(sqrt_price, 417332158212080721273783715441581)

        # target price of 1 uses partial input amount
        price = to_uint(2)
        price_target = to_uint(1)
        liquidity = 1 
        amount = to_uint(3915081100057732413702495386755767)
        fee = 1
        res = await self.contract.compute_swap_step(price, price_target, liquidity, amount, fee).call()
        sqrt_price = from_uint(res.call_info.result[:2])
        amount_in = from_uint(res.call_info.result[2: 4])
        amount_out = from_uint(res.call_info.result[4: 6])
        fee_amount = from_uint(res.call_info.result[6: 8])

        self.assertEqual(amount_in, 39614081257132168796771975168)
        self.assertEqual(fee_amount, 39614120871253040049813)
        self.assertEqual(amount_in + fee_amount <= 3915081100057732413702495386755767, True)
        self.assertEqual(amount_out, 0)
        self.assertEqual(sqrt_price, 1)

        # entire input amount taken as fee
        price = to_uint(2413)
        price_target = to_uint(79887613182836312)
        liquidity = 1985041575832132834610021537970
        amount = to_uint(10)
        fee = 1872
        res = await self.contract.compute_swap_step(price, price_target, liquidity, amount, fee).call()
        sqrt_price = from_uint(res.call_info.result[:2])
        amount_in = from_uint(res.call_info.result[2: 4])
        amount_out = from_uint(res.call_info.result[4: 6])
        fee_amount = from_uint(res.call_info.result[6: 8])

        self.assertEqual(amount_in, 0)
        self.assertEqual(fee_amount, 10)
        self.assertEqual(amount_out, 0)
        self.assertEqual(sqrt_price, 2413)

        # handles intermediate insufficient liquidity in zero for one exact output case

        price = to_uint(20282409603651670423947251286016)
        price_target = to_uint(20282409603651670423947251286016 * 11 // 10)
        liquidity = 1024
        amount = to_uint(2 ** 256 - 4)
        fee = 3000
        res = await self.contract.compute_swap_step(price, price_target, liquidity, amount, fee).call()
        sqrt_price = from_uint(res.call_info.result[:2])
        amount_in = from_uint(res.call_info.result[2: 4])
        amount_out = from_uint(res.call_info.result[4: 6])
        fee_amount = from_uint(res.call_info.result[6: 8])

        self.assertEqual(amount_in, 26215)
        self.assertEqual(fee_amount, 79)
        self.assertEqual(amount_out, 0)
        self.assertEqual(sqrt_price, from_uint(price_target))

        # handles intermediate insufficient liquidity in one for zero exact output case

        price = to_uint(20282409603651670423947251286016)
        price_target = to_uint(20282409603651670423947251286016 * 9 // 10)
        liquidity = 1024
        amount = to_uint(2 ** 256 - 263000)
        fee = 3000
        res = await self.contract.compute_swap_step(price, price_target, liquidity, amount, fee).call()
        sqrt_price = from_uint(res.call_info.result[:2])
        amount_in = from_uint(res.call_info.result[2: 4])
        amount_out = from_uint(res.call_info.result[4: 6])
        fee_amount = from_uint(res.call_info.result[6: 8])

        self.assertEqual(amount_in, 1)
        self.assertEqual(fee_amount, 1)
        self.assertEqual(amount_out, 26214)
        self.assertEqual(sqrt_price, from_uint(price_target))