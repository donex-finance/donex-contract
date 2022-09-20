%lang starknet

from starkware.starknet.common.syscalls import get_caller_address, get_contract_address
from starkware.cairo.common.cairo_builtins import HashBuiltin
from contracts.sqrt_price_math import SqrtPriceMath
from starkware.cairo.common.uint256 import Uint256
from starkware.cairo.common.cairo_builtins import BitwiseBuiltin

from openzeppelin.token.erc20.IERC20 import IERC20

from contracts.interface.ISwapPool import ISwapPool

@storage_var
func _token0() -> (res: felt) {
}

@storage_var
func _token1() -> (res: felt) {
}


@constructor
func constructor{
    syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr
}(
    token0: felt,
    token1: felt
) {
    _token0.write(token0);
    _token1.write(token1);
    return ();
}

@external
func add_liquidity{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    recipient: felt, tick_lower: felt, tick_upper: felt, amount: felt, pool_address: felt 
) -> (amount0: Uint256, amount1: Uint256) {
    let (caller) = get_caller_address(); 
    let (amount0: Uint256, amount1: Uint256) = ISwapPool.add_liquidity(contract_address=pool_address, recipient=recipient, tick_lower=tick_lower, tick_upper=tick_upper, liquidity=amount, data=caller);
    return (amount0, amount1);
}

@external
func add_liquidity_callback{
    syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr
}(
    amount0: Uint256, 
    amount1: Uint256, 
    data: felt
) {
    let (token0) = _token0.read();
    let (token1) = _token1.read();
    let (caller_address) = get_caller_address();
    IERC20.transferFrom(contract_address=token0, sender=data, recipient=caller_address, amount=amount0);
    IERC20.transferFrom(contract_address=token1, sender=data, recipient=caller_address, amount=amount1);

    return ();
}