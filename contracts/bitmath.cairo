%lang starknet

from starkware.cairo.common.cairo_builtins import BitwiseBuiltin
from starkware.cairo.common.uint256 import (Uint256, uint256_mul, uint256_shr, uint256_shl, uint256_lt, uint256_le, uint256_add, uint256_unsigned_div_rem, uint256_signed_div_rem, uint256_or, uint256_sub, uint256_and, uint256_eq, uint256_signed_lt, uint256_neg, uint256_signed_nn)

from contracts.math_utils import Utils

namespace BitMath:

    func _msb_shift{
            range_check_ptr
        }(x: Uint256, r: felt, mask: Uint256, bit: felt) -> (x: Uint256, r: felt):
        let (is_valid) = uint256_le(mask, x)
        if is_valid == 1:
            let (new_x: Uint256) = uint256_shr(x, Uint256(bit, 0))
            let new_r = r + bit
            return (new_x, new_r)
        end
        return (x, r)
    end

    func most_significant_bit{
            range_check_ptr
        }(num: Uint256) -> (res: felt):
        alloc_locals

        let (is_valid) = uint256_lt(Uint256(0, 0), num)
        assert is_valid = 1

        let (x: Uint256, r) = _msb_shift(num, 0, Uint256(0, 1), 128)
        let (x: Uint256, r) = _msb_shift(x, r, Uint256(0x10000000000000000, 0), 64)
        let (x: Uint256, r) = _msb_shift(x, r, Uint256(0x100000000, 0), 32)
        let (x: Uint256, r) = _msb_shift(x, r, Uint256(0x10000, 0), 16)
        let (x: Uint256, r) = _msb_shift(x, r, Uint256(0x100, 0), 8)
        let (x: Uint256, r) = _msb_shift(x, r, Uint256(0x10, 0), 4)
        let (x: Uint256, r) = _msb_shift(x, r, Uint256(0x4, 0), 2)

        let (is_valid) = uint256_le(Uint256(0x2, 0), x)
        if (is_valid) == 1:
            return (r + 1)
        end
        return (r)
    end

    func _lsb_shift{
            range_check_ptr,
            bitwise_ptr: BitwiseBuiltin*
        }(x: Uint256, r: felt, mask: Uint256, bit: felt) -> (x: Uint256, r: felt):
        alloc_locals

        let (tx: Uint256) = uint256_and(x, mask)
        let (is_valid) = uint256_lt(Uint256(0, 0), tx)
        if is_valid == 1:
            let new_r = r - bit
            return (x, new_r)
        end
        let (new_x: Uint256) = uint256_shr(x, Uint256(bit, 0))
        return (new_x, r)
    end

    func least_significant_bit{
            range_check_ptr,
            bitwise_ptr: BitwiseBuiltin*
        }(num: Uint256) -> (res: felt):

        let (is_valid) = uint256_lt(Uint256(0, 0), num)
        assert is_valid = 1

        let (x: Uint256, r) = _lsb_shift(num, 255, Uint256(Utils.MAX_UINT128, 0), 128)
        let (x: Uint256, r) = _lsb_shift(x, r, Uint256(0xffffffffffffffff, 0), 64)
        let (x: Uint256, r) = _lsb_shift(x, r, Uint256(0xffffffff, 0), 32)
        let (x: Uint256, r) = _lsb_shift(x, r, Uint256(0xffff, 0), 16)
        let (x: Uint256, r) = _lsb_shift(x, r, Uint256(0xff, 0), 8)
        let (x: Uint256, r) = _lsb_shift(x, r, Uint256(0xf, 0), 4)
        let (x: Uint256, r) = _lsb_shift(x, r, Uint256(0x3, 0), 2)
        let (x: Uint256, r) = _lsb_shift(x, r, Uint256(0x1, 0), 1)
        return (r)
    end
end