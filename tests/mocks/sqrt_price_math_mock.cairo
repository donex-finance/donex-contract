%lang starknet

from starkware.cairo.common.cairo_builtins import HashBuiltin
from contracts.sqrt_price_math import SqrtPriceMath
from starkware.cairo.common.uint256 import Uint256
from starkware.cairo.common.cairo_builtins import BitwiseBuiltin

@view
func get_amount0_delta{
        syscall_ptr: felt*,
        pedersen_ptr: HashBuiltin*,
        range_check_ptr,
        bitwise_ptr: BitwiseBuiltin*
    }(
        sqrt_ratio0_x96: Uint256,
        sqrt_ratio1_x96: Uint256,
        liquidity: felt,
        roundup: felt
    ) -> (amount0: Uint256):
    let (res: Uint256) = SqrtPriceMath.get_amount0_delta(sqrt_ratio0_x96, sqrt_ratio1_x96, liquidity, roundup)
    return (res)
end

@view
func get_amount0_delta2{
        syscall_ptr: felt*,
        pedersen_ptr: HashBuiltin*,
        range_check_ptr,
        bitwise_ptr: BitwiseBuiltin*
    }(
        sqrt_ratio0_x96: Uint256,
        sqrt_ratio1_x96: Uint256,
        liquidity: felt
    ) -> (amount0: Uint256):
    let (res: Uint256) = SqrtPriceMath.get_amount0_delta2(sqrt_ratio0_x96, sqrt_ratio1_x96, liquidity)
    return (res)
end

@view
func get_amount1_delta{
        syscall_ptr: felt*,
        pedersen_ptr: HashBuiltin*,
        range_check_ptr,
        bitwise_ptr: BitwiseBuiltin*
    }(
        sqrt_ratio0_x96: Uint256,
        sqrt_ratio1_x96: Uint256,
        liquidity: felt,
        roundup: felt
    ) -> (amount1: Uint256):
    let (res: Uint256) = SqrtPriceMath.get_amount1_delta(sqrt_ratio0_x96, sqrt_ratio1_x96, liquidity, roundup)
    return (res)
end

@view
func get_amount1_delta2{
        syscall_ptr: felt*,
        pedersen_ptr: HashBuiltin*,
        range_check_ptr,
        bitwise_ptr: BitwiseBuiltin*
    }(
        sqrt_ratio0_x96: Uint256,
        sqrt_ratio1_x96: Uint256,
        liquidity: felt
    ) -> (amount1: Uint256):
    let (res: Uint256) = SqrtPriceMath.get_amount1_delta2(sqrt_ratio0_x96, sqrt_ratio1_x96, liquidity)
    return (res)
end

@view
func get_next_sqrt_price_from_amount0_roundingup{
        syscall_ptr: felt*,
        pedersen_ptr: HashBuiltin*,
        range_check_ptr,
        bitwise_ptr: BitwiseBuiltin*
    }(
        sqrt_price_x96: Uint256,
        liquidity: felt,
        amount: Uint256,
        add: felt
    ) -> (res: Uint256):
    let (res: Uint256) = SqrtPriceMath.get_next_sqrt_price_from_amount0_roundingup(sqrt_price_x96, liquidity, amount, add)
    return (res)
end

@view
func get_next_sqrt_price_from_amount1_roundingdown{
        syscall_ptr: felt*,
        pedersen_ptr: HashBuiltin*,
        range_check_ptr,
        bitwise_ptr: BitwiseBuiltin*
    }(
        sqrt_price_x96: Uint256,
        liquidity: felt,
        amount: Uint256,
        add: felt
    ) -> (res: Uint256):
    let (res: Uint256) = SqrtPriceMath.get_next_sqrt_price_from_amount1_roundingdown(sqrt_price_x96, liquidity, amount, add)
    return (res)
end

@view
func get_next_sqrt_price_from_input{
        range_check_ptr,
        bitwise_ptr: BitwiseBuiltin*
    }(
        sqrt_price_x96: Uint256,
        liquidity: felt,
        amount_in: Uint256,
        zero_for_one: felt
    ) -> (res: Uint256):

    let (res: Uint256) = SqrtPriceMath.get_next_sqrt_price_from_input(sqrt_price_x96, liquidity, amount_in, zero_for_one)
    return (res)
end

@view
func get_next_sqrt_price_from_output{
        range_check_ptr,
        bitwise_ptr: BitwiseBuiltin*
    }(
        sqrt_price_x96: Uint256,
        liquidity: felt,
        amount_out: Uint256,
        zero_for_one: felt
    ) -> (res: Uint256):

    let (res: Uint256) = SqrtPriceMath.get_next_sqrt_price_from_output(sqrt_price_x96, liquidity, amount_out, zero_for_one)
    return (res)
end