%lang starknet

from starkware.starknet.common.syscalls import (get_caller_address, get_contract_address)
from starkware.cairo.common.cairo_builtins import HashBuiltin, BitwiseBuiltin
from starkware.cairo.common.uint256 import Uint256, uint256_le, uint256_add, uint256_lt, uint256_sub

from contracts.interface.IERC721Mintable import IERC721Mintable
from contracts.interface.ISwapPool import ISwapPool
from contracts.tickmath import TickMath
from contracts.liquidity_amounts import LiquidityAmounts
from contracts.math_utils import Utils
from contracts.fullmath import FullMath
from contracts.position_mgr import PositionInfo

struct UserPosition {
    pool_address: felt,
    tick_lower: felt,
    tick_upper: felt,
    liquidity: felt,
    fee_growth_inside0_x128: Uint256,
    fee_growth_inside1_x128: Uint256,
    tokens_owed0: felt,
    tokens_owed1: felt,
}

// storage

@storage_var
func _token_id() -> (res: Uint256) {
}

@storage_var
func _positions(token_id: Uint256) -> (position: UserPosition) {
}

@storage_var
func _erc721_contract() -> (address: felt) {
}

@storage_var
func _swap_pools(token0: felt, token1: felt, fee: felt) -> (address: felt) {
}

// event

@event
func IncreaseLiquidity(token_id: Uint256, liquidity: felt, amount0: Uint256, amount1: Uint256) {
}

@event
func DecreaseLiquidity(token_id: Uint256, liquidity: felt, amount0: Uint256, amount1: Uint256) {
}

@event
func Collect(token_id: Uint256, recipient: felt, amount0: felt, amount1: felt) {
}

@constructor
func constructor{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}() {
    return ();
}

// view

@view
func get_token_position{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    token_id: Uint256
) -> (position: UserPosition) {
    let (position: UserPosition) = _positions.read(token_id);
    return (position,);
}

@view
func get_erc721_contract{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}() -> (
    address: felt
) {
    let (address) = _erc721_contract.read();
    return (address,);
}

@view 
func get_pool_address{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    token0: felt,
    token1: felt,
    fee: felt
) -> (address: felt) {
    let token_a = Utils.min(token0, token1);
    let token_b = Utils.max(token0, token1);
    let (address) = _swap_pools.read(token_a, token_b, fee);
    return (address,);
}

func _write_pool_address{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    token0: felt,
    token1: felt,
    fee: felt,
    address: felt
) {
    let token_a = Utils.min(token0, token1);
    let token_b = Utils.max(token0, token1);
    _swap_pools.write(token_a, token_b, fee, address);
    return ();
}

// TODO: create_new_pool
@external
func register_pool_address{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    token0: felt,
    token1: felt,
    fee: felt,
    pool_address: felt
) {
    // TODO: only owner
    let (address) = get_pool_address(token0, token1, fee);
    with_attr error_message("pool already exist") {
        assert address = 0;
    }
    _write_pool_address(token0, token1, fee, pool_address);
    return ();
}

@external
func intialize{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    erc721_contract: felt
) {
    // only can be initilize once
    let (old) = _erc721_contract.read();
    with_attr error_message("user_position_mgr: only can be initilize once") {
        assert old = 0;
    }

    _erc721_contract.write(erc721_contract);
    return ();
}

func _get_mint_liuqidity{
    syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr, bitwise_ptr: BitwiseBuiltin*
}(
    pool_address: felt,
    tick_lower: felt,
    tick_upper: felt,
    amount0_desired: Uint256,
    amount1_desired: Uint256,
) -> (liquidity: felt) {
    alloc_locals;

    let (sqrt_price_x96: Uint256, _) = ISwapPool.get_cur_slot(contract_address=pool_address);
    let (sqrtRatioA: Uint256) = TickMath.get_sqrt_ratio_at_tick(tick_lower);
    let (sqrtRatioB: Uint256) = TickMath.get_sqrt_ratio_at_tick(tick_upper);

    let (liquidity) = LiquidityAmounts.get_liquidity_for_amounts(
        sqrt_price_x96, sqrtRatioA, sqrtRatioB, amount0_desired, amount1_desired
    );

    return (liquidity,);
}

@external
func mint{
    syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr, bitwise_ptr: BitwiseBuiltin*
}(
    recipient: felt,
    token0: felt,
    token1: felt,
    fee: felt,
    tick_lower: felt,
    tick_upper: felt,
    amount0_desired: Uint256,
    amount1_desired: Uint256,
    amount0_min: Uint256,
    amount1_min: Uint256,
) {
    alloc_locals;

    let (cur_token_id: Uint256) = _token_id.read();
    let (new_token_id: Uint256, _) = uint256_add(cur_token_id, Uint256(1, 0));
    _token_id.write(new_token_id);

    // mint position
    // get the pool address
    let (pool_address) = get_pool_address(token0, token1, fee);

    // remote call the add_liquidity function
    let (liquidity) = _get_mint_liuqidity(
        pool_address, tick_lower, tick_upper, amount0_desired, amount1_desired
    );

    let (this_address) = get_contract_address();
    let (amount0: Uint256, amount1: Uint256) = ISwapPool.add_liquidity(
        contract_address=pool_address,
        recipient=this_address,
        tick_lower=tick_lower,
        tick_upper=tick_upper,
        liquidity=liquidity,
    );
    let (flag1) = uint256_le(amount0_min, amount0);
    let (flag2) = uint256_le(amount1_min, amount1);
    let flag = flag1 + flag2;
    with_attr error_message("price slippage check") {
        assert flag = 2;
    }

    // mint the erc721
    let (erc721_contract) = _erc721_contract.read();
    IERC721Mintable.mint(contract_address=erc721_contract, to=recipient, tokenId=cur_token_id);

    let (slot_pos: PositionInfo) = ISwapPool.get_position(
        contract_address=pool_address, owner=this_address, tick_lower=tick_lower, tick_upper=tick_upper
    );
    // write the position
    let position = UserPosition(
        pool_address=pool_address,
        tick_lower=tick_lower,
        tick_upper=tick_upper,
        liquidity=liquidity,
        fee_growth_inside0_x128=slot_pos.fee_growth_inside0_x128,
        fee_growth_inside1_x128=slot_pos.fee_growth_inside1_x128,
        tokens_owed0=0,
        tokens_owed1=0,
    );
    _positions.write(new_token_id, position);

    IncreaseLiquidity.emit(new_token_id, liquidity, amount0, amount1);

    return ();
}

@external
func increase_liquidity{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr, bitwise_ptr: BitwiseBuiltin*}(
    token_id: Uint256,
    amount0_desired: Uint256,
    amount1_desired: Uint256,
    amount0_min: Uint256,
    amount1_min: Uint256
) -> (
    liquidity: felt,
    amount0: Uint256,
    amount1: Uint256
) {
    alloc_locals;

    let (position: UserPosition) = _positions.read(token_id);
    let pool_address = position.pool_address;
    let tick_lower = position.tick_lower;
    let tick_upper = position.tick_upper;

    let (liquidity) = _get_mint_liuqidity(
        pool_address, tick_lower, tick_upper, amount0_desired, amount1_desired
    );

    let(this_address) = get_contract_address();
    let (amount0: Uint256, amount1: Uint256) = ISwapPool.add_liquidity(
        contract_address=pool_address,
        recipient=this_address,
        tick_lower=tick_lower,
        tick_upper=tick_upper,
        liquidity=liquidity,
    );
    let (flag1) = uint256_le(amount0_min, amount0);
    let (flag2) = uint256_le(amount1_min, amount1);
    let flag = flag1 + flag2;
    with_attr error_message("price slippage check") {
        assert flag = 2;
    }

    // update the position
    let (slot_pos: PositionInfo) = ISwapPool.get_position(
        contract_address=pool_address, owner=this_address, tick_lower=tick_lower, tick_upper=tick_upper
    );

    let (tmp: Uint256) = uint256_sub(slot_pos.fee_growth_inside0_x128, position.fee_growth_inside0_x128);
    let (tokens_owed0: Uint256, _) = FullMath.uint256_mul_div(
        tmp,
        Uint256(liquidity, 0),
        Uint256(0, 1)
    );

    let (tmp2: Uint256) = uint256_sub(slot_pos.fee_growth_inside1_x128, position.fee_growth_inside1_x128);
    let (tokens_owed1: Uint256, _) = FullMath.uint256_mul_div(
        tmp2,
        Uint256(liquidity, 0),
        Uint256(0, 1)
    );

    let new_position = UserPosition(
        pool_address=pool_address,
        tick_lower=tick_lower,
        tick_upper=tick_upper,
        liquidity=liquidity + position.liquidity,
        fee_growth_inside0_x128=slot_pos.fee_growth_inside0_x128,
        fee_growth_inside1_x128=slot_pos.fee_growth_inside1_x128,
        tokens_owed0=position.tokens_owed0 + tokens_owed0.low,
        tokens_owed1=position.tokens_owed1 + tokens_owed1.low,
    );
    _positions.write(token_id, new_position);

    IncreaseLiquidity.emit(token_id, liquidity, amount0, amount1);

    return (liquidity, amount0, amount1);
}

@external
func decrease_liquidity{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr, bitwise_ptr: BitwiseBuiltin*}(
    token_id: Uint256,
    liquidity: felt,
    amount0_min: Uint256,
    amount1_min: Uint256
) -> (
    amount0: Uint256,
    amount1: Uint256
) {
    alloc_locals;

    //TODO: check the token_id owner

    let (is_valid) = Utils.is_gt(liquidity, 0);
    with_attr error_message("liquidity must be greater than 0") {
        assert is_valid = 1;
    }

    let (position: UserPosition) = _positions.read(token_id);
    let (is_valid) = is_le(liquidity, position.liquidity);
    with_attr error_message("liquidity must be less than or equal to the position liquidity") {
        assert is_valid = 1;
    }

    let pool_address = position.pool_address;
    let tick_lower = position.tick_lower;
    let tick_upper = position.tick_upper;

    let (amount0: Uint256, amount1: Uint256) = ISwapPool.remove_liquidity(
        contract_address=pool_address,
        tick_lower=tick_lower,
        tick_upper=tick_upper,
        liquidity=liquidity,
    );
    let (flag1) = uint256_le(amount0_min, amount0);
    let (flag2) = uint256_le(amount1_min, amount1);
    let flag = flag1 + flag2;
    with_attr error_message("price slippage check") {
        assert flag = 2;
    }

    // update the position
    let(this_address) = get_contract_address();
    let (slot_pos: PositionInfo) = ISwapPool.get_position(
        contract_address=pool_address, owner=this_address, tick_lower=tick_lower, tick_upper=tick_upper
    );

    let (tmp: Uint256) = uint256_sub(slot_pos.fee_growth_inside0_x128, position.fee_growth_inside0_x128);
    let (tmp2: Uint256, _) = FullMath.uint256_mul_div(
        tmp,
        Uint256(liquidity, 0),
        Uint256(0, 1)
    );
    let tokens_owed0 = position.tokens_owed0 + amount0.low + tmp2.low;

    let (tmp3: Uint256) = uint256_sub(slot_pos.fee_growth_inside1_x128, position.fee_growth_inside1_x128);
    let (tmp4: Uint256, _) = FullMath.uint256_mul_div(
        tmp3,
        Uint256(liquidity, 0),
        Uint256(0, 1)
    );
    let tokens_owed1 = position.tokens_owed1 + amount1.low + tmp4.low;

    let new_position = UserPosition(
        pool_address=pool_address,
        tick_lower=tick_lower,
        tick_upper=tick_upper,
        liquidity=position.liquidity - liquidity,
        fee_growth_inside0_x128=slot_pos.fee_growth_inside0_x128,
        fee_growth_inside1_x128=slot_pos.fee_growth_inside1_x128,
        tokens_owed0=tokens_owed0,
        tokens_owed1=tokens_owed1,
        );
    _positions.write(token_id, new_position);

    DecreaseLiquidity.emit(token_id, liquidity, amount0, amount1);

    return (amount0, amount1);
}
    
func _update_fees{
    syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr, bitwise_ptr: BitwiseBuiltin*
}(position: UserPosition) -> (
    tokens_owed0: felt,
    tokens_owed1: felt,
    fee_growth_inside0_x128: Uint256,
    fee_growth_inside1_x128: Uint256,
) {
    alloc_locals;

    let (is_valid) = Utils.is_gt(position.liquidity, 0);
    if (is_valid == 1) {
        ISwapPool.remove_liquidity(
            contract_address=position.pool_address,
            tick_lower=position.tick_lower,
            tick_upper=position.tick_upper,
            liquidity=0,
        );

        let (this_address) = get_contract_address();
        let (slot_pos: PositionInfo) = ISwapPool.get_position(
            contract_address=position.pool_address,
            owner=this_address,
            tick_lower=position.tick_lower,
            tick_upper=position.tick_upper,
        );

        let (tmp: Uint256) = uint256_sub(
            slot_pos.fee_growth_inside0_x128, position.fee_growth_inside0_x128
        );
        let (tmp1: Uint256, _) = FullMath.uint256_mul_div(
            tmp, Uint256(position.liquidity, 0), Uint256(0, 1)
        );
        let tokens_owed0 = position.tokens_owed0 + tmp1.low;

        let (tmp2: Uint256) = uint256_sub(
            slot_pos.fee_growth_inside1_x128, position.fee_growth_inside1_x128
        );
        let (tmp3: Uint256, _) = FullMath.uint256_mul_div(
            tmp2, Uint256(position.liquidity, 0), Uint256(0, 1)
        );
        let tokens_owed1 = position.tokens_owed1 + tmp3.low;

        return (
            tokens_owed0,
            tokens_owed1,
            slot_pos.fee_growth_inside0_x128,
            slot_pos.fee_growth_inside1_x128,
        );
    }

    return (
        position.tokens_owed0,
        position.tokens_owed1,
        position.fee_growth_inside0_x128,
        position.fee_growth_inside1_x128,
    );
}

@external
func collect{
    syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr, bitwise_ptr: BitwiseBuiltin*
}(token_id: Uint256, recipient: felt, amount0_max: felt, amount1_max: felt) -> (
    amount0: Uint256, amount1: Uint256
) {
    alloc_locals;

    // TODO: check approve
    // TODO: check token_id owner

    let (flag1) = Utils.is_lt(0, amount0_max);
    let (flag2) = Utils.is_lt(0, amount1_max);
    let (is_valid) = Utils.is_gt(flag1 + flag2, 0);
    with_attr error_message("user_position_mgr.collect: amount0 and amount1 can not be zero") {
        assert is_valid = 1;
    }

    let (position) = _positions.read(token_id);

    let (
        tokens_owed0,
        tokens_owed1,
        fee_growth_inside0_x128: Uint256,
        fee_growth_inside1_x128: Uint256,
    ) = _update_fees(position);

    let amount0_collect = Utils.min(tokens_owed0, amount0_max);
    let amount1_collect = Utils.min(tokens_owed1, amount1_max);

    let (amount0, amount1) = ISwapPool.collect(
        contract_address=position.pool_address,
        recipient=recipient,
        tick_lower=position.tick_lower,
        tick_upper=position.tick_upper,
        amount0_requested=amount0_collect,
        amount1_requested=amount1_collect,
    );

    _positions.write(
        token_id,
        UserPosition(
        pool_address=position.pool_address,
        tick_lower=position.tick_lower,
        tick_upper=position.tick_upper,
        liquidity=position.liquidity,
        fee_growth_inside0_x128=fee_growth_inside0_x128,
        fee_growth_inside1_x128=fee_growth_inside1_x128,
        tokens_owed0=tokens_owed0 - amount0_collect,
        tokens_owed1=tokens_owed1 - amount1_collect
        ),
    );

    Collect.emit(token_id, recipient, amount0_collect, amount1_collect);

    return (Uint256(amount0, 0), Uint256(amount1, 0));
}

@external
func burn{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(token_id: Uint256) {
    let (position: UserPosition) = _positions.read(token_id);

    with_attr error_message("user_position_mgr: position not clear") {
        assert position.liquidity = 0;
        assert position.tokens_owed0 = 0;
        assert position.tokens_owed1 = 0;
    }

    _positions.write(token_id, UserPosition(0, 0, 0, 0, Uint256(0, 0), Uint256(0, 0), 0, 0));

    // TODO: delegate call for get_caller_address
    let (erc721_contract) = _erc721_contract.read();
    IERC721Mintable.burn(contract_address=erc721_contract, tokenId=token_id);

    return ();
}
