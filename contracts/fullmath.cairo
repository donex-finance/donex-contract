%lang starknet

from starkware.cairo.common.uint256 import (Uint256, uint256_mul, uint256_shr, uint256_shl, uint256_lt, uint256_le, uint256_add, uint256_unsigned_div_rem, uint256_signed_div_rem, uint256_or, uint256_sub, uint256_and, uint256_eq, uint256_signed_lt, uint256_neg, uint256_signed_nn)
from starkware.cairo.common.bitwise import (bitwise_and, bitwise_or)
from starkware.cairo.common.math import abs_value
from starkware.cairo.common.cairo_builtins import BitwiseBuiltin
from starkware.cairo.common.math_cmp import (is_nn, is_le)

from contracts.math_utils import Utils

namespace FullMath:
# a * b / c
    func uint256_mul_div{
            range_check_ptr,
            bitwise_ptr: BitwiseBuiltin*
        }(a: Uint256, b: Uint256, c: Uint256) -> (res: Uint256, rem_final: Uint256):
        alloc_locals

        local bitwise_ptr: BitwiseBuiltin* = bitwise_ptr

        let (low: Uint256, high: Uint256) = uint256_mul(a, b)

        # check if high < c
        let (is_valid) = uint256_lt(high, c)
        with_attr error_message("a * b / c is over 2 ^ 256"):
            assert is_valid = 1
        end

        let (res: Uint256, rem_low: Uint256) = uint256_unsigned_div_rem(low, c)
        # if high == 0
        let (is_valid) = uint256_eq(Uint256(0, 0), high)
        if is_valid == 1:
            return (res, rem_low)
        end

        #%{ 
        #    print(f"mul overflow: {ids.a=}, {ids.b=}, {ids.c=}")
        #    breakpoint() 
        #%}

        # get the 2 ^ 256 - 1 % c
        let (_, rem_256_1: Uint256) = uint256_unsigned_div_rem(Uint256(Utils.MAX_UINT128, Utils.MAX_UINT128), c)

        # get 2 ^ 256 % c
        let (tmp: Uint256, _) = uint256_add(rem_256_1, Uint256(1, 0))
        let (_, rem_256: Uint256) = uint256_unsigned_div_rem(tmp, c)

        # high * 256_rem % c
        let (tmp: Uint256, _) = uint256_mul(rem_256, high)
        let (_, rem_high: Uint256) = uint256_unsigned_div_rem(tmp, c)

        # (rem_high + rem_low) % c
        let (tmp: Uint256, carry) =  uint256_add(rem_low, rem_high)
        let (_, rem_all: Uint256) = uint256_unsigned_div_rem(tmp, c)

        # if carry + 1, compute (rem_all + rem_256) % c
        local rem_final: Uint256
        let (is_valid) = Utils.is_gt(carry, 0)
        if is_valid == 1:
            let (tmp: Uint256, _) = uint256_add(rem_all, rem_256)
            let (_, tmp2: Uint256) = uint256_unsigned_div_rem(tmp, c)
            rem_final.low = tmp2.low 
            rem_final.high = tmp2.high
            tempvar range_check_ptr = range_check_ptr
        else:
            rem_final.low = rem_all.low
            rem_final.high = rem_all.high
            tempvar range_check_ptr = range_check_ptr
        end

        let (is_valid) = uint256_lt(low, c)
        let (prod1: Uint256) = uint256_sub(high, Uint256(is_valid, 0))
        let (prod0: Uint256) = uint256_sub(low, c)

        let (minus_c: Uint256) = uint256_neg(c)
        let (twos: Uint256) = uint256_and(minus_c, c)

        let (denomnator: Uint256, _) = uint256_signed_div_rem(c, twos)

        let (prod0: Uint256, _) = uint256_signed_div_rem(prod0, twos)

        let (tmp: Uint256) = uint256_sub(Uint256(0, 0), twos)
        let (tmp: Uint256, _) = uint256_signed_div_rem(tmp, twos)
        let (twos: Uint256, _) = uint256_add(tmp, Uint256(1, 0))

        let (tmp: Uint256, _) = uint256_mul(prod1, twos)

        let (prod0: Uint256) = uint256_or(prod1, twos)

        let (tmp: Uint256, _) = uint256_mul(Uint256(3, 0), denomnator)
        let (inv: Uint256, _) = uint256_mul(tmp, tmp)

        # inverse mod 2**8
        let (tmp: Uint256, _) = uint256_mul(denomnator, inv)
        let (tmp: Uint256) = uint256_sub(Uint256(2, 0), tmp)
        let (inv: Uint256, _) = uint256_mul(inv, tmp)

        # inverse mod 2**16
        let (tmp: Uint256, _) = uint256_mul(denomnator, inv)
        let (tmp: Uint256) = uint256_sub(Uint256(2, 0), tmp)
        let (inv: Uint256, _) = uint256_mul(inv, tmp)

        # inverse mod 2**32
        let (tmp: Uint256, _) = uint256_mul(denomnator, inv)
        let (tmp: Uint256) = uint256_sub(Uint256(2, 0), tmp)
        let (inv: Uint256, _) = uint256_mul(inv, tmp)

        # inverse mod 2**64
        let (tmp: Uint256, _) = uint256_mul(denomnator, inv)
        let (tmp: Uint256) = uint256_sub(Uint256(2, 0), tmp)
        let (inv: Uint256, _) = uint256_mul(inv, tmp)

        # inverse mod 2**128
        let (tmp: Uint256, _) = uint256_mul(denomnator, inv)
        let (tmp: Uint256) = uint256_sub(Uint256(2, 0), tmp)
        let (inv: Uint256, _) = uint256_mul(inv, tmp)

        # inverse mod 2**256
        let (tmp: Uint256, _) = uint256_mul(denomnator, inv)
        let (tmp: Uint256) = uint256_sub(Uint256(2, 0), tmp)
        let (inv: Uint256, _) = uint256_mul(inv, tmp)

        let (result: Uint256, _) = uint256_mul(prod0, inv)
        return (result, rem_final)
    end

    func uint256_mul_div_roundingup{
            range_check_ptr,
            bitwise_ptr: BitwiseBuiltin*
        }(a: Uint256, b: Uint256, c: Uint256) -> (res: Uint256):
        alloc_locals

        let (res: Uint256, rem: Uint256) = uint256_mul_div(a, b, c)
        let (is_valid) = uint256_lt(Uint256(0, 0), rem)
        if is_valid == 1:
            let (is_valid) = uint256_lt(rem, Uint256(Utils.MAX_UINT128, Utils.MAX_UINT128))
            assert is_valid = 1
            let (tmp: Uint256, _) = uint256_add(res, Uint256(1, 0))
            return (tmp)
        end
        return (res)
    end

    func uint256_div_roundingup{
            range_check_ptr
        }(a: Uint256, b: Uint256) -> (res: Uint256):
        alloc_locals

        let (res: Uint256, rem: Uint256) = uint256_unsigned_div_rem(a, b)
        let (is_valid) = uint256_lt(Uint256(0, 0), rem)
        if is_valid == 1:
            let (tmp: Uint256, _) = uint256_add(res, Uint256(1, 0))
            return (tmp)
        end
        return (res)
    end
end