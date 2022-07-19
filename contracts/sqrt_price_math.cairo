%lang starknet

from starkware.cairo.common.uint256 import (Uint256, uint256_mul, uint256_shr, uint256_shl, uint256_lt, uint256_le, uint256_add, uint256_unsigned_div_rem, uint256_signed_div_rem, uint256_or, uint256_sub, uint256_and, uint256_eq, uint256_signed_lt, uint256_neg, uint256_signed_nn)

from contracts.fullmath import FullMath
from contracts.math_utils import Utils

namespace SqrtPriceMath:
    func get_amount0_delta{
            range_check_ptr
        }(
            sqrt_ratio0_x96: Uint256,
            sqrt_ratio1_x96: Uint256,
            liquidity: felt,
            roundup: felt
        ) -> (amount0: Uint256):

        let (is_valid) = uint256_lt(sqrt_ratio1_x96, sqrt_ratio0_x96)
        if is_valid == 1:
            tempvar price_a = sqrt_ratio1_x96
            tempvar price_b = sqrt_ratio0_x96
        else:
            tempvar price_a = sqrt_ratio0_x96
            tempvar price_b = sqrt_ratio1_x96
        end

        let (numerator1: Uint256) = uint256_shl(Uint256(liquidity, 0), Uint256(96, 0))
        let (numerator2: Uint256) = uint256_sub(price_b , price_a)

        let (is_valid) = uint256_lt(0, price_a)
        assert is_valid = 1

        if roundup == 1:
            let (tmp: Uint256) = FullMath.uint256_mul_div_roundingup(numerator1, numerator2, price_b)
            let (delta: Uint256, _) = FullMath.uint256_div_roundingup(tmp, price_a)
            return (delta)
        end

        let (tmp: Uint256) = FullMath.uint256_mul_div(numerator1, numerator2, price_b)
        let (delta: Uint256, _) = uint256_unsigned_div_rem(tmp, price_a)
        return (delta)
    end

    func get_amount0_delta2{
            range_check_ptr
        }(
            sqrt_ratio0_x96: Uint256,
            sqrt_ratio1_x96: Uint256,
            liquidity: felt
        ) -> (amount0: Uint256):
        let (is_valid) = Utils.is_lt(liquidity, 0)
        if is_valid == 1:
            let (tmp: Uint256) = get_amount0_delta(sqrt_ratio0_x96, sqrt_ratio1_x96, -liquidity, 0)
            let (res: Uint256) = uint256_neg(tmp)
            return (res)
        end
        let (res: Uint256) = get_amount0_delta(sqrt_ratio0_x96, sqrt_ratio1_x96, liquidity, 1)
        return (res)
    end

    func get_amount1_delta{
            range_check_ptr
        }(
            sqrt_ratio0_x96: Uint256,
            sqrt_ratio1_x96: Uint256,
            liquidity: felt,
            roundup: felt
        ) -> (amount1: Uint256):

        let (is_valid) = uint256_lt(sqrt_ratio1_x96, sqrt_ratio0_x96)
        if is_valid == 1:
            tempvar price_a = sqrt_ratio1_x96
            tempvar price_b = sqrt_ratio0_x96
        else:
            tempvar price_a = sqrt_ratio0_x96
            tempvar price_b = sqrt_ratio1_x96
        end

        if roundup == 1:
            let (delta: Uint256) = FullMath.uint256_mul_div_roundingup(liquidity, price_b - price_a, Uint256(2 ** 96, 0))
            return (delta)
        end

        let (delta: Uint256, _) = FullMath.uint256_mul_div(liquidity, price_b - price_a, Uint256(2 ** 96, 0))
        return (delta)
    end

    func get_amount1_delta2{
            range_check_ptr
        }(
            sqrt_ratio0_x96: Uint256,
            sqrt_ratio1_x96: Uint256,
            liquidity: felt
        ) -> (amount1: Uint256):
        let (is_valid) = Utils.is_lt(liquidity, 0)
        if is_valid == 1:
            let (tmp: Uint256) = get_amount1_delta(sqrt_ratio0_x96, sqrt_ratio1_x96, -liquidity, 0)
            let (res: Uint256) = uint256_neg(tmp)
            return (res)
        end

        let (res: Uint256) = get_amount1_delta(sqrt_ratio0_x96, sqrt_ratio1_x96, liquidity, 1)
        return (res)
    end

    func get_next_sqrt_price_from_amount0_roundingup{
            range_check_ptr
        }(
            sqrt_price_x96: Uint256,
            liquidity: felt,
            amount: Uint256,
            add: felt
        ) -> (res: Uint256):
        
        let (is_valid) = uint256_eq(amount, Uint256(0, 0))
        if is_valid == 1:
            return (sqrt_price_x96)
        end

        let (numerator1: Uint256) = uint256_shl(Uint256(liquidity, 0), Uint256(96, 0))

        let (product: Uint256, _) = uint256_mul(amount, sqrt_price_x96)
        let (tmp: Uint256, _) = uint256_unsigned_div_rem(product, amount)
        let (not_overflow) = uint256_eq(tmp, sqrt_price_x96)

        if add == 1:
            if not_overflow == 1:
                let (denominator: Uint256) = uint256_add(numerator1, product)
                let (is_valid) = uint256_le(numerator1, denominator)
                if is_valid == 1:
                    let (res: Uint256) = FullMath.uint256_mul_div_roundingup(numerator1, sqrt_price_x96, denominator)
                    return (res)
                end
            end

            let (tmp: Uint256, _) = uint256_unsigned_div_rem(numerator1, sqrt_price_x96)
            let (tmp2: Uint256, _) = uint256_add(tmp, amount)
            let (res: Uint256) = FullMath.uint256_div_roundingup(numerator1, tmp2)
            return (res)
        end

        assert not_overflow = 1
        let (is_valid) = uint256_lt(product, numerator1)
        assert is_valid = 1

        let (denominator: Uint256) = uint256_sub(numerator1, product)
        let (res: Uint256) = FullMath.uint256_mul_div_roundingup(numerator1, sqrt_price_x96, denominator)
        return (res)
    end

    func get_next_sqrt_price_from_amount1_roundingdown{
            range_check_ptr
        }(
            sqrt_price_x96: Uint256,
            liquidity: felt,
            amount: Uint256,
            add: felt
        ) -> (res: Uint256):

        if add == 1:
            let (tmp: Uint256, _) = FullMath.uint256_mul_div(amount, Uint256(2 ** 96, 0), liquidity)
            let (res: Uint256) = uint256_add(sqrt_price_x96, tmp)
            return (res)
        end

        let (tmp: Uint256, _) = FullMath.uint256_mul_div_roundingup(amount, Uint256(2 ** 96, 0), liquidity)
        let (is_valid) = uint256_lt(tmp, sqrt_price_x96)
        assert is_valid = 1

        let (res: Uint256) = uint256_sub(sqrt_price_x96, tmp)
        return (res)
    end

    func get_next_sqrt_price_from_input{
            range_check_ptr
        }(
            sqrt_price_x96: Uint256,
            liquidity: felt,
            amount_in: Uint256,
            zero_for_one: felt
        ) -> (res: Uint256):
        assert uint256_lt(0, sqrt_price_x96)[0] = 1
        assert Utils.is_gt(liquidity, 0)[0] = 1

        if zero_for_one == 1:
            let (res: Uint256) = get_next_sqrt_price_from_amount0_roundingup(sqrt_price_x96, liquidity, amount_in, 1)
            return (res)
        end

        let (res: Uint256) = get_next_sqrt_price_from_amount1_roundingdown(sqrt_price_x96, liquidity, amount_in, 1)
        return (res)
    end

    func get_next_sqrt_price_from_output{
            range_check_ptr
        }(
            sqrt_price_x96: Uint256,
            liquidity: felt,
            amount_out: Uint256,
            zero_for_one: felt
        ) -> (res: Uint256):
        assert uint256_lt(0, sqrt_price_x96)[0] = 1
        assert Utils.is_gt(liquidity, 0)[0] = 1

        if zero_for_one == 1:
            let (res: Uint256) = get_next_sqrt_price_from_amount1_roundingdown(sqrt_price_x96, liquidity, amount_out, 0)
            return (res)
        end

        let (res: Uint256) = get_next_sqrt_price_from_amount0_roundingup(sqrt_price_x96, liquidity, amount_out, 0)
        return (res)
    end

end