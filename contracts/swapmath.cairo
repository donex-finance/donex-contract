%lang starknet

from starkware.cairo.common.uint256 import (Uint256, uint256_mul, uint256_shr, uint256_shl, uint256_lt, uint256_le, uint256_add, uint256_unsigned_div_rem, uint256_signed_div_rem, uint256_or, uint256_sub, uint256_and, uint256_eq, uint256_signed_lt, uint256_neg, uint256_signed_nn)

from contracts.fullmath import FullMath
from contracts.sqrt_price_math import SqrtPriceMath
from contracts.math_utils import Utils

const num_1e6 = 1000000

namespace SwapMath:
    func compute_swap_step{
            range_check_ptr
        }(
            sqrt_ratio_current: Uint256,
            sqrt_ratio_target: Uint256,
            liquidity: felt,
            amount_remaining: Uint256,
            fee_pips: felt
        ) -> (sqrt_ratio_next:  Uint256, amont_in: Uint256, amount_out: Uint256, fee_amount: Uint256):
        alloc_locals

        let (zero_for_one) = uint256_le(sqrt_ratio_target, sqrt_ratio_current)
        let (exact_in) = uint256_signed_nn(amount_remaining)

        if exact_in == 1:
            let (amount_remaining_less_fee: Uint256) = FullMath.uint256_mul_div(amount_remaining, Uint256(num_1e6, 0), Uint256(num_1e6, 0))
            if zero_for_one == 1:
                let (amount_in: Uint256) = SqrtPriceMath.get_amount0_delta(sqrt_ratio_target, sqrt_ratio_current, liquidity, 1)
            else:
                let (amount_in: Uint256) = SqrtPriceMath.get_amount1_delta(sqrt_ratio_current, sqrt_ratio_target, liquidity, 1)
            end

            let (is_valid) = uint256_lt(amount_in, amount_remaining_less_fee)
            if is_valid == 1:
                tempvar sqrt_ratio_next = sqrt_ratio_target
            else:
                let (tmp: Uint256) = SqrtPriceMath.get_next_sqrt_price_from_input(sqrt_ratio_current, liquidity, amount_remaining_less_fee, zero_for_one)
                tempvar sqrt_ratio_next = tmp
            end
        else:
            if zero_for_one == 1:
                let (tmp: Uint256) = SqrtPriceMath.get_amount1_delta(sqrt_ratio_target, sqrt_ratio_current, liquidity, 0)
                tempvar amount_out = tmp
            else:
                let (tmp: Uint256) = SqrtPriceMath.get_amount0_delta(sqrt_ratio_current, sqrt_ratio_target, liquidity, 0)
                tempvar amount_out = tmp
            end

            let (abs_amount_remaining: Uint256) = uint256_neg(amount_remaining)
            let (is_valid) = uint256_lt(amount_out, abs_amount_remaining)
            if is_valid == 1:
                tempvar sqrt_ratio_next = sqrt_ratio_target
            else:
                let (tmp: Uint256) = SqrtPriceMath.get_next_sqrt_price_from_output(sqrt_ratio_current, liquidity, abs_amount_remaining, zero_for_one)
                tempvar sqrt_ratio_next = tmp
            end
        end

        let (max) = uint256_eq(sqrt_ratio_target, sqrt_ratio_next)

        if zero_for_one == 1:
            if max + exact_in == 2:
                tempvar amount_in = amount_in
            else:
                let (res: Uint256) = SqrtPriceMath.get_amount0_delta(sqrt_ratio_next, sqrt_ratio_current, liquidity, 1)
                tempvar amount_in = res
            end

            let (tmp) = Utils.is_eq(max, 1)
            let (tmp2) = Utils.is_eq(exact_in, 0)
            if tmp + tmp2 == 2:
                tempvar amount_out = amount_out
            else:
                let (res: Uint256) = SqrtPriceMath.get_amount1_delta(sqrt_ratio_next, sqrt_ratio_current, liquidity, 0)
                tempvar amount_out = res
            end
        else:
            if max + exact_in == 2:
                tempvar amount_in = amount_in
            else:
                let (res: Uint256) = SqrtPriceMath.get_amount1_delta(sqrt_ratio_current, sqrt_ratio_next, liquidity, 1)
                tempvar amount_in = res
            end

            let (tmp) = Utils.is_eq(max, 1)
            let (tmp2) = Utils.is_eq(exact_in, 0)
            if tmp + tmp2 == 2:
                tempvar amount_out = amount_out
            else:
                let (res: Uint256) = SqrtPriceMath.get_amount0_delta(sqrt_ratio_current, sqrt_ratio_next, liquidity, 0)
                tempvar amount_out = res
            end
        end

        let (is_valid) = uint256_eq(sqrt_ratio_next, sqrt_ratio_target)
        
        if exact_in == 1:
            if is_valid == 0:
                tempvar flag = 1
            else:
                tempvar flag = 0
            end
        else:
            tempvar flag = 0
        end

        if flag == 1:
            let (fee_amount: Uint256) = uint256_sub(amount_remaining, amount_in)
        else:
            let (fee_amount: Uint256) = FullMath.uint256_mul_div_roundingup(amount_in, Uint256(fee_pips, 0), Uint256(num_1e6 - fee_pips, 0))
        end

        return (sqrt_ratio_next, amount_in, amount_out, fee_amount)
    end
end