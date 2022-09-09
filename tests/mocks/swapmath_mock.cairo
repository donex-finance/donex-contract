%lang starknet

from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.cairo.common.uint256 import Uint256
from starkware.cairo.common.cairo_builtins import BitwiseBuiltin

from contracts.swapmath import SwapMath

@view
func compute_swap_step{
    syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr, bitwise_ptr: BitwiseBuiltin*
}(
    sqrt_ratio_current: Uint256,
    sqrt_ratio_target: Uint256,
    liquidity: felt,
    amount_remaining: Uint256,
    fee_pips: felt,
) -> (sqrt_ratio_next: Uint256, amont_in: Uint256, amount_out: Uint256, fee_amount: Uint256) {
    let (
        sqrt_ratio_next: Uint256, amont_in: Uint256, amount_out: Uint256, fee_amount: Uint256
    ) = SwapMath.compute_swap_step(
        sqrt_ratio_current, sqrt_ratio_target, liquidity, amount_remaining, fee_pips
    );
    return (sqrt_ratio_next, amont_in, amount_out, fee_amount);
}
