%lang starknet

from starkware.starknet.common.syscalls import get_caller_address, get_contract_address
from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.cairo_builtins import HashBuiltin, BitwiseBuiltin
from starkware.cairo.common.uint256 import Uint256, uint256_le, uint256_add, uint256_lt, uint256_sub, uint256_neg, uint256_eq, uint256_signed_lt, uint256_check
from starkware.cairo.common.math_cmp import is_le, is_le_felt
from starkware.cairo.common.math import unsigned_div_rem
from starkware.cairo.common.bool import TRUE, FALSE

from openzeppelin.token.erc20.IERC20 import IERC20

from contracts.interface.ISwapPool import ISwapPool
from contracts.tickmath import TickMath
from contracts.math_utils import Utils
from contracts.interface.IUserPositionMgr import IUserPositionMgr
from contracts.swap_utils import SwapUtils

@storage_var
func _initialized() -> (res: felt) {
}


@storage_var
func _user_position_mgr_address() -> (res: felt) {
}

@storage_var
func _amount_in_cached() -> (res: Uint256) {
}

@constructor
func constructor{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}() {
    return ();
}

@external
func initializer{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    user_position_mgr_address: felt
) {
    with_attr error_message("only can be initilized once") {
        let (old) = _initialized.read();
        assert old = FALSE;
    }
    _initialized.write(TRUE);

    _user_position_mgr_address.write(user_position_mgr_address);
    _amount_in_cached.write(Uint256(Utils.MAX_UINT128, Utils.MAX_UINT128));

    return (); 
}

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

// external


func _exact_input_internal{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    path_len: felt,
    path: felt*,
    payer: felt,
    recipient: felt,
    amount_in: Uint256, 
    sqrt_price_limit: Uint256,
) -> (amount_out: Uint256) {
    alloc_locals;

    // get the pool info
    let token_in = path[0];
    let fee = path[1];
    let token_out = path[2];
    let pool_address = _get_pool_address(token_in, token_out, fee);

    let zero_for_one = is_le_felt(token_in, token_out);

    let (limit_price: Uint256) = SwapUtils.get_limit_price(sqrt_price_limit, zero_for_one);

    // call pool swap
    let (amount0: Uint256, amount1: Uint256) = ISwapPool.swap(contract_address=pool_address, recipient=recipient, zero_for_one=zero_for_one, amount_specified=amount_in, sqrt_price_limit_x96=limit_price, sender=payer, data_len=path_len, data=path);

    if (zero_for_one == TRUE) {
        let (neg_amount1: Uint256) = uint256_neg(amount1);
        return (neg_amount1,);
    }

    let (neg_amount0) = uint256_neg(amount0);
    return (neg_amount0,);
}

@external
func exact_input{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    token_in: felt,
    token_out: felt,
    fee: felt,
    recipient: felt,
    amount_in: Uint256, 
    sqrt_price_limit: Uint256,
    amount_out_min: Uint256,
    deadline: felt
) -> (amount_out: Uint256) {
    alloc_locals;

    uint256_check(amount_in);
    uint256_check(amount_out_min);
    Utils.assert_is_uint160(sqrt_price_limit);

    SwapUtils.check_deadline(deadline);

    let (payer) = get_caller_address();

    // alloc path array
    let (local path: felt*) = alloc();
    assert path[0] = token_in;
    assert path[1] = fee;
    assert path[2] = token_out;
    let (amount_out: Uint256) = _exact_input_internal(3, path, payer, recipient, amount_in, sqrt_price_limit);

    with_attr error_message("too little received") {
        let (is_valid) = uint256_le(amount_out_min, amount_out);
        assert is_valid = TRUE;
    }

    return (amount_out,);
}

func _exact_input_router{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    path_len: felt,
    path: felt*,
    payer: felt,
    recipient: felt,
    amount_in: Uint256 
) -> (amount_out: Uint256) {
    alloc_locals;

    let (has_multiple_pools) = Utils.is_gt(path_len, 3);

    if (has_multiple_pools == TRUE) {
        let (this_address) = get_contract_address();
        // the recipient should be this contract except the last hop
        let (amount_out: Uint256) = _exact_input_internal(path_len, path, payer, this_address, amount_in, Uint256(0, 0));
        // the payer should be the contract except the first hop
        let (new_amount_out: Uint256) = _exact_input_router(path_len - 2, path + 2, this_address, recipient, amount_out);
        return (new_amount_out,);
    }

    let (amount_out: Uint256) = _exact_input_internal(path_len, path, payer, recipient, amount_in, Uint256(0, 0));
    return (amount_out,);
}

@external
func exact_input_router{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    path_len: felt,
    path: felt*,
    recipient: felt,
    amount_in: Uint256, 
    amount_out_min: Uint256,
    deadline: felt
) -> (amount_out: Uint256) {
    alloc_locals;

    let (pool_num, rem) = unsigned_div_rem(path_len, 2);
    with_attr error_message("path_len illeagl") {
        assert rem = 1;
    }

    uint256_check(amount_in);
    uint256_check(amount_out_min);

    SwapUtils.check_deadline(deadline);

    let (payer) = get_caller_address();

    let (amount_out: Uint256) = _exact_input_router(path_len, path, payer, recipient, amount_in);

    with_attr error_message("too little received") {
        let (is_valid) = uint256_le(amount_out_min, amount_out);
        assert is_valid = TRUE;
    }

    return (amount_out,);
}


func _check_amount_out{range_check_ptr}(
    sqrt_price_limit: Uint256,
    amount_out: Uint256,
    amount_out_received: Uint256
) {
    alloc_locals;

    // it's technically possible to not receive the full output amount,
    // so if no price limit has been specified, require this possibility away
    let (flag) = uint256_eq(sqrt_price_limit, Uint256(0, 0));
    if (flag == TRUE) {
        with_attr error_message("amount_out not right") {
            let (is_valid) = uint256_eq(amount_out, amount_out_received);
            assert is_valid = TRUE;
        }
        return ();
    }
    return ();
}

func _exact_output_internal{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    recipient: felt,
    amount_out: Uint256, 
    sqrt_price_limit: Uint256,
    sender: felt,
    path_len: felt,
    path: felt*,
) -> (amount_in: Uint256) {
    alloc_locals;

    // decode data
    let token_out = path[0];
    let fee = path[1];
    let token_in = path[2];

    let pool_address = _get_pool_address(token_in, token_out, fee);

    let zero_for_one = is_le_felt(token_in, token_out);
     
    // minus means exact output
    let (amount_specified: Uint256) = uint256_neg(amount_out);

    let (limit_price: Uint256) = SwapUtils.get_limit_price(sqrt_price_limit, zero_for_one);

    let (amount0: Uint256, amount1: Uint256) = ISwapPool.swap(contract_address=pool_address, recipient=recipient, zero_for_one=zero_for_one, amount_specified=amount_specified, sqrt_price_limit_x96=limit_price, sender=sender, data_len=path_len, data=path);

    if (zero_for_one == TRUE) {
        let (amount_out_received: Uint256) = uint256_neg(amount1);
        _check_amount_out(sqrt_price_limit, amount_out, amount_out_received);
        return (amount0,);
    }
    let (amount_out_received: Uint256) = uint256_neg(amount0);
    _check_amount_out(sqrt_price_limit, amount_out, amount_out_received);
    return (amount1,);
}

@external
func exact_output{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    token_in: felt,
    token_out: felt,
    fee: felt,
    recipient: felt,
    amount_out: Uint256, 
    sqrt_price_limit: Uint256,
    amount_in_max: Uint256,
    deadline: felt
) -> (amount_in: Uint256) {
    alloc_locals;

    uint256_check(amount_out);
    uint256_check(amount_in_max);
    Utils.assert_is_uint160(sqrt_price_limit);

    SwapUtils.check_deadline(deadline);

    let (local path: felt*) = alloc();
    assert path[0] = token_out;
    assert path[1] = fee;
    assert path[2] = token_in;

    let (caller) = get_caller_address();
    let (amount_in: Uint256) = _exact_output_internal(recipient, amount_out, sqrt_price_limit, caller, 3, path);

    with_attr error_message("too much requested") {
        let (is_valid) = uint256_le(amount_in, amount_in_max);
        assert is_valid = TRUE;
    }

    _amount_in_cached.write(Uint256(Utils.MAX_UINT128, Utils.MAX_UINT128));
    return (amount_in,);
}

@external
func exact_output_router{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    path_len: felt,
    path: felt*,
    recipient: felt,
    amount_out: Uint256, 
    amount_in_max: Uint256,
    deadline: felt,
) -> (amount_in: Uint256) {
    alloc_locals;

    uint256_check(amount_out);
    uint256_check(amount_in_max);

    SwapUtils.check_deadline(deadline);

    let (caller) = get_caller_address();
    _exact_output_internal(recipient, amount_out, Uint256(0, 0), caller, path_len, path);

    let (amount_in: Uint256) = _amount_in_cached.read();

    with_attr error_message("too much requested") {
        let (is_valid) = uint256_le(amount_in, amount_in_max);
        assert is_valid = TRUE;
    }

    _amount_in_cached.write(Uint256(Utils.MAX_UINT128, Utils.MAX_UINT128));
    return (amount_in,);
}

func _swap_callback_1{range_check_ptr}(
    amount0: Uint256,
    amount1: Uint256,
    token_in: felt,
    token_out: felt
) -> (exact_input: felt, amount0: Uint256) {
    let (flag) = uint256_signed_lt(Uint256(0, 0), amount0);

    if (flag == TRUE) {
        let exact_input = is_le_felt(token_in, token_out);
        return (exact_input, amount0);
    }

    let exact_input = is_le_felt(token_out, token_in);
    return (exact_input, amount1);
}

func _pay{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    token_address: felt,
    payer: felt,
    recipient: felt,
    amount: Uint256
) {
    alloc_locals;

    let (this_address) = get_contract_address();
    if (this_address == payer) {
        IERC20.transfer(contract_address=token_address, recipient=recipient, amount=amount);
        return ();
    }
    IERC20.transferFrom(contract_address=token_address, sender=payer, recipient=recipient, amount=amount);
    return ();
}

@external
func swap_callback{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    amount0: Uint256, 
    amount1: Uint256, 
    sender: felt,
    data_len: felt,
    data: felt*
) {
    
    alloc_locals;

    let (flag1) = uint256_signed_lt(Uint256(0, 0), amount0);
    let (flag2) = uint256_signed_lt(Uint256(0, 0), amount1);
    with_attr error_message("zero amount swap is not allowed") {
        let is_valid = is_le(1, flag1 + flag2);
        assert is_valid = TRUE;
    }

    let (caller_address) = get_caller_address();

    // decode path, if is exact output, token_in is token_out, token_out is token_in
    let token_in = data[0];
    let fee = data[1];
    let token_out = data[2];

    // verify callback
    let pool_address = _get_pool_address(token_in, token_out, fee);
    assert caller_address = pool_address;

    let (exact_input, amount_pay: Uint256) = _swap_callback_1(amount0, amount1, token_in, token_out);

    let (caller_address) = get_caller_address();
    if (exact_input == TRUE) {
        _pay(token_in, sender, caller_address, amount_pay);
        return ();
    } 

    let (has_multiple_pools) = Utils.is_gt(data_len, 3);
    if (has_multiple_pools == TRUE) {
        let (amount_in: Uint256) = _exact_output_internal(caller_address, amount_pay, Uint256(0, 0), sender, data_len - 2, data + 2);
        return ();
    }

    _amount_in_cached.write(amount_pay);
    // token_out is token_in when exact output
    _pay(token_out, sender, caller_address, amount_pay);
    return ();
}
