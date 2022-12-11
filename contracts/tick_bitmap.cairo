%lang starknet

from starkware.cairo.common.cairo_builtins import HashBuiltin, BitwiseBuiltin
from starkware.cairo.common.math import signed_div_rem
from starkware.cairo.common.uint256 import (
    Uint256,
    uint256_shl,
    uint256_add,
    uint256_and,
    uint256_sub,
    uint256_eq,
    uint256_not,
    uint256_xor,
    uint256_pow2,
)
from starkware.cairo.common.bool import FALSE, TRUE

from contracts.math_utils import Utils
from contracts.bitmath import BitMath

@storage_var
func TickBitmap_data(tick: felt) -> (value: Uint256) {
}

namespace TickBitmap {
    const bound = 2 ** 127;

    func position{range_check_ptr}(tick: felt) -> (word_pos: felt, bitPos: felt) {
        alloc_locals;

        let (word_pos, bit_pos) = signed_div_rem(tick, 256, bound);
        let (is_valid) = Utils.is_lt_signed(bit_pos, 0);
        if (is_valid == TRUE) {
            let res = 256 + bit_pos;
            return (word_pos, res);
        }
        return (word_pos, bit_pos);
    }

    func flip_tick{
        syscall_ptr: felt*,
        pedersen_ptr: HashBuiltin*,
        range_check_ptr,
        bitwise_ptr: BitwiseBuiltin*,
    }(tick: felt, tick_spacing: felt) {
        alloc_locals;

        let (key, rem) = signed_div_rem(tick, tick_spacing, bound);
        with_attr error_message("tick must be multiples of tick_spacing") {
            assert rem = 0;
        }

        let (word_pos, bit_pos) = position(key);
        let (mask: Uint256) = uint256_pow2(Uint256(bit_pos, 0));
        let (cur_state: Uint256) = TickBitmap_data.read(word_pos);

        let (state: Uint256) = uint256_xor(cur_state, mask);

        TickBitmap_data.write(word_pos, state);
        return ();
    }

    func next_valid_tick_within_one_word{
        syscall_ptr: felt*,
        pedersen_ptr: HashBuiltin*,
        range_check_ptr,
        bitwise_ptr: BitwiseBuiltin*,
    }(tick: felt, tick_spacing: felt, lte: felt) -> (tick_next: felt, initialized: felt) {
        alloc_locals;

        // if tick is minus, it will return math.floor(tick / tick_spacing), for example signed_div_rem(-13, 10) = (-2, 7)
        let (compressed, _) = signed_div_rem(tick, tick_spacing, bound);

        if (lte == TRUE) {
            let (word_pos, bit_pos) = position(compressed);

            let (tmp: Uint256) = uint256_shl(Uint256(1, 0), Uint256(bit_pos, 0));
            let (tmp2: Uint256) = uint256_sub(tmp, Uint256(1, 0));
            let (mask: Uint256, _) = uint256_add(tmp, tmp2);

            let (cur_state: Uint256) = TickBitmap_data.read(word_pos);
            let (state: Uint256) = uint256_and(cur_state, mask);

            let (is_valid) = uint256_eq(state, Uint256(0, 0));
            if (is_valid == FALSE) {
                let (msb) = BitMath.most_significant_bit(state);
                let next = (compressed - (bit_pos - msb)) * tick_spacing;
                return (next, TRUE);
            }

            let next = (compressed - bit_pos) * tick_spacing;
            return (next, FALSE);
        }

        let (word_pos, bit_pos) = position(compressed + 1);
        let (tmp: Uint256) = uint256_shl(Uint256(1, 0), Uint256(bit_pos, 0));
        let (tmp2: Uint256) = uint256_sub(tmp, Uint256(1, 0));
        let (mask: Uint256) = uint256_not(tmp2);

        let (cur_state: Uint256) = TickBitmap_data.read(word_pos);
        let (state: Uint256) = uint256_and(cur_state, mask);

        let (is_valid) = uint256_eq(state, Uint256(0, 0));
        if (is_valid == FALSE) {
            let (lsb) = BitMath.least_significant_bit(state);
            let next = (compressed + 1 + (lsb - bit_pos)) * tick_spacing;
            return (next, TRUE);
        }

        let next = (compressed + 1 + 255 - bit_pos) * tick_spacing;
        return (next, FALSE);
    }
}
