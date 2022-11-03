%lang starknet

from starkware.cairo.common.cairo_builtins import HashBuiltin, BitwiseBuiltin
from starkware.starknet.common.syscalls import get_caller_address, get_contract_address
from starkware.cairo.common.uint256 import (
    Uint256,
    uint256_mul,
    uint256_shr,
    uint256_shl,
    uint256_lt,
    uint256_le,
    uint256_add,
    uint256_unsigned_div_rem,
    uint256_or,
    uint256_sub,
    uint256_and,
    uint256_eq,
    uint256_signed_lt,
    uint256_neg,
    uint256_signed_nn,
    uint256_check
)
from starkware.cairo.common.bool import FALSE, TRUE
from starkware.cairo.common.math import unsigned_div_rem, assert_in_range
from starkware.cairo.common.math_cmp import is_le, is_nn

from openzeppelin.token.erc20.IERC20 import IERC20
from openzeppelin.access.ownable.library import Ownable
from openzeppelin.security.safemath.library import SafeUint256

from contracts.tick_mgr import TickMgr, TickInfo
from contracts.tick_bitmap import TickBitmap
from contracts.position_mgr import PositionMgr, PositionInfo
from contracts.swapmath import SwapMath
from contracts.tickmath import TickMath
from contracts.math_utils import Utils
from contracts.fullmath import FullMath
from contracts.sqrt_price_math import SqrtPriceMath
from contracts.interface.ISwapPoolCallback import ISwapPoolCallback

struct SlotState {
    sqrt_price_x96: Uint256,
    tick: felt,
}

struct SwapState {
    amount_specified_remaining: Uint256,
    amount_caculated: Uint256,
    sqrt_price_x96: Uint256,
    tick: felt,
    fee_growth_global_x128: Uint256,
    protocol_fee: felt,
    liquidity: felt,
}

struct StepComputations {
    sqrt_price_start_x96: Uint256,
    tick_next: felt,
    initialized: felt,
    sqrt_price_next_x96: Uint256,
    amount_in: Uint256,
    amount_out: Uint256,
    fee_amount: Uint256,
}

struct ModifyPositionParams {
    // the address that owns the position
    owner: felt,
    // the lower and upper tick of the position
    tick_lower: felt,
    tick_upper: felt,
    // any change in liquidity
    liquidity_delta: felt,
}

@storage_var
func _fee_protocol() -> (fee_protocol: felt) {
}

@storage_var
func _slot_unlocked() -> (unlocked: felt) {
}

@storage_var
func _slot0() -> (slot0: SlotState) {
}

@storage_var
func _protocol_fee_token0() -> (fee: felt) {
}

@storage_var
func _protocol_fee_token1() -> (fee: felt) {
}

@storage_var
func _liquidity() -> (liquidity: felt) {
}

@storage_var
func _fee_growth_global0_x128() -> (fee_growth_global_0x128: Uint256) {
}

@storage_var
func _fee_growth_global1_x128() -> (fee_growth_global_1x128: Uint256) {
}

@storage_var
func _tick_spacing() -> (tick_spacing: felt) {
}

@storage_var
func _fee() -> (fee: felt) {
}

@storage_var
func _max_liquidity_per_tick() -> (max_liquidity_per_tick: felt) {
}

@storage_var
func _token0() -> (address: felt) {
}

@storage_var
func _token1() -> (address: felt) {
}

@event
func AddLiquidity(
    recipient: felt,
    tick_lower: felt,
    tick_upper: felt,
    amount: felt,
    amount0: Uint256,
    amount1: Uint256,
) {
}

@event
func RemoveLiquidity(
    recipient: felt,
    tick_lower: felt,
    tick_upper: felt,
    amount: felt,
    amount0: Uint256,
    amount1: Uint256,
) {
}

@event
func Swap(
    recipient: felt,
    zero_for_one: felt,
    amount_specified: Uint256,
    amount0: Uint256,
    amount1: Uint256,
    sqrt_price_x96: Uint256,
    liquidity: felt,
    tick: felt,
) {
}

@event
func Collect(
    caller: felt,
    recipient: felt,
    tick_lower: felt,
    tick_upper: felt,
    amount0_requested: felt,
    amount1_requested: felt,
    amount0: felt,
    amount1: felt,
) {
}

@event
func CollectProtocol(
    recipient: felt, amount0_requested: felt, amount1_requested: felt, amount0: felt, amount1: felt
) {
}

@event
func TransferToken(token_contract: felt, to: felt, amount: Uint256) {
}

@event
func SetFeeProtocol(fee_protocol0: felt, fee_protocol1: felt, fee_protocol: felt) {
}

@constructor
func constructor{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}() {
    return ();
}

@external
func initializer{
    syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr, bitwise_ptr: BitwiseBuiltin*
}(
    tick_spacing: felt, 
    fee: felt, 
    token_a: felt, 
    token_b: felt, 
    owner: felt 
) {
    alloc_locals;

    _tick_spacing.write(tick_spacing);
    _fee.write(fee);

    let token0 = Utils.min(token_a, token_b); 
    let token1 = Utils.max(token_a, token_b);
    _token0.write(token0);
    _token1.write(token1);

    let (max_liquidity_per_tick) = TickMgr.get_max_liquidity_per_tick(tick_spacing);
    _max_liquidity_per_tick.write(max_liquidity_per_tick);

    Ownable.initializer(owner);
    
    return ();
}

@view
func get_fee_protocol{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}() -> (
    slot: felt
) {
    let (res) = _fee_protocol.read();
    return (res,);
}

@view
func get_cur_slot{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}() -> (
    sqrt_price_x96: Uint256, tick: felt
) {
    let (slot: SlotState) = _slot0.read();
    return (slot.sqrt_price_x96, slot.tick);
}

@view
func get_max_liquidity_per_tick{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    ) -> (liquidity: felt) {
    let (liquidity: felt) = _max_liquidity_per_tick.read();
    return (liquidity,);
}

@view
func get_protocol_fees{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}() -> (
    fee_token0: felt, fee_token1: felt
) {
    let (fee_token0) = _protocol_fee_token0.read();
    let (fee_token1) = _protocol_fee_token1.read();
    return (fee_token0, fee_token1);
}

@view
func get_tick{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(tick: felt) -> (
    tick: TickInfo
) {
    let (tick_info: TickInfo) = TickMgr.get_tick(tick);
    return (tick_info,);
}

@view
func get_tick_spacing{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}() -> (
    tick_spacing: felt
) {
    let (tick_spacing) = _tick_spacing.read();
    return (tick_spacing,);
}

@view
func get_position{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    address: felt, tick_lower: felt, tick_upper: felt
) -> (position: PositionInfo) {
    let (position: PositionInfo) = PositionMgr.get(address, tick_lower, tick_upper);
    return (position,);
}

@view
func get_liquidity{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}() -> (
    liquidity: felt
) {
    let (liquidity) = _liquidity.read();
    return (liquidity,);
}

@view
func balance0{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}() -> (
    balance: Uint256
) {
    let (token0) = _token0.read();
    let (address) = get_contract_address();
    let (balance) = IERC20.balanceOf(contract_address=token0, account=address);
    return (balance,);
}

@view
func balance1{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}() -> (
    balance: Uint256
) {
    let (token1) = _token1.read();
    let (address) = get_contract_address();
    let (balance) = IERC20.balanceOf(contract_address=token1, account=address);
    return (balance,);
}

@view
func get_position_token_fee{
    syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr, bitwise_ptr: BitwiseBuiltin*
}(
    tick_lower: felt,
    tick_upper: felt,
) -> (token0_fee: Uint256, token1_fee: Uint256) {
    alloc_locals;

    let (slot0: SlotState) = _slot0.read();
    let tick = slot0.tick;
    let (fee_growth_global0_x128: Uint256) = _fee_growth_global0_x128.read();
    let (fee_growth_global1_x128: Uint256) = _fee_growth_global1_x128.read();
    let (
        fee_growth_inside0_x128: Uint256, fee_growth_inside1_x128: Uint256
    ) = TickMgr.get_fee_growth_inside(
        tick_lower, tick_upper, tick, fee_growth_global0_x128, fee_growth_global1_x128
    );
    return (fee_growth_inside0_x128, fee_growth_inside1_x128);
}

@external
func initialize_price{
    syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr, bitwise_ptr: BitwiseBuiltin*
}(
    sqrt_price_x96: Uint256 // uint160
) {
    alloc_locals;
    Utils.assert_is_uint160(sqrt_price_x96);

    let (slot0) = _slot0.read();
    let (is_valid) = uint256_eq(slot0.sqrt_price_x96, Uint256(0, 0));
    with_attr error_message("initialize more than once") {
        assert is_valid = TRUE;
    }

    let (tick) = TickMath.get_tick_at_sqrt_ratio(sqrt_price_x96);

    let new_slot0: SlotState = SlotState(sqrt_price_x96=sqrt_price_x96, tick=tick);
    _slot0.write(new_slot0);

    _unlock();

    return ();
}

func _transfer_token{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    token_contract: felt, recipient: felt, amount: Uint256
) {
    alloc_locals;
    // transfer token
    IERC20.transfer(contract_address=token_contract, recipient=recipient, amount=amount);
    TransferToken.emit(token_contract, recipient, amount);
    return ();
}

func _transfer_token_cond{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    cond: felt, token_contract: felt, recipient: felt, value: Uint256
) {
    alloc_locals;

    if (cond == 1) {
        _transfer_token(token_contract, recipient, value);
        return ();
    }
    return ();
}

func _lock{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}() {
    let (slot_unlocked) = _slot_unlocked.read();
    with_attr error_message("swap is locked") {
        assert slot_unlocked = TRUE;
    }
    _slot_unlocked.write(0);
    return ();
}

func _unlock{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}() {
    _slot_unlocked.write(1);
    return ();
}

func _compute_swap_step_1{range_check_ptr}(
    exact_input: felt,
    state: SwapState,
    amount_in: Uint256,
    amount_out: Uint256,
    fee_amount: Uint256,
) -> (amount_specified_remaining: Uint256, amount_caculated: Uint256) {
    if (exact_input == 1) {
        let (tmp: Uint256, _) = uint256_add(amount_in, fee_amount);
        let (amount_specified_remaining: Uint256) = uint256_sub(
            state.amount_specified_remaining, tmp
        );

        let (amount_caculated: Uint256) = uint256_sub(state.amount_caculated, amount_out);

        return (amount_specified_remaining, amount_caculated);
    }

    let (amount_specified_remaining: Uint256, _) = uint256_add(
        state.amount_specified_remaining, amount_out
    );

    let (tmp: Uint256, _) = uint256_add(amount_in, fee_amount);
    let (amount_caculated: Uint256, _) = uint256_add(state.amount_caculated, tmp);

    return (amount_specified_remaining, amount_caculated);
}

func _compute_swap_step_2{range_check_ptr}(
    fee_protocol: felt, protocol_fee: felt, fee_amount: Uint256
) -> (new_fee_amount: Uint256, new_protocol_fee: felt) {
    let (is_valid) = Utils.is_gt(fee_protocol, 0);
    if (is_valid == TRUE) {
        let (delta: Uint256, _) = uint256_unsigned_div_rem(fee_amount, Uint256(fee_protocol, 0));
        let (new_fee_amount: Uint256) = uint256_sub(fee_amount, delta);

        // TODO: overflow?
        return (new_fee_amount, protocol_fee + delta.low);
    }
    return (fee_amount, protocol_fee);
}

func _compute_swap_step_3{range_check_ptr, bitwise_ptr: BitwiseBuiltin*}(
    state: SwapState, fee_amount: Uint256
) -> (fee_growth_global_x128: Uint256) {
    let (is_valid) = Utils.is_gt(state.liquidity, 0);
    if (is_valid == TRUE) {
        let (tmp: Uint256, _) = FullMath.uint256_mul_div(
            fee_amount, Uint256(0, 1), Uint256(state.liquidity, 0)
        );
        let (fee_growth_global_x128: Uint256, _) = uint256_add(state.fee_growth_global_x128, tmp);
        return (fee_growth_global_x128,);
    }
    return (state.fee_growth_global_x128,);
}

func _compute_swap_step_4_1{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    zero_for_one: felt, tick_next: felt, state_fee_growth_global_x128: Uint256
) -> (liquidity_net: felt) {
    if (zero_for_one == 1) {
        let (fee_growth_global1_x128: Uint256) = _fee_growth_global1_x128.read();
        let (tmp_felt) = TickMgr.cross(
            tick_next, state_fee_growth_global_x128, fee_growth_global1_x128
        );
        tempvar liquidity_net = -tmp_felt;
        return (liquidity_net,);
    }

    let (fee_growth_global0_x128: Uint256) = _fee_growth_global0_x128.read();
    let (liquidity_net) = TickMgr.cross(
        tick_next, fee_growth_global0_x128, state_fee_growth_global_x128
    );
    return (liquidity_net,);
}

func _compute_swap_step_4{
    syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr, bitwise_ptr: BitwiseBuiltin*
}(
    state: SwapState,
    state_sqrt_price_x96: Uint256,
    sqrt_price_start_x96: Uint256,
    sqrt_price_next_x96: Uint256,
    state_fee_growth_global_x128: Uint256,
    tick_next: felt,
    zero_for_one: felt,
    initialized: felt,
) -> (liquidity: felt, tick: felt) {
    alloc_locals;

    let (is_valid) = uint256_eq(state_sqrt_price_x96, sqrt_price_next_x96);
    if (is_valid == TRUE) {
        let (tick) = Utils.cond_assign(zero_for_one, tick_next - 1, tick_next);

        if (initialized == 1) {
            let (liquidity_net) = _compute_swap_step_4_1(
                zero_for_one, tick_next, state_fee_growth_global_x128
            );

            let (liquidity) = Utils.u128_safe_add(state.liquidity, liquidity_net);

            return (liquidity, tick);
        }

        return (state.liquidity, tick);
    }

    let (is_valid) = uint256_eq(state_sqrt_price_x96, sqrt_price_start_x96);
    if (is_valid == FALSE) {
        let (tick) = TickMath.get_tick_at_sqrt_ratio(state_sqrt_price_x96);
        return (state.liquidity, tick);
    }

    return (state.liquidity, state.tick);
}

func _compute_swap_step{
    syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr, bitwise_ptr: BitwiseBuiltin*
}(
    state: SwapState,
    fee_protocol: felt,
    exact_input: felt,
    zero_for_one: felt,
    sqrt_price_limit_x96: Uint256,
) -> (state: SwapState) {
    alloc_locals;

    let (flag1) = uint256_eq(state.amount_specified_remaining, Uint256(0, 0));
    let (flag2) = uint256_eq(state.sqrt_price_x96, sqrt_price_limit_x96);

    if (flag1 + flag2 != 0) {
        return (state,);
    }

    let (tick_spacing) = _tick_spacing.read();

    let (tick_next, initialized) = TickBitmap.next_valid_tick_within_one_word(
        state.tick, tick_spacing, zero_for_one
    );

    let sqrt_price_start_x96: Uint256 = state.sqrt_price_x96;

    let (is_valid) = Utils.is_lt_signed(tick_next, TickMath.MIN_TICK);
    let (tick_next) = Utils.cond_assign(is_valid, TickMath.MIN_TICK, tick_next);

    let (is_valid) = Utils.is_lt_signed(TickMath.MAX_TICK, tick_next);
    let (tick_next) = Utils.cond_assign(is_valid, TickMath.MAX_TICK, tick_next);

    let (sqrt_price_next_x96: Uint256) = TickMath.get_sqrt_ratio_at_tick(tick_next);

    if (zero_for_one == 1) {
        let (flag) = uint256_lt(sqrt_price_next_x96, sqrt_price_limit_x96);
    } else {
        let (flag) = uint256_lt(sqrt_price_limit_x96, sqrt_price_next_x96);
    }

    let (sqrt_price_target_x96: Uint256) = Utils.cond_assign_uint256(
        flag, sqrt_price_limit_x96, sqrt_price_next_x96
    );

    let (fee) = _fee.read();
    let (
        state_sqrt_price_x96: Uint256, amount_in: Uint256, amount_out: Uint256, fee_amount: Uint256
    ) = SwapMath.compute_swap_step(
        state.sqrt_price_x96,
        sqrt_price_target_x96,
        state.liquidity,
        state.amount_specified_remaining,
        fee,
    );

    let (
        state_amount_specified_remaining: Uint256, state_amount_caculated: Uint256
    ) = _compute_swap_step_1(exact_input, state, amount_in, amount_out, fee_amount);

    let (fee_amount: Uint256, state_protocol_fee) = _compute_swap_step_2(
        fee_protocol, state.protocol_fee, fee_amount
    );

    let (state_fee_growth_global_x128: Uint256) = _compute_swap_step_3(state, fee_amount);

    let (state_liquidity, state_tick) = _compute_swap_step_4(
        state,
        state_sqrt_price_x96,
        sqrt_price_start_x96,
        sqrt_price_next_x96,
        state_fee_growth_global_x128,
        tick_next,
        zero_for_one,
        initialized,
    );

    let new_state: SwapState = SwapState(
        amount_specified_remaining=state_amount_specified_remaining,
        amount_caculated=state_amount_caculated,
        sqrt_price_x96=state_sqrt_price_x96,
        tick=state_tick,
        fee_growth_global_x128=state_fee_growth_global_x128,
        protocol_fee=state_protocol_fee,
        liquidity=state_liquidity,
    );

    return _compute_swap_step(new_state, fee_protocol, exact_input, zero_for_one, sqrt_price_limit_x96);
}

func _swap_1{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    slot0: SlotState, sqrt_price_limit_x96: Uint256, zero_for_one
) -> (res: felt) {
    alloc_locals;

    let (fee_protocol) = _fee_protocol.read();
    if (zero_for_one == 1) {
        let (is_valid) = uint256_lt(sqrt_price_limit_x96, slot0.sqrt_price_x96);
        with_attr error_message("ZO: price limit too high") {
            assert is_valid = TRUE;
        }

        let (is_valid) = uint256_lt(Uint256(TickMath.MIN_SQRT_RATIO, 0), sqrt_price_limit_x96);
        with_attr error_message("ZO: price limit too low") {
            assert is_valid = TRUE;
        }

        let (_, res) = unsigned_div_rem(fee_protocol, 16);

        return (res,);
    }

    let (is_valid) = uint256_lt(slot0.sqrt_price_x96, sqrt_price_limit_x96);
    with_attr error_message("OZ: price limit too low") {
        assert is_valid = TRUE;
    }

    let (is_valid) = uint256_lt(
        sqrt_price_limit_x96, Uint256(TickMath.MAX_SQRT_RATIO_LOW, TickMath.MAX_SQRT_RATIO_HIGH)
    );
    with_attr error_message("OZ: price limit too high") {
        assert is_valid = TRUE;
    }

    let (res, _) = unsigned_div_rem(fee_protocol, 16);
    return (res,);
}

func _swap_2{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    state_fee_growth_global_x128: Uint256, protocol_fee: felt, zero_for_one: felt
) {
    alloc_locals;
    if (zero_for_one == 1) {
        _fee_growth_global0_x128.write(state_fee_growth_global_x128);

        let (is_valid) = Utils.is_gt(protocol_fee, 0);
        if (is_valid == TRUE) {
            let (protocol_fee_token0) = _protocol_fee_token0.read();
            _protocol_fee_token0.write(protocol_fee_token0 + protocol_fee);
            return ();
        }
        return ();
    }

    _fee_growth_global1_x128.write(state_fee_growth_global_x128);
    let (is_valid) = Utils.is_gt(protocol_fee, 0);
    if (is_valid == TRUE) {
        let (protocol_fee_token1) = _protocol_fee_token1.read();
        _protocol_fee_token1.write(protocol_fee_token1 + protocol_fee);
        return ();
    }
    return ();
}

func _swap_cal_res{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    zero_for_one: felt, exact_input: felt, amount_specified: Uint256, state: SwapState
) -> (amount0: Uint256, amount1: Uint256) {
    if (zero_for_one == exact_input) {
        let (amount0: Uint256) = uint256_sub(amount_specified, state.amount_specified_remaining);
        let amount1: Uint256 = state.amount_caculated;
        return (amount0, amount1);
    }

    let amount0: Uint256 = state.amount_caculated;
    let (amount1: Uint256) = uint256_sub(amount_specified, state.amount_specified_remaining);
    return (amount0, amount1);
}

func _swap_transfer_token{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    zero_for_one: felt, 
    amount0: Uint256, 
    amount1: Uint256, 
    recipient: felt, 
    data: felt
) {
    alloc_locals;

    let (token0) = _token0.read();
    let (token1) = _token1.read();
    let (fee) = _fee.read();
    let (caller) = get_caller_address();
    if (zero_for_one == 1) {
        let (flag) = uint256_signed_nn(amount1);
        let (is_valid) = Utils.is_eq(flag, 0);
        let (abs_amount1: Uint256) = uint256_neg(amount1);
        _transfer_token_cond(is_valid, token1, recipient, abs_amount1);
        let (balance_before) = balance0();
        ISwapPoolCallback.swap_callback(contract_address=caller, token0=token0, token1=token1, fee=fee, amount0=amount0, amount1=amount1, data=data);
        let (balance_after: Uint256) = balance0();
        let (tmp: Uint256) = SafeUint256.add(balance_before, amount0);
        let (is_valid) = uint256_le(tmp, balance_after);
        with_attr error_message("transfer token0 failed") {
            assert is_valid = TRUE;
        }
        return ();
    }

    let (flag) = uint256_signed_nn(amount0);
    let (is_valid) = Utils.is_eq(flag, 0);
    let (abs_amount0: Uint256) = uint256_neg(amount0);
    _transfer_token_cond(is_valid, token0, recipient, abs_amount0);
    let (balance1_before) = balance1();
    ISwapPoolCallback.swap_callback(contract_address=caller, token0=token0, token1=token1, fee=fee, amount0=amount0, amount1=amount1, data=data);
    let (balance_after: Uint256) = balance1();
    let (tmp: Uint256) = SafeUint256.add(balance1_before, amount1);
    let (is_valid) = uint256_le(tmp, balance_after);
    with_attr error_message("transfer token1 failed") {
        assert is_valid = TRUE;
    }
    return ();
}

func _update_liquidity_cond{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    old_liqudity: felt,
    liquidity: felt
) {
    // write operation cost more gas than if?
    if (old_liqudity != liquidity) {
        _liquidity.write(liquidity);
        return ();
    }
    return ();
}

@view
func get_swap_results{
    syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr, bitwise_ptr: BitwiseBuiltin*
}(
    zero_for_one: felt, 
    amount_specified: Uint256,  // int256
    sqrt_price_limit_x96: Uint256, // uint160
) -> (amount0: Uint256, amount1: Uint256) {
    alloc_locals;

    Utils.assert_is_uint160(sqrt_price_limit_x96);

    // amount_specified != 0
    let (is_valid) = uint256_eq(amount_specified, Uint256(0, 0));
    with_attr error_message("Amount specified is zero") {
        assert is_valid = FALSE;
    }

    let (slot0: SlotState) = _slot0.read();
    let (fee_protocol) = _swap_1(slot0, sqrt_price_limit_x96, zero_for_one);

    let (liquidity_start) = _liquidity.read();

    let (exact_input) = uint256_signed_lt(Uint256(0, 0), amount_specified);

    if (zero_for_one == 1) {
        let (fee_growth: Uint256) = _fee_growth_global0_x128.read();
    } else {
        let (fee_growth: Uint256) = _fee_growth_global1_x128.read();
    }

    let init_state = SwapState(
        amount_specified_remaining=amount_specified,
        amount_caculated=Uint256(0, 0),
        sqrt_price_x96=slot0.sqrt_price_x96,
        tick=slot0.tick,
        fee_growth_global_x128=fee_growth,
        protocol_fee=0,
        liquidity=liquidity_start,
    );

    let (state: SwapState) = _compute_swap_step(
        init_state, fee_protocol, exact_input, zero_for_one, sqrt_price_limit_x96
    );

    let (amount0: Uint256, amount1: Uint256) = _swap_cal_res(
        zero_for_one, exact_input, amount_specified, state
    );

    return (amount0, amount1);
}

// @params amount_specified: int256
@external
func swap{
    syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr, bitwise_ptr: BitwiseBuiltin*
}(
    recipient: felt, 
    zero_for_one: felt, 
    amount_specified: Uint256,  // int256
    sqrt_price_limit_x96: Uint256, // uint160
    data: felt
) -> (amount0: Uint256, amount1: Uint256) {
    alloc_locals;

    uint256_check(amount_specified);
    Utils.assert_is_uint160(sqrt_price_limit_x96);

    // amount_specified != 0
    let (is_valid) = uint256_eq(amount_specified, Uint256(0, 0));
    with_attr error_message("Amount specified is zero") {
        assert is_valid = FALSE;
    }

    _lock();

    let (slot0: SlotState) = _slot0.read();
    let (fee_protocol) = _swap_1(slot0, sqrt_price_limit_x96, zero_for_one);

    let (liquidity_start) = _liquidity.read();

    let (exact_input) = uint256_signed_lt(Uint256(0, 0), amount_specified);

    if (zero_for_one == 1) {
        let (fee_growth: Uint256) = _fee_growth_global0_x128.read();
    } else {
        let (fee_growth: Uint256) = _fee_growth_global1_x128.read();
    }

    let init_state = SwapState(
        amount_specified_remaining=amount_specified,
        amount_caculated=Uint256(0, 0),
        sqrt_price_x96=slot0.sqrt_price_x96,
        tick=slot0.tick,
        fee_growth_global_x128=fee_growth,
        protocol_fee=0,
        liquidity=liquidity_start,
    );

    let (state: SwapState) = _compute_swap_step(
        init_state, fee_protocol, exact_input, zero_for_one, sqrt_price_limit_x96
    );

    _slot0.write(SlotState(
        sqrt_price_x96=state.sqrt_price_x96,
        tick=state.tick,
        ));

    _update_liquidity_cond(liquidity_start, state.liquidity);

    _swap_2(state.fee_growth_global_x128, state.protocol_fee, zero_for_one);

    let (amount0: Uint256, amount1: Uint256) = _swap_cal_res(
        zero_for_one, exact_input, amount_specified, state
    );

    // transfer and check balance
    _swap_transfer_token(zero_for_one, amount0, amount1, recipient, data);

    _unlock();

    Swap.emit(
        recipient,
        zero_for_one,
        amount_specified,
        amount0,
        amount1,
        state.sqrt_price_x96,
        state.liquidity,
        state.tick,
    );

    return (amount0, amount1);
}

func _check_ticks{range_check_ptr}(tick_lower: felt, tick_upper: felt) {
    let (is_valid) = Utils.is_lt_signed(tick_lower, tick_upper);
    with_attr error_message("tick lower is greater than tick upper") {
        assert is_valid = TRUE;
    }

    let is_valid = is_le(TickMath.MIN_TICK, tick_lower);
    with_attr error_message("tick is too low") {
        assert is_valid = TRUE;
    }

    let is_valid = is_le(tick_upper, TickMath.MAX_TICK);
    with_attr error_message("tick is too high") {
        assert is_valid = TRUE;
    }

    return ();
}

func _flip_tick{
    syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr, bitwise_ptr: BitwiseBuiltin*
}(flipped: felt, tick: felt, tick_spacing: felt) {
    alloc_locals;
    if (flipped == 1) {
        TickBitmap.flip_tick(tick, tick_spacing);
        return ();
    }
    return ();
}

func _clear_tick{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    clear: felt, tick: felt
) {
    if (clear == 1) {
        TickMgr.clear(tick);
        return ();
    }
    return ();
}

func _update_position_1{
    syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr, bitwise_ptr: BitwiseBuiltin*
}(
    tick_lower: felt,
    tick_upper: felt,
    liquidity_delta: felt,
    tick: felt,
    fee_growth_global0_x128: Uint256,
    fee_growth_global1_x128: Uint256,
) -> (flipped_lower: felt, flipped_upper: felt) {
    alloc_locals;

    if (liquidity_delta != 0) {
        let (max_liquidity_per_tick) = _max_liquidity_per_tick.read();
        let (flipped_lower: felt) = TickMgr.update(
            tick_lower,
            tick,
            liquidity_delta,
            fee_growth_global0_x128,
            fee_growth_global1_x128,
            0,
            max_liquidity_per_tick,
        );
        let (flipped_upper: felt) = TickMgr.update(
            tick_upper,
            tick,
            liquidity_delta,
            fee_growth_global0_x128,
            fee_growth_global1_x128,
            1,
            max_liquidity_per_tick,
        );

        let (tick_spacing) = _tick_spacing.read();
        _flip_tick(flipped_lower, tick_lower, tick_spacing);
        _flip_tick(flipped_upper, tick_upper, tick_spacing);
        return (flipped_lower, flipped_upper);
    }

    return (0, 0);
}

func _update_position{
    syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr, bitwise_ptr: BitwiseBuiltin*
}(owner: felt, tick_lower: felt, tick_upper: felt, liquidity_delta: felt, tick: felt) -> (
    positionInfo: PositionInfo
) {
    alloc_locals;

    let (position: PositionInfo) = PositionMgr.get(owner, tick_lower, tick_upper);

    let (fee_growth_global0_x128: Uint256) = _fee_growth_global0_x128.read();
    let (fee_growth_global1_x128: Uint256) = _fee_growth_global1_x128.read();

    let (flipped_lower, flipped_upper) = _update_position_1(
        tick_lower,
        tick_upper,
        liquidity_delta,
        tick,
        fee_growth_global0_x128,
        fee_growth_global1_x128,
    );

    let (
        fee_growth_inside0_x128: Uint256, fee_growth_inside1_x128: Uint256
    ) = TickMgr.get_fee_growth_inside(
        tick_lower, tick_upper, tick, fee_growth_global0_x128, fee_growth_global1_x128
    );

    let (new_position: PositionInfo) = PositionMgr.update_position(
        position,
        liquidity_delta,
        fee_growth_inside0_x128,
        fee_growth_inside1_x128,
        owner,
        tick_lower,
        tick_upper,
    );

    let (is_valid) = Utils.is_lt_signed(liquidity_delta, 0);
    if (is_valid == TRUE) {
        _clear_tick(flipped_lower, tick_lower);
        _clear_tick(flipped_upper, tick_upper);
        return (new_position,);
    }

    return (new_position,);
}

func _modify_position{
    syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr, bitwise_ptr: BitwiseBuiltin*
}(params: ModifyPositionParams) -> (position: PositionInfo, amount0: Uint256, amount1: Uint256) {
    alloc_locals;

    _check_ticks(params.tick_lower, params.tick_upper);

    let (slot0: SlotState) = _slot0.read();

    let (position: PositionInfo) = _update_position(
        params.owner, params.tick_lower, params.tick_upper, params.liquidity_delta, slot0.tick
    );

    if (params.liquidity_delta != 0) {
        let (sqrt_ratio0: Uint256) = TickMath.get_sqrt_ratio_at_tick(params.tick_lower);
        let (sqrt_ratio1: Uint256) = TickMath.get_sqrt_ratio_at_tick(params.tick_upper);

        let (is_valid) = Utils.is_lt_signed(slot0.tick, params.tick_lower);
        if (is_valid == TRUE) {
            let (amount0: Uint256) = SqrtPriceMath.get_amount0_delta2(
                sqrt_ratio0, sqrt_ratio1, params.liquidity_delta
            );
            return (position, amount0, Uint256(0, 0));
        }

        let (is_valid) = Utils.is_lt_signed(slot0.tick, params.tick_upper);
        if (is_valid == TRUE) {
            let (amount0: Uint256) = SqrtPriceMath.get_amount0_delta2(
                slot0.sqrt_price_x96, sqrt_ratio1, params.liquidity_delta
            );

            let (amount1: Uint256) = SqrtPriceMath.get_amount1_delta2(
                sqrt_ratio0, slot0.sqrt_price_x96, params.liquidity_delta
            );

            let (cur_liquidity) = _liquidity.read();
            let (liquidity) = Utils.u128_safe_add(cur_liquidity, params.liquidity_delta);
            _liquidity.write(liquidity);

            return (position, amount0, amount1);
        }

        let (amount1: Uint256) = SqrtPriceMath.get_amount1_delta2(
            sqrt_ratio0, sqrt_ratio1, params.liquidity_delta
        );
        return (position, Uint256(0, 0), amount1);
    }

    return (position, Uint256(0, 0), Uint256(0, 0));
}

func _add_liquidity_callback_1{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(flag: felt) -> (res: Uint256) {
    if (flag == 1) {
        let (balance: Uint256) = balance0();
        return (balance,);
    }
    return (Uint256(0, 0),);
}

func _add_liquidity_callback_2{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(flag: felt) -> (res: Uint256) {
    if (flag == 1) {
        let (balance: Uint256) = balance1();
        return (balance,);
    }
    return (Uint256(0, 0),);
}

func _add_liquidity_callback_3{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(flag: felt, balance0_before: Uint256, amount0: Uint256) {
    if (flag == 1) {
        let (balance0_after) = balance0();
        let (tmp: Uint256) = SafeUint256.add(balance0_before, amount0);
        let (is_valid) = uint256_le(tmp, balance0_after);
        with_attr error_message("token0 balance illegal") {
            assert is_valid = TRUE;
        }
        return ();
    }
    return ();
}

func _add_liquidity_callback{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    amount0: Uint256,
    amount1: Uint256,
    data: felt
) {
    alloc_locals;

    let (flag1) = uint256_lt(Uint256(0, 0), amount0);
    let (flag2) = uint256_lt(Uint256(0, 0), amount1);

    let (balance0_before: Uint256) = _add_liquidity_callback_1(flag1);
    let (balance1_before: Uint256) = _add_liquidity_callback_2(flag2);

    let (caller) = get_caller_address();
    let (token0) = _token0.read();
    let (token1) = _token1.read();
    let (fee) = _fee.read();
    ISwapPoolCallback.add_liquidity_callback(contract_address=caller, token0=token0, token1=token1, fee=fee, amount0=amount0, amount1=amount1, data=data);

    _add_liquidity_callback_3(flag1, balance0_before, amount0);

    if (flag2 == 1) {
        let (balance1_after) = balance1();
        let (tmp: Uint256) = SafeUint256.add(balance1_before, amount1);
        let (is_valid) = uint256_le(tmp, balance1_after);
        with_attr error_message("token1 balance illegal") {
            assert is_valid = TRUE;
        }
        return ();
    }

    return ();
}

@external
func add_liquidity{
    syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr, bitwise_ptr: BitwiseBuiltin*
}(
    recipient: felt, 
    tick_lower: felt, 
    tick_upper: felt, 
    amount: felt,  // uint128
    data: felt
) -> (amount0: Uint256, amount1: Uint256) {
    alloc_locals;

    _lock();

    Utils.assert_is_uint128(amount);

    let (_, amount0: Uint256, amount1: Uint256) = _modify_position(
        ModifyPositionParams(
        owner=recipient,
        tick_lower=tick_lower,
        tick_upper=tick_upper,
        liquidity_delta=amount
        ),
    );

    // transfer callback
    // check balance
    _add_liquidity_callback(amount0, amount1, data);

    _unlock();

    AddLiquidity.emit(recipient, tick_lower, tick_upper, amount, amount0, amount1);

    return (amount0, amount1);
}

func _remove_liquidity_1{
    syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr, bitwise_ptr: BitwiseBuiltin*
}(
    recipient: felt,
    tick_lower: felt,
    tick_upper: felt,
    position: PositionInfo,
    abs_amount0: Uint256,
    abs_amount1: Uint256,
) {
    alloc_locals;

    let (flag1) = uint256_lt(Uint256(0, 0), abs_amount0);
    let (flag2) = uint256_lt(Uint256(0, 0), abs_amount1);

    let (is_valid) = Utils.is_gt(flag1 + flag2, 0);
    // TODO: could abs_amount greater then 2 ** 128
    if (is_valid == TRUE) {
        let tokens_owed0 = position.tokens_owed0 + abs_amount0.low;
        let tokens_owed1 = position.tokens_owed1 + abs_amount1.low;
        // write new position
        let new_position = PositionInfo(
            liquidity=position.liquidity,
            fee_growth_inside0_x128=position.fee_growth_inside0_x128,
            fee_growth_inside1_x128=position.fee_growth_inside1_x128,
            tokens_owed0=tokens_owed0,
            tokens_owed1=tokens_owed1,
        );
        PositionMgr.set(recipient, tick_lower, tick_upper, new_position);

        return ();
    }
    return ();
}

@external
func remove_liquidity{
    syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr, bitwise_ptr: BitwiseBuiltin*
}(
    tick_lower: felt, 
    tick_upper: felt, 
    amount: felt
) -> (amount0: Uint256, amount1: Uint256) {
    alloc_locals;

    _lock();

    // 0 <= amount < 2 ** 128
    Utils.assert_is_uint128(amount);

    let (recipient) = get_caller_address();

    let (position: PositionInfo, amount0: Uint256, amount1: Uint256) = _modify_position(
        ModifyPositionParams(
        owner=recipient,
        tick_lower=tick_lower,
        tick_upper=tick_upper,
        liquidity_delta=-amount
        ),
    );

    let (abs_amount0: Uint256) = uint256_neg(amount0);
    let (abs_amount1: Uint256) = uint256_neg(amount1);

    _remove_liquidity_1(recipient, tick_lower, tick_upper, position, abs_amount0, abs_amount1);

    _unlock();
    RemoveLiquidity.emit(recipient, tick_lower, tick_upper, amount, abs_amount0, abs_amount1);

    return (abs_amount0, abs_amount1);
}

func _check_fee_protocol{range_check_ptr}(fee_protocol) {
    if (fee_protocol != 0) {
        // 4 <= fee_protocol <= 10
        assert_in_range(fee_protocol, 4, 11);
        return ();
    }
    return ();
}

@external
func set_fee_protocol{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    fee_protocol0: felt, fee_protocol1: felt
) {
    alloc_locals;

    Ownable.assert_only_owner();

    _lock();

    _check_fee_protocol(fee_protocol0);
    _check_fee_protocol(fee_protocol1);

    let fee_protocol = fee_protocol0 + fee_protocol1 * 16;
    _fee_protocol.write(fee_protocol);

    _unlock();

    SetFeeProtocol.emit(fee_protocol0, fee_protocol1, fee_protocol);
    return ();
}

func _collect_1{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    owner: felt,
    recipient: felt,
    tick_lower: felt,
    tick_upper: felt,
    amount0: felt,
    amount1: felt,
    position: PositionInfo,
) {
    alloc_locals;

    let (flag1) = Utils.is_gt(amount0, 0);
    let (tokens_owed0) = Utils.cond_assign(
        flag1, position.tokens_owed0 - amount0, position.tokens_owed0
    );

    let (flag2) = Utils.is_gt(amount1, 0);
    let (tokens_owed1) = Utils.cond_assign(
        flag2, position.tokens_owed1 - amount1, position.tokens_owed1
    );

    let flag = flag1 + flag2;
    let (is_valid) = Utils.is_gt(flag, 0);
    if (is_valid == TRUE) {
        let new_position = PositionInfo(
            liquidity=position.liquidity,
            fee_growth_inside0_x128=position.fee_growth_inside0_x128,
            fee_growth_inside1_x128=position.fee_growth_inside1_x128,
            tokens_owed0=tokens_owed0,
            tokens_owed1=tokens_owed1,
        );
        PositionMgr.set(owner, tick_lower, tick_upper, new_position);

        let (token0) = _token0.read();
        _transfer_token_cond(flag1, token0, recipient, Uint256(amount0, 0));

        let (token1) = _token1.read();
        _transfer_token_cond(flag2, token1, recipient, Uint256(amount1, 0));
        return ();
    }
    return ();
}

@external
func collect{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    recipient: felt,
    tick_lower: felt,
    tick_upper: felt,
    amount0_requested: felt, // uint128
    amount1_requested: felt, // uint128
) -> (amount0: felt, amount1: felt) {
    alloc_locals;

    _lock();

    Utils.assert_is_uint128(amount0_requested);
    Utils.assert_is_uint128(amount1_requested);

    let (caller_address) = get_caller_address();

    let (position: PositionInfo) = PositionMgr.get(caller_address, tick_lower, tick_upper);

    // TODO: why collect use uint128 for amount0 and amount1
    let (is_valid) = Utils.is_gt(amount0_requested, position.tokens_owed0);
    let (amount0) = Utils.cond_assign(is_valid, position.tokens_owed0, amount0_requested);

    let (is_valid) = Utils.is_gt(amount1_requested, position.tokens_owed1);
    let (amount1) = Utils.cond_assign(is_valid, position.tokens_owed1, amount1_requested);

    _collect_1(caller_address, recipient, tick_lower, tick_upper, amount0, amount1, position);

    _unlock();

    Collect.emit(
        caller_address, recipient, tick_lower, tick_upper, amount0_requested, amount1_requested, amount0, amount1
    );

    return (amount0, amount1);
}

func _collect_protocol_1{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    recipient: felt, amount: felt, protocol_fee_token: felt
) -> (res: felt) {
    alloc_locals;
    let (is_valid) = Utils.is_gt(amount, 0);
    if (is_valid == TRUE) {
        // ensure that the slot is not cleared, for gas savings
        let (token0) = _token0.read();
        if (protocol_fee_token == amount) {
            let new_amount = amount - 1;
            _protocol_fee_token0.write(protocol_fee_token - new_amount);
            _transfer_token(token0, recipient, Uint256(new_amount, 0));
            return (new_amount,);
        }
        _protocol_fee_token0.write(protocol_fee_token - amount);
        _transfer_token(token0, recipient, Uint256(amount, 0));
        return (amount,);
    }

    return (amount,);
}

func _collect_protocol_2{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    recipient: felt, amount: felt, protocol_fee_token: felt
) -> (res: felt) {
    alloc_locals;
    let (is_valid) = Utils.is_gt(amount, 0);
    if (is_valid == TRUE) {
        // ensure that the slot is not cleared, for gas savings
        let (token1) = _token1.read();
        if (protocol_fee_token == amount) {
            let new_amount = amount - 1;
            _protocol_fee_token1.write(protocol_fee_token - new_amount);
            _transfer_token(token1, recipient, Uint256(new_amount, 0));
            return (new_amount,);
        }
        _protocol_fee_token1.write(protocol_fee_token - amount);
        _transfer_token(token1, recipient, Uint256(amount, 0));
        return (amount,);
    }

    return (amount,);
}

@external
func collect_protocol{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    recipient: felt, 
    amount0_requested: felt, // uint128
    amount1_requested: felt // uint128
) -> (amount0: felt, amount1: felt) {
    alloc_locals;


    _lock();

    Utils.assert_is_uint128(amount0_requested);
    Utils.assert_is_uint128(amount1_requested);

    Ownable.assert_only_owner();

    let (protocol_fee_token0) = _protocol_fee_token0.read();
    let (is_valid) = Utils.is_gt(amount0_requested, protocol_fee_token0);
    let (amount0) = Utils.cond_assign(is_valid, protocol_fee_token0, amount0_requested);

    let (protocol_fee_token1) = _protocol_fee_token1.read();
    let (is_valid) = Utils.is_gt(amount1_requested, protocol_fee_token1);
    let (amount1) = Utils.cond_assign(is_valid, protocol_fee_token1, amount1_requested);

    let (new_amount0) = _collect_protocol_1(recipient, amount0, protocol_fee_token0);
    let (new_amount1) = _collect_protocol_2(recipient, amount1, protocol_fee_token1);

    _unlock();
    CollectProtocol.emit(recipient, amount0_requested, amount1_requested, new_amount0, new_amount1);

    return (new_amount0, new_amount1);
}
