%lang starknet

from starkware.cairo.common.cairo_builtins import BitwiseBuiltin
from starkware.cairo.common.uint256 import (Uint256, uint256_mul, uint256_shr, uint256_shl, uint256_lt, uint256_le, uint256_add, uint256_unsigned_div_rem, uint256_signed_div_rem, uint256_or, uint256_sub, uint256_and, uint256_eq, uint256_signed_lt, uint256_neg, uint256_signed_nn)

from contracts.fullmath import FullMath
from contracts.sqrt_price_math import SqrtPriceMath
from contracts.math_utils import Utils

const num_1e6 = 1000000

namespace SwapMath:
    func compute_swap_step{
            range_check_ptr,
            bitwise_ptr: BitwiseBuiltin*
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
        tempvar bitwise_ptr = bitwise_ptr

        local amount_in: Uint256
        local amount_out: Uint256
        local sqrt_ratio_next: Uint256
        if exact_in == 1:
            amount_out.low = 0
            amount_out.high = 1
            let (amount_remaining_less_fee: Uint256, _) = FullMath.uint256_mul_div(amount_remaining, Uint256(num_1e6, 0), Uint256(num_1e6, 0))
            tempvar range_check_ptr = range_check_ptr
            tempvar bitwise_ptr = bitwise_ptr
            if zero_for_one == 1:
                let (amount_in_tmp: Uint256) = SqrtPriceMath.get_amount0_delta(sqrt_ratio_target, sqrt_ratio_current, liquidity, 1)
                tempvar range_check_ptr = range_check_ptr
                tempvar bitwise_ptr = bitwise_ptr
            else:
                let (amount_in_tmp: Uint256) = SqrtPriceMath.get_amount1_delta(sqrt_ratio_current, sqrt_ratio_target, liquidity, 1)
                tempvar range_check_ptr = range_check_ptr
                tempvar bitwise_ptr = bitwise_ptr
            end
            tempvar bitwise_ptr = bitwise_ptr

            amount_in.low = amount_in_tmp.low
            amount_in.high = amount_in_tmp.high

            let (is_valid) = uint256_lt(amount_in, amount_remaining_less_fee)
            tempvar bitwise_ptr = bitwise_ptr
            if is_valid == 1:
                sqrt_ratio_next.low = sqrt_ratio_target.low
                sqrt_ratio_next.high = sqrt_ratio_target.high
                tempvar range_check_ptr = range_check_ptr
                tempvar bitwise_ptr = bitwise_ptr
            else:
                let (tmp: Uint256) = SqrtPriceMath.get_next_sqrt_price_from_input(sqrt_ratio_current, liquidity, amount_remaining_less_fee, zero_for_one)
                sqrt_ratio_next.low = tmp.low
                sqrt_ratio_next.high = tmp.high
                tempvar range_check_ptr = range_check_ptr
                tempvar bitwise_ptr = bitwise_ptr
            end

        else:
            amount_in.low = 0
            amount_in.high = 0
            if zero_for_one == 1:
                let (tmp: Uint256) = SqrtPriceMath.get_amount1_delta(sqrt_ratio_target, sqrt_ratio_current, liquidity, 0)
                tempvar range_check_ptr = range_check_ptr
                tempvar bitwise_ptr = bitwise_ptr
            else:
                let (tmp: Uint256) = SqrtPriceMath.get_amount0_delta(sqrt_ratio_current, sqrt_ratio_target, liquidity, 0)
                tempvar range_check_ptr = range_check_ptr
                tempvar bitwise_ptr = bitwise_ptr
            end
            tempvar bitwise_ptr = bitwise_ptr

            amount_out.low = tmp.low
            amount_out.high = tmp.high

            let (abs_amount_remaining: Uint256) = uint256_neg(amount_remaining)
            let (is_valid) = uint256_lt(amount_out, abs_amount_remaining)
            if is_valid == 1:
                sqrt_ratio_next.low = sqrt_ratio_target.low
                sqrt_ratio_next.high = sqrt_ratio_target.high
                tempvar range_check_ptr = range_check_ptr
                tempvar bitwise_ptr = bitwise_ptr
            else:
                let (tmp: Uint256) = SqrtPriceMath.get_next_sqrt_price_from_output(sqrt_ratio_current, liquidity, abs_amount_remaining, zero_for_one)
                sqrt_ratio_next.low = tmp.low
                sqrt_ratio_next.high = tmp.high
                tempvar range_check_ptr = range_check_ptr
                tempvar bitwise_ptr = bitwise_ptr
            end
        end
        tempvar bitwise_ptr = bitwise_ptr

        let (max) = uint256_eq(sqrt_ratio_target, sqrt_ratio_next)
        tempvar range_check_ptr = range_check_ptr
        tempvar bitwise_ptr = bitwise_ptr

        local amount_in2: Uint256
        local amount_out2: Uint256

        if zero_for_one == 1:
            if max + exact_in == 2:
                amount_in2.low = amount_in.low
                amount_in2.high = amount_in.high
                tempvar range_check_ptr = range_check_ptr
                tempvar bitwise_ptr = bitwise_ptr
            else:
                let (res: Uint256) = SqrtPriceMath.get_amount0_delta(sqrt_ratio_next, sqrt_ratio_current, liquidity, 1)
                amount_in2.low = res.low
                amount_in2.high = res.high
                tempvar range_check_ptr = range_check_ptr
                tempvar bitwise_ptr = bitwise_ptr
            end

            let (flag1) = Utils.is_eq(max, 1)
            let (flag2) = Utils.is_eq(exact_in, 0)

            if flag1 + flag2 == 2:
                amount_out2.low = amount_out.low
                amount_out2.high = amount_out.high
                tempvar range_check_ptr = range_check_ptr
                tempvar bitwise_ptr = bitwise_ptr
            else:
                let (res: Uint256) = SqrtPriceMath.get_amount1_delta(sqrt_ratio_next, sqrt_ratio_current, liquidity, 0)
                amount_out2.low = res.low
                amount_out2.high = res.high
                tempvar range_check_ptr = range_check_ptr
                tempvar bitwise_ptr = bitwise_ptr
            end
        else:
            if max + exact_in == 2:
                amount_in2.low = amount_in.low
                amount_in2.high = amount_in.high
                tempvar range_check_ptr = range_check_ptr
                tempvar bitwise_ptr = bitwise_ptr
            else:
                let (res: Uint256) = SqrtPriceMath.get_amount1_delta(sqrt_ratio_current, sqrt_ratio_next, liquidity, 1)
                amount_in2.low = res.low
                amount_in2.high = res.high
                tempvar range_check_ptr = range_check_ptr
                tempvar bitwise_ptr = bitwise_ptr
            end

            let (flag1) = Utils.is_eq(max, 1)
            let (flag2) = Utils.is_eq(exact_in, 0)
            if flag1 + flag2 == 2:
                amount_out2.low = amount_out.low
                amount_out2.high = amount_out.high
                tempvar range_check_ptr = range_check_ptr
                tempvar bitwise_ptr = bitwise_ptr
            else:
                let (res: Uint256) = SqrtPriceMath.get_amount0_delta(sqrt_ratio_current, sqrt_ratio_next, liquidity, 0)
                amount_out2.low = res.low
                amount_out2.high = res.high
                tempvar range_check_ptr = range_check_ptr
                tempvar bitwise_ptr = bitwise_ptr
            end
        end
        tempvar bitwise_ptr = bitwise_ptr

        let (is_valid) = uint256_eq(sqrt_ratio_next, sqrt_ratio_target)
        tempvar bitwise_ptr = bitwise_ptr
        
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
            let (fee_amount: Uint256) = uint256_sub(amount_remaining, amount_in2)
            return (sqrt_ratio_next, amount_in2, amount_out2, fee_amount)
        end

        let (fee_amount: Uint256) = FullMath.uint256_mul_div_roundingup(amount_in2, Uint256(fee_pips, 0), Uint256(num_1e6 - fee_pips, 0))
        return (sqrt_ratio_next, amount_in2, amount_out2, fee_amount)
    end
end