%lang starknet

from starkware.cairo.common.cairo_builtins import HashBuiltin
from contracts.tick_bitmap import TickBitmap
from starkware.cairo.common.uint256 import Uint256
from starkware.cairo.common.cairo_builtins import BitwiseBuiltin

@external
func flip_tick{
        syscall_ptr: felt*,
        pedersen_ptr: HashBuiltin*,
        range_check_ptr,
        bitwise_ptr: BitwiseBuiltin*
    } (tick: felt):
    TickBitmap.flip_tick(tick, 1)
    return ()
end

@view
func next_valid_tick_within_one_word{
        syscall_ptr: felt*,
        pedersen_ptr: HashBuiltin*,
        range_check_ptr,
        bitwise_ptr: BitwiseBuiltin*
    } (tick: felt, tick_spacing: felt, lte: felt) -> (tick_next: felt, initialized: felt):
    let (tick_next, initialized) = TickBitmap.next_valid_tick_within_one_word(tick, tick_spacing, lte)
    return (tick_next, initialized)
end

@view
func is_initialized{
        syscall_ptr: felt*,
        pedersen_ptr: HashBuiltin*,
        range_check_ptr,
        bitwise_ptr: BitwiseBuiltin*
    } (tick: felt) -> (initialized: felt):
    let (tick_next, initialized) = TickBitmap.next_valid_tick_within_one_word(tick, 1, 1)
    if tick_next == tick:
        return (initialized)
    end
    return (0)
end