%lang starknet

from starkware.cairo.common.cairo_builtins import HashBuiltin
from contracts.tickmath import TickMath
from starkware.cairo.common.uint256 import Uint256
from starkware.cairo.common.cairo_builtins import BitwiseBuiltin

@view
func get_sqrt_ratio_at_tick{
        syscall_ptr: felt*,
        pedersen_ptr: HashBuiltin*,
        range_check_ptr,
        bitwise_ptr: BitwiseBuiltin*
    } (tick: felt) -> (res: felt):
    let (res) = TickMath.get_sqrt_ratio_at_tick(tick)
    return (res)
end

@view
func get_tick_at_sqrt_ratio{
        syscall_ptr: felt*,
        pedersen_ptr: HashBuiltin*,
        range_check_ptr,
        bitwise_ptr: BitwiseBuiltin*
    } (price: felt) -> (res: felt):
    let (res) = TickMath.get_tick_at_sqrt_ratio(price)
    return (res)
end