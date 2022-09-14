%lang starknet

from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.cairo.common.uint256 import Uint256
from starkware.cairo.common.cairo_builtins import BitwiseBuiltin

from contracts.liquidity_amounts import LiquidityAmounts

@view
func get_amount0_for_liquidity{
    syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr, bitwise_ptr: BitwiseBuiltin*
}(sqrt_ratio0: Uint256, sqrt_ratio1: Uint256, liquidity: felt
) -> (amount0: Uint256) {
    let (amount0: Uint256) = LiquidityAmounts.get_amount0_for_liquidity(sqrt_ratio0, sqrt_ratio1, liquidity);
    return (amount0,);
}

@view
func get_amount1_for_liquidity{
    syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr, bitwise_ptr: BitwiseBuiltin*
}(sqrt_ratio0: Uint256, sqrt_ratio1: Uint256, liquidity: felt
) -> (amount1: Uint256) {
    let (amount1: Uint256) = LiquidityAmounts.get_amount1_for_liquidity(sqrt_ratio0, sqrt_ratio1, liquidity);
    return (amount1,);
}

@view
func get_amounts_for_liquidity{
    syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr, bitwise_ptr: BitwiseBuiltin*
}(sqrt_ratio: Uint256, sqrt_ratio_a: Uint256, sqrt_ratio_b: Uint256, liquidity: felt
) -> (amount0: Uint256, amount1: Uint256) {
    let (amount0: Uint256, amount1: Uint256) = LiquidityAmounts.get_amounts_for_liquidity(sqrt_ratio, sqrt_ratio_a, sqrt_ratio_b, liquidity);
    return (amount0, amount1);
}

@view
func get_liquidity_for_amount0{
    syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr, bitwise_ptr: BitwiseBuiltin*
}(sqrt_ratio0: Uint256, sqrt_ratio1: Uint256, amount0: Uint256
) -> (liquidity: felt) {
    let (liquidity) = LiquidityAmounts.get_liquidity_for_amount0(sqrt_ratio0, sqrt_ratio1, amount0);
    return (liquidity,);
}

@view
func get_liquidity_for_amount1{
    syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr, bitwise_ptr: BitwiseBuiltin*
}(sqrt_ratio0: Uint256, sqrt_ratio1: Uint256, amount1: Uint256
) -> (liquidity: felt) {
    let (liquidity) = LiquidityAmounts.get_liquidity_for_amount1(sqrt_ratio0, sqrt_ratio1, amount1);
    return (liquidity,);
}

@view
func get_liquidity_for_amounts{
    syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr, bitwise_ptr: BitwiseBuiltin*
}(
    sqrt_ratio: Uint256,
    sqrt_ratio_a: Uint256,
    sqrt_ratio_b: Uint256,
    amount0: Uint256,
    amount1: Uint256,
) -> (liquidity: felt) {
    let (liquidity) = LiquidityAmounts.get_liquidity_for_amounts(sqrt_ratio, sqrt_ratio_a, sqrt_ratio_b, amount0, amount1);
    return (liquidity,);
}
