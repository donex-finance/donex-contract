%lang starknet

from starkware.starknet.common.syscalls import get_caller_address, get_contract_address, deploy, get_block_timestamp
from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.cairo_builtins import HashBuiltin, BitwiseBuiltin
from starkware.cairo.common.uint256 import Uint256, uint256_le, uint256_add, uint256_lt, uint256_sub, uint256_neg, uint256_eq, uint256_signed_lt, uint256_check
from starkware.cairo.common.math_cmp import is_le, is_le_felt
from starkware.cairo.common.math import unsigned_div_rem
from starkware.cairo.common.bool import TRUE, FALSE

from openzeppelin.token.erc20.IERC20 import IERC20
from openzeppelin.access.ownable.library import Ownable
from openzeppelin.token.erc721.library import ERC721
from openzeppelin.introspection.erc165.library import ERC165
from openzeppelin.token.erc721.enumerable.library import ERC721Enumerable

from contracts.interface.ISwapPool import ISwapPool
from contracts.tickmath import TickMath
from contracts.liquidity_amounts import LiquidityAmounts
from contracts.math_utils import Utils
from contracts.fullmath import FullMath
from contracts.position_mgr import PositionInfo
from contracts.sqrt_price_math import SqrtPriceMath

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

struct PoolInfo {
    token0: felt,
    token1: felt,
    fee: felt,
}

// storage

@storage_var
func _token_id() -> (res: Uint256) {
}

@storage_var
func _positions(token_id: Uint256) -> (position: UserPosition) {
}

@storage_var
func _swap_pools(token0: felt, token1: felt, fee: felt) -> (address: felt) {
}

@storage_var
func _pool_infos(pool_address: felt) -> (info: PoolInfo) {
}

@storage_var
func _swap_pool_hash() -> (hash: felt) {
}

@storage_var
func _swap_pool_proxy_hash() -> (hash: felt) {
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

@event
func CreateNewPool(token0: felt, token1: felt, fee: felt, pool_address: felt) {
}

@constructor
func constructor{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}() {
    return ();
}

@external
func initializer{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    owner: felt,
    swap_pool_hash: felt,
    swap_pool_proxy_hash: felt,
    name: felt,
    symbol: felt
) {
    let (old) = _swap_pool_proxy_hash.read();
    with_attr error_message("user_position_mgr: only can be initilize once") {
        assert old = 0;
    }
    Ownable.initializer(owner);
    _swap_pool_hash.write(swap_pool_hash);
    _swap_pool_proxy_hash.write(swap_pool_proxy_hash);

    ERC721.initializer(name, symbol);
    ERC721Enumerable.initializer();
    return ();
}

// view

@view
func get_token_position{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    token_id: Uint256
) -> (position: UserPosition, pool_info: PoolInfo) {
    let (position: UserPosition) = _positions.read(token_id);
    let (is_valid) = Utils.is_eq(position.pool_address, 0);
    with_attr error_message("invalid token id") {
        assert is_valid = FALSE;
    }

    let (pool_info: PoolInfo) = _pool_infos.read(position.pool_address);

    return (position, pool_info);
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

@view
func owner{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}() -> (owner: felt) {
    return Ownable.owner();
}

@view
func get_pool_cur_price{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    token0: felt,
    token1: felt,
    fee: felt
) -> (sqrt_price_x96: Uint256, tick: felt) {
    let (pool_address) = get_pool_address(token0, token1, fee);
    let (sqrt_price_x96: Uint256, tick) = ISwapPool.get_cur_slot(contract_address=pool_address);
    return (sqrt_price_x96, tick);
}

func _get_position_liquidity_token{
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
}(
    position: UserPosition,
    sqrt_price_x96: Uint256,
    cur_tick
) -> (amount0: Uint256, amount1: Uint256) {
    alloc_locals;

    if (position.liquidity != 0) {
        let (sqrt_ratio0: Uint256) = TickMath.get_sqrt_ratio_at_tick(position.tick_lower);
        let (sqrt_ratio1: Uint256) = TickMath.get_sqrt_ratio_at_tick(position.tick_upper);

        let (is_valid) = Utils.is_lt_signed(cur_tick, position.tick_lower);
        if (is_valid == TRUE) {
            let (amount0: Uint256) = SqrtPriceMath.get_amount0_delta(
                sqrt_ratio0, sqrt_ratio1, position.liquidity, FALSE
            );
            return (amount0, Uint256(0, 0));
        }

        let (is_valid) = Utils.is_lt_signed(cur_tick, position.tick_upper);
        if (is_valid == TRUE) {
            let (amount0: Uint256) = SqrtPriceMath.get_amount0_delta(
                sqrt_price_x96, sqrt_ratio1, position.liquidity, FALSE
            );

            let (amount1: Uint256) = SqrtPriceMath.get_amount1_delta(
                sqrt_ratio0, sqrt_price_x96, position.liquidity, FALSE
            );

            return (amount0, amount1);
        }

        let (amount1: Uint256) = SqrtPriceMath.get_amount1_delta(
            sqrt_ratio0, sqrt_ratio1, position.liquidity, FALSE
        );
        return (Uint256(0, 0), amount1);
    }
    return (Uint256(0, 0), Uint256(0, 0));
}

@view
func get_position_token_amounts{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr, bitwise_ptr: BitwiseBuiltin*}(
    token_id: Uint256
) -> (token0_liquidity: Uint256, token1_liquidity: Uint256, tokens_owed0: felt, tokens_owed1: felt) {
    alloc_locals;

    let (position: UserPosition) = _positions.read(token_id);
    let (sqrt_price_x96: Uint256, tick) = ISwapPool.get_cur_slot(contract_address=position.pool_address);

    // get the liquidity token
    let (amount0: Uint256, amount1: Uint256) = _get_position_liquidity_token(
        position, sqrt_price_x96, tick
    );

    // get the fee
    let (fee_growth_inside0_x128: Uint256, fee_growth_inside1_x128: Uint256) = ISwapPool.get_position_token_fee(contract_address=position.pool_address, tick_lower=position.tick_lower, tick_upper=position.tick_upper);

    let (tmp: Uint256) = uint256_sub(
        fee_growth_inside0_x128, position.fee_growth_inside0_x128
    );
    let (tmp1: Uint256, _) = FullMath.uint256_mul_div(
        tmp, Uint256(position.liquidity, 0), Uint256(0, 1)
    );
    let tokens_owed0 = position.tokens_owed0 + tmp1.low;

    let (tmp2: Uint256) = uint256_sub(
        fee_growth_inside1_x128, position.fee_growth_inside1_x128
    );
    let (tmp3: Uint256, _) = FullMath.uint256_mul_div(
        tmp2, Uint256(position.liquidity, 0), Uint256(0, 1)
    );
    let tokens_owed1 = position.tokens_owed1 + tmp3.low;

    return (
        amount0,
        amount1,
        tokens_owed0,
        tokens_owed1
    );
}

//
//  external
//

func _write_pool_address{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    token0: felt,
    token1: felt,
    fee: felt,
    address: felt
) {
    let token_a = Utils.min(token0, token1);
    let token_b = Utils.max(token0, token1);
    _swap_pools.write(token_a, token_b, fee, address);
    _pool_infos.write(address, PoolInfo(token_a, token_b, fee));
    return ();
}

func _get_tickSpacing{range_check_ptr}(
    fee: felt
) -> felt {

    if (fee == 500) {
        return 10;
    } 
    if (fee == 3000) {
        return 60;
    } 
    if (fee == 10000) {
        return 200;
    }

    with_attr error_message("invalid fee level") {
        assert 0 = 1;
    }
    return 0;
}

@external
func create_and_initialize_pool{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    token0: felt,
    token1: felt,
    fee: felt,
    sqrt_price_x96: Uint256 // uint160
) -> (pool_address: felt) {
    alloc_locals;

    Utils.assert_is_uint160(sqrt_price_x96);

    let (is_valid) = Utils.is_eq(token0, token1);
    with_attr error_message("token0 or token1 is illegal") {
        assert is_valid = FALSE;
    }

    let (pool_address) = get_pool_address(token0, token1, fee);
    let (is_valid) = Utils.is_eq(pool_address, 0);
    with_attr error_message("pool already exists") {
        assert is_valid = TRUE;
    }

    let (this_address) = get_contract_address();

    let tick_spacing = _get_tickSpacing(fee);
    let (swap_pool_hash) = _swap_pool_hash.read();
    let (swap_pool_proxy_hash) = _swap_pool_proxy_hash.read();
    let (owner) = Ownable.owner();

    let (local calldata: felt*) = alloc();
    assert calldata[0] = swap_pool_hash;
    assert calldata[1] = tick_spacing;
    assert calldata[2] = fee;
    assert calldata[3] = token0;
    assert calldata[4] = token1;
    assert calldata[5] = this_address;

    // deploy contract
    let (pool_address) = deploy(
        class_hash=swap_pool_proxy_hash,
        contract_address_salt=tick_spacing,
        constructor_calldata_size=6,
        constructor_calldata=calldata,
        deploy_from_zero=1,
    );

    ISwapPool.initialize_price(contract_address=pool_address, sqrt_price_x96=sqrt_price_x96);

    _write_pool_address(token0, token1, fee, pool_address);

    CreateNewPool.emit(token0, token1, fee, pool_address);
    return (pool_address,);
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

func _check_pool_address{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    token0: felt,
    token1: felt,
    fee: felt
) -> felt {
    let (address) = get_pool_address(token0, token1, fee);
    let (is_valid) = Utils.is_eq(address, 0);
    with_attr error_message("pool not exist") {
        assert is_valid = FALSE;
    }
    return address;
}

func _check_token_order{range_check_ptr} (
    token0: felt,
    token1: felt
) {
    let is_valid = is_le_felt(token0, token1);
    with_attr error_message("token0 address should be less than token1 address") {
        assert is_valid = TRUE;
    }
    return ();
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
    deadline: felt
) -> (amount0: Uint256, amount1: Uint256) {
    alloc_locals;

    _check_deadline(deadline);

    _check_token_order(token0, token1);

    uint256_check(amount0_desired);
    uint256_check(amount1_desired);
    uint256_check(amount0_min);
    uint256_check(amount1_min);

    let (cur_token_id: Uint256) = _token_id.read();
    let (new_token_id: Uint256, _) = uint256_add(cur_token_id, Uint256(1, 0));
    _token_id.write(new_token_id);

    // mint position
    // get the pool address
    let pool_address = _check_pool_address(token0, token1, fee);

    // remote call the add_liquidity function
    let (liquidity) = _get_mint_liuqidity(
        pool_address, tick_lower, tick_upper, amount0_desired, amount1_desired
    );

    let (this_address) = get_contract_address();
    let (caller) = get_caller_address();
    let (amount0: Uint256, amount1: Uint256) = ISwapPool.add_liquidity(
        contract_address=pool_address,
        recipient=this_address,
        tick_lower=tick_lower,
        tick_upper=tick_upper,
        liquidity=liquidity,
        data=caller
    );
    let (flag1) = uint256_le(amount0_min, amount0);
    let (flag2) = uint256_le(amount1_min, amount1);
    let flag = flag1 + flag2;
    with_attr error_message("price slippage check") {
        assert flag = 2;
    }

    // mint the erc721
    ERC721Enumerable._mint(recipient, new_token_id);

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

    return (amount0, amount1);
}

@external
func increase_liquidity{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr, bitwise_ptr: BitwiseBuiltin*}(
    token_id: Uint256,
    amount0_desired: Uint256,
    amount1_desired: Uint256,
    amount0_min: Uint256,
    amount1_min: Uint256,
    deadline: felt
) -> (
    liquidity: felt,
    amount0: Uint256,
    amount1: Uint256
) {
    alloc_locals;

    _check_deadline(deadline);

    uint256_check(amount0_desired);
    uint256_check(amount1_desired);
    uint256_check(amount0_min);
    uint256_check(amount1_min);

    let (position: UserPosition) = _positions.read(token_id);
    let pool_address = position.pool_address;
    let tick_lower = position.tick_lower;
    let tick_upper = position.tick_upper;

    let (liquidity) = _get_mint_liuqidity(
        pool_address, tick_lower, tick_upper, amount0_desired, amount1_desired
    );

    let (this_address) = get_contract_address();
    let (caller) = get_caller_address();
    let (amount0: Uint256, amount1: Uint256) = ISwapPool.add_liquidity(
        contract_address=pool_address,
        recipient=this_address,
        tick_lower=tick_lower,
        tick_upper=tick_upper,
        liquidity=liquidity,
        data=caller
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
func add_liquidity_callback{
    syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr
}(
    token0: felt,
    token1: felt,
    fee: felt,
    amount0: Uint256, 
    amount1: Uint256, 
    data: felt
) {
    let (caller_address) = get_caller_address();
    // verify callback
    let (pool_address) = get_pool_address(token0, token1, fee);
    assert caller_address = pool_address;

    IERC20.transferFrom(contract_address=token0, sender=data, recipient=caller_address, amount=amount0);
    IERC20.transferFrom(contract_address=token1, sender=data, recipient=caller_address, amount=amount1);

    return ();
}

func _check_approverd_or_owner{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr} (
    address: felt,
    token_id: Uint256,
) {
    alloc_locals;

    let (owner) = ERC721.owner_of(token_id);
    if (owner == address) {
        return ();
    }

    let (approver) = ERC721.get_approved(token_id);

    with_attr error_message("_check_approverd_or_owner failed") {
        assert approver = address;
    }
    return ();
}

// @function remove liquidity from position
// @param {Uint256} token_id nft ID of position
// @param {uint128} liquidity amount of liquidity to remove
// @param {uint256} amount0_min minimum amount of token0 to remove from liquidity 
// @param {uint256} amount1_min minimum amount of token1 to remove from liquidity
// @param {felt} deadline deadline for transaction
@external
func decrease_liquidity{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr, bitwise_ptr: BitwiseBuiltin*}(
    token_id: Uint256,
    liquidity: felt, // uint128
    amount0_min: Uint256,
    amount1_min: Uint256,
    deadline: felt
) -> (
    amount0: Uint256,
    amount1: Uint256
) {
    alloc_locals;

    _check_deadline(deadline);

    uint256_check(amount0_min);
    uint256_check(amount1_min);

    // check the token_id owner
    let (caller) = get_caller_address();
    _check_approverd_or_owner(caller, token_id);

    // liquidity should greater than 0
    let (is_valid) = Utils.is_gt(liquidity, 0);
    with_attr error_message("DL: liquidity must be greater than 0") {
        assert is_valid = TRUE;
    }

    let (position: UserPosition) = _positions.read(token_id);
    let is_valid = is_le(liquidity, position.liquidity);
    with_attr error_message("DL: liquidity is more than own") {
        assert is_valid = TRUE;
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
    with_attr error_message("DL: price slippage check") {
        assert flag = 2;
    }

    // update the position
    let(this_address) = get_contract_address();
    let (slot_pos: PositionInfo) = ISwapPool.get_position(
        contract_address=pool_address, owner=this_address, tick_lower=tick_lower, tick_upper=tick_upper
    );

    // TODO: why this here use the uint128 not Uint256?
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

    // trigger an update of the position fees owed and fee growth snapshots if it has any liquidity
    let (is_valid) = Utils.is_gt(position.liquidity, 0);
    if (is_valid == TRUE) {
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
}(
    token_id: Uint256, 
    recipient: felt, 
    amount0_max: felt, // uint128
    amount1_max: felt  // uint128
) -> (
    amount0: Uint256, amount1: Uint256
) {
    alloc_locals;

    let (caller) = get_caller_address();
    _check_approverd_or_owner(caller, token_id);

    // check uint128
    Utils.assert_is_uint128(amount0_max);
    Utils.assert_is_uint128(amount1_max);

    let (flag1) = Utils.is_lt_signed(0, amount0_max);
    let (flag2) = Utils.is_lt_signed(0, amount1_max);
    let (is_valid) = Utils.is_gt(flag1 + flag2, 0);
    with_attr error_message("user_position_mgr.collect: amount0 and amount1 can not be zero") {
        assert is_valid = TRUE;
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
    alloc_locals;

    let (caller) = get_caller_address();
    _check_approverd_or_owner(caller, token_id);
    let (position: UserPosition) = _positions.read(token_id);

    with_attr error_message("user_position_mgr: position not clear") {
        assert position.liquidity = 0;
        assert position.tokens_owed0 = 0;
        assert position.tokens_owed1 = 0;
    }

    _positions.write(token_id, UserPosition(0, 0, 0, 0, Uint256(0, 0), Uint256(0, 0), 0, 0));

    // remove nft token
    ERC721Enumerable._burn(token_id);

    return ();
}

func _get_limit_price{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr} (
    sqrt_price_limit: Uint256, 
    zero_for_one: felt
) -> (res: Uint256) {

    alloc_locals;

    let (flag) = uint256_eq(sqrt_price_limit, Uint256(0, 0));
    if (flag == 1) {
        if (zero_for_one == 1) {
            let res: Uint256 = Uint256(TickMath.MIN_SQRT_RATIO + 1, 0);
            return (res,);
        }
        let (res: Uint256) = uint256_sub(Uint256(TickMath.MAX_SQRT_RATIO_LOW, TickMath.MAX_SQRT_RATIO_HIGH), Uint256(1, 0));
        return (res,);
    }

    return (sqrt_price_limit,);
}

func _check_deadline{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(deadline: felt) {
    alloc_locals;

    // Expired
    with_attr error_message("deadline") {
        let (block_timestamp) = get_block_timestamp();
        let flag = is_le_felt(block_timestamp, deadline);
        assert flag = TRUE;
    }

    return ();
}

@view
func get_exact_input{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    token_in: felt,
    token_out: felt,
    fee: felt,
    amount_in: Uint256, 
    sqrt_price_limit: Uint256,
) -> (amount_out: Uint256) {
    alloc_locals;

    let pool_address = _check_pool_address(token_in, token_out, fee);
    let (caller) = get_caller_address();

    let zero_for_one = is_le_felt(token_in, token_out);

    let (limit_price: Uint256) = _get_limit_price(sqrt_price_limit, zero_for_one);

    let (amount0: Uint256, amount1: Uint256) = ISwapPool.get_swap_results(contract_address=pool_address, zero_for_one=zero_for_one, amount_specified=amount_in, sqrt_price_limit_x96=limit_price);

    if (zero_for_one == 1) {
        let (neg_amount1: Uint256) = uint256_neg(amount1);
        return (neg_amount1,);
    }

    let (neg_amount0) = uint256_neg(amount0);
    return (neg_amount0,);
}

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
    let token_out  = path[1];
    let fee = path[2];
    let pool_address = _check_pool_address(token_in, token_out, fee);

    let zero_for_one = is_le_felt(token_in, token_out);

    let (limit_price: Uint256) = _get_limit_price(sqrt_price_limit, zero_for_one);

    // call pool swap
    let (amount0: Uint256, amount1: Uint256) = ISwapPool.swap(contract_address=pool_address, recipient=recipient, zero_for_one=zero_for_one, amount_specified=amount_in, sqrt_price_limit_x96=limit_price, data=payer);

    if (zero_for_one == 1) {
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

    _check_deadline(deadline);

    let (payer) = get_caller_address();

    // alloc path array
    let (local path: felt*) = alloc();
    assert path[0] = token_in;
    assert path[1] = token_out;
    assert path[2] = fee;
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
        // first pool token_out should be the second pool token_in
        with_attr error_message("pool path is not connected") {
            assert path[1] = path[3];
        }
        let (this_address) = get_contract_address();
        let (amount_out: Uint256) = _exact_input_internal(path_len, path, payer, this_address, amount_in, Uint256(0, 0));
        let (new_amount_out: Uint256) = _exact_input_router(path_len - 3, path + 3, this_address, this_address, amount_out);
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

    let (pool_num, rem) = unsigned_div_rem(path_len, 3);
    with_attr error_message("path_len illeagl") {
        assert rem = 0;
    }

    uint256_check(amount_in);
    uint256_check(amount_out_min);

    _check_deadline(deadline);

    let (payer) = get_caller_address();

    let (amount_out: Uint256) = _exact_input_router(path_len, path, payer, recipient, amount_in);

    with_attr error_message("too little received") {
        let (is_valid) = uint256_le(amount_out_min, amount_out);
        assert is_valid = TRUE;
    }

    return (amount_out,);
}

@view
func get_exact_output{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    token_in: felt,
    token_out: felt,
    fee: felt,
    amount_out: Uint256, 
    sqrt_price_limit: Uint256
) -> (amount_in: Uint256) {
    alloc_locals;

    let pool_address = _check_pool_address(token_in, token_out, fee);
    let (caller) = get_caller_address();

    // unsined int
    let zero_for_one = is_le_felt(token_in, token_out);
     
    let (amount_specified: Uint256) = uint256_neg(amount_out);

    let (limit_price: Uint256) = _get_limit_price(sqrt_price_limit, zero_for_one);

    let (amount0: Uint256, amount1: Uint256) = ISwapPool.get_swap_results(contract_address=pool_address, zero_for_one=zero_for_one, amount_specified=amount_specified, sqrt_price_limit_x96=limit_price);

    if (zero_for_one == 1) {
        return (amount0,);
    }
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

    _check_deadline(deadline);

    let pool_address = _check_pool_address(token_in, token_out, fee);
    let (caller) = get_caller_address();

    // unsined int
    let zero_for_one = is_le_felt(token_in, token_out);
     
    let (amount_specified: Uint256) = uint256_neg(amount_out);

    let (limit_price: Uint256) = _get_limit_price(sqrt_price_limit, zero_for_one);

    let (amount0: Uint256, amount1: Uint256) = ISwapPool.swap(contract_address=pool_address, recipient=recipient, zero_for_one=zero_for_one, amount_specified=amount_specified, sqrt_price_limit_x96=limit_price, data=caller);

    if (zero_for_one == 1) {
        let (is_valid) = uint256_le(amount0, amount_in_max);
        with_attr error_message("too much requested") {
            assert is_valid = TRUE;
        }
        return (amount0,);
    }
    let (is_valid) = uint256_le(amount1, amount_in_max);
    with_attr error_message("too much requested") {
        assert is_valid = TRUE;
    }
    return (amount1,);
}

@external
func swap_callback{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    token0: felt,
    token1: felt,
    fee: felt,
    amount0: Uint256, 
    amount1: Uint256, 
    data: felt
) {
    
    alloc_locals;

    let (caller_address) = get_caller_address();
    // verify callback
    let (pool_address) = get_pool_address(token0, token1, fee);
    assert caller_address = pool_address;

    let (flag1) = uint256_signed_lt(Uint256(0, 0), amount0);
    if (flag1 == 1) {
        IERC20.transferFrom(contract_address=token0, sender=data, recipient=caller_address, amount=amount0);
        return ();
    }

    let (flag2) = uint256_signed_lt(Uint256(0, 0), amount1);
    if (flag2 == 1) {
        IERC20.transferFrom(contract_address=token1, sender=data, recipient=caller_address, amount=amount1);
        return ();
    }
    return ();
}

@external
func transferOwnership{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    newOwner: felt
) {
    Ownable.transfer_ownership(newOwner);
    return ();
}

@external
func renounceOwnership{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}() {
    Ownable.renounce_ownership();
    return ();
}

@external
func update_swap_pool{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    swap_pool_hash: felt,
    swap_pool_proxy_hash: felt
) {
    Ownable.assert_only_owner();
    _swap_pool_hash.write(swap_pool_hash);
    _swap_pool_proxy_hash.write(swap_pool_proxy_hash);
    return ();
}

@external
func collect_protocol{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    token0: felt,
    token1: felt,
    fee: felt,
    recipient: felt, 
    amount0_requested: felt, 
    amount1_requested: felt
) -> (amount0: felt, amount1: felt) {
    alloc_locals;

    Ownable.assert_only_owner();

    let pool_address = _check_pool_address(token0, token1, fee);

    let (amount0, amount1) = ISwapPool.collect_protocol(contract_address=pool_address, recipient=recipient, amount0_requested=amount0_requested, amount1_requested=amount1_requested);

    return (amount0, amount1);
}

@external
func set_fee_protocol{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    token0: felt,
    token1: felt,
    fee: felt,
    fee_protocol0: felt, 
    fee_protocol1: felt
) {
    
    alloc_locals;

    Ownable.assert_only_owner();

    let pool_address = _check_pool_address(token0, token1, fee);

    ISwapPool.set_fee_protocol(contract_address=pool_address, fee_protocol0=fee_protocol0, fee_protocol1=fee_protocol1);

    return ();
}

@external
func upgrade_swap_pool_class_hash{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    token0: felt,
    token1: felt,
    fee: felt,
    swap_pool_hash: felt
) {
    Ownable.assert_only_owner();
    let pool_address = _check_pool_address(token0, token1, fee);
    ISwapPool.upgrade(contract_address=pool_address, new_implementation=swap_pool_hash);
    return ();
}

//**************************************************************************************************ERC721 interface//**************************************************************************************************

//
// Getters
//

@view
func totalSupply{pedersen_ptr: HashBuiltin*, syscall_ptr: felt*, range_check_ptr}() -> (
    totalSupply: Uint256
) {
    let (totalSupply: Uint256) = ERC721Enumerable.total_supply();
    return (totalSupply=totalSupply);
}

@view
func tokenByIndex{pedersen_ptr: HashBuiltin*, syscall_ptr: felt*, range_check_ptr}(
    index: Uint256
) -> (tokenId: Uint256) {
    let (tokenId: Uint256) = ERC721Enumerable.token_by_index(index);
    return (tokenId=tokenId);
}

@view
func tokenOfOwnerByIndex{pedersen_ptr: HashBuiltin*, syscall_ptr: felt*, range_check_ptr}(
    owner: felt, index: Uint256
) -> (tokenId: Uint256) {
    let (tokenId: Uint256) = ERC721Enumerable.token_of_owner_by_index(owner, index);
    return (tokenId=tokenId);
}

@view
func supportsInterface{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    interfaceId: felt
) -> (success: felt) {
    return ERC165.supports_interface(interfaceId);
}

@view
func name{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}() -> (name: felt) {
    return ERC721.name();
}

@view
func symbol{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}() -> (symbol: felt) {
    return ERC721.symbol();
}

@view
func balanceOf{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(owner: felt) -> (
    balance: Uint256
) {
    return ERC721.balance_of(owner);
}

@view
func ownerOf{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(tokenId: Uint256) -> (
    owner: felt
) {
    return ERC721.owner_of(tokenId);
}

@view
func getApproved{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    tokenId: Uint256
) -> (approved: felt) {
    return ERC721.get_approved(tokenId);
}

@view
func isApprovedForAll{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    owner: felt, operator: felt
) -> (isApproved: felt) {
    let (isApproved: felt) = ERC721.is_approved_for_all(owner, operator);
    return (isApproved=isApproved);
}

@view
func tokenURI{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    tokenId: Uint256
) -> (tokenURI: felt) {
    let (tokenURI: felt) = ERC721.token_uri(tokenId);
    return (tokenURI=tokenURI);
}

//
// Externals
//

@external
func approve{pedersen_ptr: HashBuiltin*, syscall_ptr: felt*, range_check_ptr}(
    to: felt, tokenId: Uint256
) {
    ERC721.approve(to, tokenId);
    return ();
}

@external
func setApprovalForAll{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    operator: felt, approved: felt
) {
    ERC721.set_approval_for_all(operator, approved);
    return ();
}

@external
func transferFrom{pedersen_ptr: HashBuiltin*, syscall_ptr: felt*, range_check_ptr}(
    from_: felt, to: felt, tokenId: Uint256
) {
    ERC721Enumerable.transfer_from(from_, to, tokenId);
    return ();
}

@external
func safeTransferFrom{pedersen_ptr: HashBuiltin*, syscall_ptr: felt*, range_check_ptr}(
    from_: felt, to: felt, tokenId: Uint256, data_len: felt, data: felt*
) {
    ERC721Enumerable.safe_transfer_from(from_, to, tokenId, data_len, data);
    return ();
}

@external
func setTokenURI{pedersen_ptr: HashBuiltin*, syscall_ptr: felt*, range_check_ptr}(
    tokenId: Uint256, tokenURI: felt
) {
    Ownable.assert_only_owner();
    ERC721._set_token_uri(tokenId, tokenURI);
    return ();
}
