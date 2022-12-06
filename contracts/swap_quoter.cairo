%lang starknet

from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.cairo_builtins import HashBuiltin, BitwiseBuiltin
from starkware.cairo.common.uint256 import Uint256, uint256_le, uint256_add, uint256_lt, uint256_sub, uint256_neg, uint256_eq, uint256_signed_lt, uint256_check
from starkware.cairo.common.math_cmp import is_le_felt
from starkware.cairo.common.math import unsigned_div_rem

from contracts.interface.ISwapPool import ISwapPool
from contracts.math_utils import Utils
from contracts.interface.IUserPositionMgr import IUserPositionMgr
from contracts.swap_utils import SwapUtils

@storage_var
func _user_position_mgr_address() -> (res: felt) {
}

@constructor
func constructor{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(user_position_mgr_address) {
    _user_position_mgr_address.write(user_position_mgr_address);
    return ();
}

// view
func _get_pool_address{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    token0: felt,
    token1: felt,
    fee: felt
) -> felt {
    let (address) = _user_position_mgr_address.read();
    let (pool_address) = IUserPositionMgr.get_pool_address(
        contract_address=address,
        token0=token0,
        token1=token1,
        fee=fee
    );

    return pool_address;
}

func _get_exact_output_internal{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    path_len: felt,
    path: felt*,
    amount_out: Uint256
) -> (amount_in: Uint256) {
    alloc_locals;

    let token_out = path[0];
    let fee = path[1];
    let token_in = path[2];

    let pool_address = _get_pool_address(token_in, token_out, fee);

    // unsined int
    let zero_for_one = is_le_felt(token_in, token_out);
     
    let (amount_specified: Uint256) = uint256_neg(amount_out);

    let (limit_price: Uint256) = SwapUtils.get_limit_price(Uint256(0, 0), zero_for_one);

    let (amount0: Uint256, amount1: Uint256) = ISwapPool.get_swap_results(contract_address=pool_address, zero_for_one=zero_for_one, amount_specified=amount_specified, sqrt_price_limit_x96=limit_price);

    if (zero_for_one == TRUE) {
        return (amount0,);
    }
    return (amount1,);
}

@view
func get_exact_output{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    token_in: felt,
    token_out: felt,
    fee: felt,
    amount_out: Uint256 
) -> (amount_in: Uint256) {
    alloc_locals;

    let (local path: felt*) = alloc();
    path[0] = token_out;
    path[1] = fee;
    path[2] = token_in;

    let (amount_in: Uint256) = _get_exact_output_internal(3, path, amount_out);

    return (amount_in,);
}

func _get_exact_output_router{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    path_len: felt,
    path: felt*,
    amount_out: Uint256 
) -> (amount_in: Uint256) {
    alloc_locals;

    let (amount_in: Uint256) = _get_exact_output_internal(path_len, path, amount_out);

    let (has_multiple_pools) = Utils.is_gt(path_len, 3);
    if (has_multiple_pools == TRUE) {
        let (new_amount_in: Uint256) = _get_exact_output_router(path_len - 2, path + 2, amount_in);
        return (new_amount_in,);
    }

    return (amount_in,);
}

@view
func get_exact_output_router{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    path_len: felt,
    path: felt*,
    amount_out: Uint256, 
) -> (amount_in: Uint256) {
    alloc_locals;

    let (pool_num, rem) = unsigned_div_rem(path_len, 2);
    with_attr error_message("path_len illeagl") {
        assert rem = 1;
    }

    let (amount_in: Uint256) = _get_exact_output_router(path_len, path, amount_out);

    return (amount_in,);
}

func _get_exact_input_internal{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    path_len: felt,
    path: felt*,
    amount_in: Uint256 
) -> (amount_out: Uint256) {
    alloc_locals;

    let token_in = path[0];
    let fee = path[1];
    let token_out = path[2];
    let pool_address = _get_pool_address(token_in, token_out, fee);

    let zero_for_one = is_le_felt(token_in, token_out);

    let (limit_price: Uint256) = SwapUtils.get_limit_price(Uint256(0, 0), zero_for_one);

    let (amount0: Uint256, amount1: Uint256) = ISwapPool.get_swap_results(contract_address=pool_address, zero_for_one=zero_for_one, amount_specified=amount_in, sqrt_price_limit_x96=limit_price);

    if (zero_for_one == TRUE) {
        let (neg_amount1: Uint256) = uint256_neg(amount1);
        return (neg_amount1,);
    }

    let (neg_amount0) = uint256_neg(amount0);
    return (neg_amount0,);
}

@view
func get_exact_input{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    token_in: felt,
    token_out: felt,
    fee: felt,
    amount_in: Uint256 
) -> (amount_out: Uint256) {
    alloc_locals;

    let (local path: felt*) = alloc();
    assert path[0] = token_in;
    assert path[1] = fee;
    assert path[2] = token_out;
    let (amount_out: Uint256) = _get_exact_input_internal(3, path, amount_in);

    return (amount_out,);
}

func _get_exact_input_router{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    path_len: felt,
    path: felt*,
    amount_in: Uint256 
) -> (amount_out: Uint256) {
    alloc_locals;

    let (amount_out: Uint256) = _get_exact_input_internal(path_len, path, amount_in);

    let (has_multiple_pools) = Utils.is_gt(path_len, 3);
    if (has_multiple_pools == TRUE) {
        let (new_amount_out: Uint256) = _get_exact_input_router(path_len - 2, path + 2, amount_out);
        return (new_amount_out,);
    }

    return (amount_out,);
}

@view
func get_exact_input_router{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    path_len: felt,
    path: felt*,
    amount_in: Uint256, 
) -> (amount_out: Uint256) {
    alloc_locals;

    let (pool_num, rem) = unsigned_div_rem(path_len, 2);
    with_attr error_message("path_len illeagl") {
        assert rem = 1;
    }

    uint256_check(amount_in);

    let (amount_out: Uint256) = _get_exact_input_router(path_len, path, amount_in);

    return (amount_out,);
}