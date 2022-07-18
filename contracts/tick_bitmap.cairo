%lang starknet

from starkware.cairo.common.math import unsigned_div_rem
from starkware.cairo.common.uint256 import (Uint256, uint256_shl, uint256_add, uint256_and, uint256_sub, uint256_eq, uint256_not)

from contracts.math_utils import Utils
from contracts.bitmath import BitMath

@storage_var
func TickBitmap_data(tick: felt) -> (value: Uint256):
end

namespace TickBitmap:

    func position{
        range_check_ptr
        }(tick: felt) -> (word_pos: felt, bitPos: felt):

        let (word_pos, bit_pos) = unsigned_div_rem(tick, 256)
        return (word_pos, bit_pos)
    end

    func flip_tick{
        range_check_ptr
        }(tick: felt, tick_spaceing: felt):
        let (_, rem) = unsigned_div_rem(tick, 256)
        assert rem = 0

        let (word_pos, bit_pos) = position(tick)
        let (mask: Uint256) = uint256_shl(Uint256(1, 0), Uint256(bit_pos)) 
        let (cur_state: Uint256) = TickBitmap_data.read(word_pos)

        let (state: Uint256) = uint256_and(cur_state, mask)

        TickBitmap_data.write(word_pos, state)
        return ()
    end

    func next_valid_tick_within_one_word{
        range_check_ptr
        }(tick: felt, tick_spaceing: felt, lte: felt) -> (tick_next: felt, initialized: felt):

        let (compressed, rem) = unsigned_div_rem(tick, tick_spaceing)

        let (is_valid) = Utils.is_lt(tick, 0)

        if is_valid == 1:
            if rem != 0:
                tempvar compressed = compressed - 1
            end
        end

        if lte == 1:
            let (word_pos, bit_pos) = position(compressed)

            let (tmp: Uint256) = uint256_shl(Uint256(1, 0), Uint256(bit_pos))
            let (tmp2: Uint256) = uint256_sub(tmp, Uint256(1, 0))
            let (mask: Uint256, _) =  uint256_add(tmp, tmp2)

            let (cur_state: Uint256) = TickBitmap_data.read(word_pos)
            let (state: Uint256) = uint256_and(cur_state, mask)

            let (is_valid) = uint256_eq(state, Uint256(0, 0))
            if is_valid == 0:
                let initialized = 1
            else:
                let initialized = 0
            end

            if initialized == 1:
                let next = (compressed - (bit_pos - BitMath.most_significant_bit(state)[0])) * tick_spaceing
            else:
                let next = (compressed - bit_pos) * tick_spaceing
            end

            return (next, initialized)
        else:
            let (word_pos, bit_pos) = position(compressed + 1)
            let (tmp: Uint256) = uint256_shl(Uint256(1, 0), Uint256(bit_pos))
            let (tmp2: Uint256) = uint256_sub(tmp, Uint256(1, 0))
            let (mask: Uint256) = uint256_not(tmp2)

            let (cur_state: Uint256) = TickBitmap_data.read(word_pos)
            let (state: Uint256) = uint256_and(cur_state, mask)

            let (is_valid) = uint256_eq(state, Uint256(0, 0))
            if is_valid == 0:
                let initialized = 1
            else:
                let initialized = 0
            end

            if initialized == 1:
                let next = (compressed + 1 + (BitMath.least_significant_bit(state)[0] - bit_pos)) * tick_spaceing
            else:
                let next = (compressed + 1 + 255 - bit_pos) * tick_spaceing
            end

            return (next, initialized)
        end
    end
end