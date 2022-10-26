%lang starknet

from starkware.cairo.common.cairo_builtins import BitwiseBuiltin
from starkware.cairo.common.uint256 import (
    Uint256,
    uint256_mul,
    uint256_shr,
    uint256_shl,
    uint256_lt,
    uint256_le,
    uint256_add,
    uint256_unsigned_div_rem,
    uint256_or,
    uint256_sub,
    uint256_and,
    uint256_eq,
    uint256_signed_lt,
    uint256_neg,
    uint256_signed_nn,
)
from starkware.cairo.common.bool import FALSE, TRUE

from contracts.fullmath import FullMath
from contracts.sqrt_price_math import SqrtPriceMath
from contracts.math_utils import Utils

const num_1e6 = 1000000;

namespace SwapMath {
    func _compute_swap_step_1{range_check_ptr, bitwise_ptr: BitwiseBuiltin*}(
        sqrt_ratio_current: Uint256,
        sqrt_ratio_target: Uint256,
        liquidity: felt,
        amount_remaining: Uint256,
        fee_pips: felt,
        exact_in: felt,
        zero_for_one: felt,
    ) -> (sqrt_ratio_next: Uint256, amont_in: Uint256, amount_out: Uint256) {
        alloc_locals;

        if (exact_in == 1) {
            let (amount_remaining_less_fee: Uint256, _) = FullMath.uint256_mul_div(
                amount_remaining, Uint256(num_1e6 - fee_pips, 0), Uint256(num_1e6, 0)
            );
            local low;
            local high;
            if (zero_for_one == 1) {
                let (amount_in: Uint256) = SqrtPriceMath.get_amount0_delta(
                    sqrt_ratio_target, sqrt_ratio_current, liquidity, 1
                );
                low = amount_in.low;
                high = amount_in.high;
                tempvar range_check_ptr = range_check_ptr;
                tempvar bitwise_ptr = bitwise_ptr;
            } else {
                let (amount_in: Uint256) = SqrtPriceMath.get_amount1_delta(
                    sqrt_ratio_current, sqrt_ratio_target, liquidity, 1
                );
                low = amount_in.low;
                high = amount_in.high;
                tempvar range_check_ptr = range_check_ptr;
                tempvar bitwise_ptr = bitwise_ptr;
            }

            let amount_in: Uint256 = Uint256(low, high);
            tempvar range_check_ptr = range_check_ptr;
            tempvar bitwise_ptr = bitwise_ptr;

            let (is_valid) = uint256_lt(amount_in, amount_remaining_less_fee);
            if (is_valid == TRUE) {
                return (sqrt_ratio_target, amount_in, Uint256(0, 0));
            }

            let (sqrt_ratio_next: Uint256) = SqrtPriceMath.get_next_sqrt_price_from_input(
                sqrt_ratio_current, liquidity, amount_remaining_less_fee, zero_for_one
            );

            return (sqrt_ratio_next, amount_in, Uint256(0, 0));
        }

        local low;
        local high;
        if (zero_for_one == 1) {
            let (amount_out: Uint256) = SqrtPriceMath.get_amount1_delta(
                sqrt_ratio_target, sqrt_ratio_current, liquidity, 0
            );
            low = amount_out.low;
            high = amount_out.high;
            tempvar range_check_ptr = range_check_ptr;
            tempvar bitwise_ptr = bitwise_ptr;
        } else {
            let (amount_out: Uint256) = SqrtPriceMath.get_amount0_delta(
                sqrt_ratio_current, sqrt_ratio_target, liquidity, 0
            );
            low = amount_out.low;
            high = amount_out.high;
            tempvar range_check_ptr = range_check_ptr;
            tempvar bitwise_ptr = bitwise_ptr;
        }
        let amount_out: Uint256 = Uint256(low, high);

        let (abs_amount_remaining: Uint256) = uint256_neg(amount_remaining);
        tempvar range_check_ptr = range_check_ptr;
        tempvar bitwise_ptr = bitwise_ptr;
        let (is_valid) = uint256_lt(amount_out, abs_amount_remaining);
        tempvar range_check_ptr = range_check_ptr;
        tempvar bitwise_ptr = bitwise_ptr;
        if (is_valid == TRUE) {
            return (sqrt_ratio_target, Uint256(0, 0), amount_out);
        }

        let (sqrt_ratio_next: Uint256) = SqrtPriceMath.get_next_sqrt_price_from_output(
            sqrt_ratio_current, liquidity, abs_amount_remaining, zero_for_one
        );
        return (sqrt_ratio_next, Uint256(0, 0), amount_out);
    }

    func _compute_swap_step_2{range_check_ptr, bitwise_ptr: BitwiseBuiltin*}(
        sqrt_ratio_current: Uint256,
        sqrt_ratio_next: Uint256,
        liquidity: felt,
        amount_in: Uint256,
        amount_out: Uint256,
        exact_in: felt,
        zero_for_one: felt,
        max: felt,
    ) -> (amont_in2: Uint256, amount_out2: Uint256) {
        alloc_locals;

        if (zero_for_one == 1) {
            local low;
            local high;
            if (max + exact_in == 2) {
                low = amount_in.low;
                high = amount_in.high;
                tempvar range_check_ptr = range_check_ptr;
                tempvar bitwise_ptr = bitwise_ptr;
            } else {
                let (res: Uint256) = SqrtPriceMath.get_amount0_delta(
                    sqrt_ratio_next, sqrt_ratio_current, liquidity, 1
                );
                low = res.low;
                high = res.high;
                tempvar range_check_ptr = range_check_ptr;
                tempvar bitwise_ptr = bitwise_ptr;
            }
            let amount_in2: Uint256 = Uint256(low, high);

            let (flag1) = Utils.is_eq(max, 1);
            let (flag2) = Utils.is_eq(exact_in, 0);

            if (flag1 + flag2 == 2) {
                return (amount_in2, amount_out);
            }

            let (res: Uint256) = SqrtPriceMath.get_amount1_delta(
                sqrt_ratio_next, sqrt_ratio_current, liquidity, 0
            );
            return (amount_in2, res);
        } else {
            local low;
            local high;
            if (max + exact_in == 2) {
                low = amount_in.low;
                high = amount_in.high;
                tempvar range_check_ptr = range_check_ptr;
                tempvar bitwise_ptr = bitwise_ptr;
            } else {
                let (res: Uint256) = SqrtPriceMath.get_amount1_delta(
                    sqrt_ratio_current, sqrt_ratio_next, liquidity, 1
                );
                low = res.low;
                high = res.high;
                tempvar range_check_ptr = range_check_ptr;
                tempvar bitwise_ptr = bitwise_ptr;
            }
            let amount_in2: Uint256 = Uint256(low, high);

            let (flag1) = Utils.is_eq(max, 1);
            let (flag2) = Utils.is_eq(exact_in, 0);
            if (flag1 + flag2 == 2) {
                return (amount_in2, amount_out);
            }

            let (res: Uint256) = SqrtPriceMath.get_amount0_delta(
                sqrt_ratio_current, sqrt_ratio_next, liquidity, 0
            );
            return (amount_in2, res);
        }
    }

    func compute_swap_step{range_check_ptr, bitwise_ptr: BitwiseBuiltin*}(
        sqrt_ratio_current: Uint256,
        sqrt_ratio_target: Uint256,
        liquidity: felt,
        amount_remaining: Uint256,
        fee_pips: felt,
    ) -> (sqrt_ratio_next: Uint256, amont_in: Uint256, amount_out: Uint256, fee_amount: Uint256) {
        alloc_locals;

        let (zero_for_one) = uint256_le(sqrt_ratio_target, sqrt_ratio_current);
        let (exact_in) = uint256_signed_nn(amount_remaining);

        let (
            sqrt_ratio_next: Uint256, amount_in: Uint256, amount_out: Uint256
        ) = _compute_swap_step_1(
            sqrt_ratio_current,
            sqrt_ratio_target,
            liquidity,
            amount_remaining,
            fee_pips,
            exact_in,
            zero_for_one,
        );

        let (max) = uint256_eq(sqrt_ratio_target, sqrt_ratio_next);

        let (amount_in2: Uint256, amount_out2: Uint256) = _compute_swap_step_2(
            sqrt_ratio_current,
            sqrt_ratio_next,
            liquidity,
            amount_in,
            amount_out,
            exact_in,
            zero_for_one,
            max,
        );

        let (is_valid) = uint256_eq(sqrt_ratio_next, sqrt_ratio_target);

        if (exact_in == 1) {
            if (is_valid == FALSE) {
                tempvar flag = 1;
            } else {
                tempvar flag = 0;
            }
        } else {
            tempvar flag = 0;
        }

        if (flag == 1) {
            let (fee_amount: Uint256) = uint256_sub(amount_remaining, amount_in2);
            return (sqrt_ratio_next, amount_in2, amount_out2, fee_amount);
        }

        let (fee_amount: Uint256) = FullMath.uint256_mul_div_roundingup(
            amount_in2, Uint256(fee_pips, 0), Uint256(num_1e6 - fee_pips, 0)
        );
        return (sqrt_ratio_next, amount_in2, amount_out2, fee_amount);
    }
}
