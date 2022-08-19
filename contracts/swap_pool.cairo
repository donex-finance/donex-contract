%lang starknet

from starkware.cairo.common.cairo_builtins import (HashBuiltin, BitwiseBuiltin)
from starkware.cairo.common.uint256 import (Uint256, uint256_mul, uint256_shr, uint256_shl, uint256_lt, uint256_le, uint256_add, uint256_unsigned_div_rem, uint256_or, uint256_sub, uint256_and, uint256_eq, uint256_signed_lt, uint256_neg, uint256_signed_nn)
from starkware.cairo.common.bool import (FALSE, TRUE)
from starkware.cairo.common.math import unsigned_div_rem
from starkware.cairo.common.math_cmp import is_le

from contracts.tick_mgr import (TickMgr, TickInfo)
from contracts.tick_bitmap import TickBitmap
from contracts.position_mgr import (PositionMgr, PositionInfo)
from contracts.swapmath import SwapMath
from contracts.tickmath import TickMath
from contracts.math_utils import Utils
from contracts.fullmath import FullMath
from contracts.sqrt_price_math import SqrtPriceMath

struct SlotState:
    member sqrt_price_x96: Uint256
    member tick: felt
end

struct SwapCache:
    member liquidity_start: felt
    member fee_protocol: felt
end

struct SwapState:
    member amount_specified_remaining: Uint256
    member amount_caculated: Uint256
    member sqrt_price_x96: Uint256
    member tick: felt 
    member fee_growth_global_x128: Uint256
    member protocol_fee: felt
    member liquidity: felt
end

struct StepComputations: 
    member sqrt_price_start_x96: Uint256
    member tick_next: felt
    member initialized: felt
    member sqrt_price_next_x96: Uint256
    member amount_in: Uint256
    member amount_out: Uint256
    member fee_amount: Uint256
end

struct ModifyPositionParams:
    # the address that owns the position
    member owner: felt
    # the lower and upper tick of the position
    member tick_lower: felt
    member tick_upper: felt
    # any change in liquidity
    member liquidity_delta: felt
end

@storage_var
func _fee_protocol() -> (fee_protocol: felt):
end

@storage_var
func _slot_unlocked() -> (unlocked: felt):
end

@storage_var
func _slot0() -> (slot0: SlotState):
end

@storage_var
func _protocol_fee_token0() -> (fee: Uint256):
end

@storage_var
func _protocol_fee_token1() -> (fee: Uint256):
end

@storage_var
func _liquidity() -> (liquidity: felt):
end

@storage_var
func _fee_growth_global0_x128() -> (fee_growth_global_0x128: Uint256):
end

@storage_var
func _fee_growth_global1_x128() -> (fee_growth_global_1x128: Uint256):
end

@storage_var
func _tick_spacing() -> (tick_spacing: felt):
end

@storage_var
func _fee() -> (fee: felt):
end

@storage_var
func _max_liquidity_per_tick() -> (max_liquidity_per_tick: felt):
end

@constructor
func constructor{
        syscall_ptr: felt*,
        pedersen_ptr: HashBuiltin*,
        range_check_ptr
    }(
        tick_spacing: felt, 
        fee: felt
    ):
    alloc_locals

    _tick_spacing.write(tick_spacing)
    _fee.write(fee)

    let (max_liquidity_per_tick) = TickMgr.get_max_liquidity_per_tick(tick_spacing)
    _max_liquidity_per_tick.write(max_liquidity_per_tick)
    return ()
end

@view
func get_cur_slot{
        syscall_ptr: felt*,
        pedersen_ptr: HashBuiltin*,
        range_check_ptr
    }() -> (slot: SlotState):

    let (slot: SlotState) = _slot0.read()
    return (slot)
end

@view
func get_max_liquidity_per_tick{
        syscall_ptr: felt*,
        pedersen_ptr: HashBuiltin*,
        range_check_ptr
    }() -> (liquidity: felt):
    let (liquidity: felt) = _max_liquidity_per_tick.read()
    return (liquidity)
end

@view 
func get_tick{
        syscall_ptr: felt*,
        pedersen_ptr: HashBuiltin*,
        range_check_ptr
    }(tick: felt) -> (tick: TickInfo):
    let (tick_info: TickInfo) = TickMgr.get_tick(tick)
    return (tick_info)
end

@external
func initialize{
        syscall_ptr: felt*,
        pedersen_ptr: HashBuiltin*,
        range_check_ptr,
        bitwise_ptr: BitwiseBuiltin*
    }(sqrt_price_x96: Uint256):
    alloc_locals

    let (slot0) = _slot0.read()
    let (is_valid) = uint256_eq(slot0.sqrt_price_x96, Uint256(0, 0))
    with_attr error_message("initialize more than once"):
        assert is_valid = 1
    end

    let (tick) = TickMath.get_tick_at_sqrt_ratio(sqrt_price_x96)

    let new_slot0: SlotState = SlotState(
        sqrt_price_x96 = sqrt_price_x96,
        tick = tick
    )
    _slot0.write(new_slot0)

    _unlock()

    return ()
end

func _compute_swap_step_1{
        range_check_ptr
    }(
        exact_input: felt, 
        state: SwapState,
        amount_in: Uint256,
        amount_out: Uint256,
        fee_amount: Uint256
    ) -> (amount_specified_remaining: Uint256, amount_caculated: Uint256):
    if exact_input == 1:
        let (tmp: Uint256, _) = uint256_add(amount_in, fee_amount)
        let (amount_specified_remaining: Uint256) = uint256_sub(state.amount_specified_remaining, tmp)

        let (amount_caculated: Uint256) = uint256_sub(state.amount_caculated, amount_out)

        return (amount_specified_remaining, amount_caculated)
    end

    let (amount_specified_remaining: Uint256, _) = uint256_add(state.amount_specified_remaining, amount_out)

    let (tmp: Uint256, _) = uint256_add(amount_in, fee_amount)
    let (amount_caculated: Uint256, _) = uint256_add(state.amount_caculated, tmp)

    return (amount_specified_remaining, amount_caculated)
end

func _compute_swap_step_2{
        range_check_ptr
    }(cache: SwapCache, state: SwapState, fee_amount: Uint256) -> (fee_amount: Uint256, protocol_fee: felt):
    let (is_valid) = Utils.is_gt(cache.fee_protocol, 0)
    if is_valid == 1:
        let (delta: Uint256, _) = uint256_unsigned_div_rem(fee_amount, Uint256(cache.fee_protocol, 0))
        let (fee_amount: Uint256) = uint256_sub(fee_amount, delta)

        #TODO: overflow?
        let (tmp: Uint256, _) = uint256_add(Uint256(state.protocol_fee, 0), delta)
        let protocol_fee = tmp.low
        return (fee_amount, protocol_fee)
    end
    return (fee_amount, state.protocol_fee)
end

func _compute_swap_step_3{
        range_check_ptr,
        bitwise_ptr: BitwiseBuiltin*
    }(state: SwapState, fee_amount: Uint256) -> (fee_growth_global_x128: Uint256):
    let (is_valid) = Utils.is_gt(state.liquidity, 0)
    if is_valid == 1:
        let (tmp: Uint256, _) = FullMath.uint256_mul_div(fee_amount, Uint256(0, 1), Uint256(state.liquidity, 0))
        let (fee_growth_global_x128: Uint256, _) = uint256_add(state.fee_growth_global_x128, tmp)
        return (fee_growth_global_x128)
    end
    return (state.fee_growth_global_x128)
end

func _compute_swap_step_4_1{
        syscall_ptr: felt*,
        pedersen_ptr: HashBuiltin*,
        range_check_ptr
    }(zero_for_one: felt, tick_next: felt, state_fee_growth_global_x128: Uint256) -> (liquidity_net: felt):
    if zero_for_one == 1:
        let (fee_growth_global1_x128: Uint256) = _fee_growth_global1_x128.read()
        let (tmp_felt) = TickMgr.cross(tick_next, state_fee_growth_global_x128, fee_growth_global1_x128)
        tempvar liquidity_net = -tmp_felt
        return (liquidity_net)
    end

    let (fee_growth_global0_x128: Uint256) = _fee_growth_global0_x128.read()
    let (liquidity_net) = TickMgr.cross(tick_next, fee_growth_global0_x128, state_fee_growth_global_x128)
    return (liquidity_net)
end

func _compute_swap_step_4{
        syscall_ptr: felt*,
        pedersen_ptr: HashBuiltin*,
        range_check_ptr,
        bitwise_ptr: BitwiseBuiltin*
    }(
        state: SwapState,
        sqrt_price_start_x96: Uint256,
        sqrt_price_next_x96: Uint256,
        state_fee_growth_global_x128: Uint256,
        tick_next: felt,
        zero_for_one: felt,
        initialized: felt,
    ) -> (liquidity: felt, tick: felt):
    alloc_locals

    let (is_valid) = uint256_eq(state.sqrt_price_x96, sqrt_price_next_x96)
    if is_valid == 1:
        let (tick) = Utils.cond_assign(zero_for_one, tick_next - 1, tick_next)

        if initialized == 1:
            let (liquidity_net) = _compute_swap_step_4_1(zero_for_one, tick_next, state_fee_growth_global_x128)

            let (liquidity) = Utils.u128_safe_add(state.liquidity, liquidity_net)

            return (liquidity, tick)
        end

        return (state.liquidity, tick)
    end

    let (is_valid) = uint256_eq(state.sqrt_price_x96, sqrt_price_start_x96)
    if is_valid == 0:
        let (tick) = TickMath.get_tick_at_sqrt_ratio(state.sqrt_price_x96)
        return (state.liquidity, tick)
    end

    return (state.liquidity, state.tick)
end

func _compute_swap_step{
        syscall_ptr: felt*,
        pedersen_ptr: HashBuiltin*,
        range_check_ptr,
        bitwise_ptr: BitwiseBuiltin*
    }(
        state: SwapState, 
        cache: SwapCache, 
        exact_input: felt, 
        zero_for_one: felt, 
        sqrt_price_limit_x96: Uint256
    ) -> (state: SwapState):
    alloc_locals

    let (flag1) = uint256_eq(state.amount_specified_remaining, Uint256(0, 0))
    let (flag2) = uint256_eq(state.sqrt_price_x96, sqrt_price_limit_x96)

    if flag1 + flag2 == 0:
        return (state)
    end

    let (tick_spacing) = _tick_spacing.read()

    let (tick_next, initialized) = TickBitmap.next_valid_tick_within_one_word(state.tick, tick_spacing, zero_for_one)

    let sqrt_price_start_x96: Uint256 = state.sqrt_price_x96

    let (is_valid) = Utils.is_lt(tick_next, TickMath.MIN_TICK) 
    let (tick_next) = Utils.cond_assign(is_valid, TickMath.MIN_TICK, tick_next)

    let (is_valid) = Utils.is_lt(TickMath.MAX_TICK, tick_next) 
    let (tick_next) = Utils.cond_assign(is_valid, TickMath.MAX_TICK, tick_next)

    let (sqrt_price_next_x96: Uint256) = TickMath.get_sqrt_ratio_at_tick(tick_next)

    if zero_for_one == 1:
        let (flag) = uint256_lt(sqrt_price_next_x96, sqrt_price_limit_x96)
    else:
        let (flag) = uint256_lt(sqrt_price_limit_x96, sqrt_price_next_x96)
    end

    let (sqrt_price_target_x96: Uint256) = Utils.cond_assign_uint256(flag, sqrt_price_limit_x96, sqrt_price_next_x96)

    let (fee) = _fee.read()
    let (state_sqrt_price_x96: Uint256, amount_in: Uint256, amount_out: Uint256, fee_amount: Uint256) = SwapMath.compute_swap_step(
        state.sqrt_price_x96,
        sqrt_price_target_x96,
        state.liquidity,
        state.amount_specified_remaining,
        fee,
    )

    let (state_amount_specified_remaining: Uint256, state_amount_caculated: Uint256) = _compute_swap_step_1(
        exact_input,
        state,
        amount_in,
        amount_out,
        fee_amount,
    )

    let (fee_amount: Uint256, state_protocol_fee) = _compute_swap_step_2(cache, state, fee_amount)
    
    let (state_fee_growth_global_x128: Uint256) = _compute_swap_step_3(state, fee_amount)

    let (state_liquidity, state_tick) = _compute_swap_step_4(state, sqrt_price_start_x96, sqrt_price_next_x96, state_fee_growth_global_x128, tick_next, zero_for_one, initialized)

    let new_state: SwapState = SwapState(
        amount_specified_remaining = state_amount_specified_remaining,
        amount_caculated = state_amount_caculated,
        sqrt_price_x96 = state_sqrt_price_x96,
        tick = state_tick,
        fee_growth_global_x128 = state_fee_growth_global_x128,
        protocol_fee = state_protocol_fee,
        liquidity = state_liquidity
    )

    return _compute_swap_step(new_state, cache, exact_input, zero_for_one, sqrt_price_limit_x96)
end

func _swap_1{
        syscall_ptr: felt*,
        pedersen_ptr: HashBuiltin*,
        range_check_ptr
    }(slot0: SlotState, sqrt_price_limit_x96: Uint256, zero_for_one) -> (res: felt):
    alloc_locals

    let (fee_protocol) = _fee_protocol.read()
    if zero_for_one == 1:
        let (is_valid) = uint256_lt(sqrt_price_limit_x96, slot0.sqrt_price_x96)
        assert is_valid = 1

        let (is_valid) = uint256_lt(Uint256(TickMath.MIN_SQRT_RATIO, 0), sqrt_price_limit_x96)
        assert is_valid = 1

        let (_, res) = unsigned_div_rem(fee_protocol, 16)

        return (res)
    end

    let (is_valid) = uint256_lt(slot0.sqrt_price_x96, sqrt_price_limit_x96)
    assert is_valid = 1

    let (is_valid) = uint256_lt(sqrt_price_limit_x96, Uint256(TickMath.MAX_SQRT_RATIO_LOW, TickMath.MAX_SQRT_RATIO_HIGH))
    assert is_valid = 1

    let (res, _) = unsigned_div_rem(fee_protocol, 16)
    return (res)
end

func _swap_2{
        syscall_ptr: felt*,
        pedersen_ptr: HashBuiltin*,
        range_check_ptr
    }(state: SwapState, zero_for_one: felt):
    alloc_locals
    if zero_for_one == 1:
        _fee_growth_global0_x128.write(state.fee_growth_global_x128)

        let (is_valid) = Utils.is_gt(state.protocol_fee, 0)
        if is_valid == 1:
            let (protocol_fee_token0: Uint256) = _protocol_fee_token0.read()
            let (tmp: Uint256, _) = uint256_add(protocol_fee_token0, Uint256(state.protocol_fee, 0))
            _protocol_fee_token0.write(tmp)
            return ()
        end
        return ()
    end

    _fee_growth_global1_x128.write(state.fee_growth_global_x128)
    let (is_valid) = Utils.is_gt(state.protocol_fee, 0)
    if is_valid == 1:
        let (protocol_fee_token1: Uint256) = _protocol_fee_token1.read()
        let (tmp: Uint256, _) = uint256_add(protocol_fee_token1, Uint256(state.protocol_fee, 0))
        _protocol_fee_token1.write(tmp)
        return ()
    end
    return ()
end

func _lock{
        syscall_ptr: felt*,
        pedersen_ptr: HashBuiltin*,
        range_check_ptr,
    }():
    let (slot_unlocked) = _slot_unlocked.read()
    with_attr error_message("swap is locked"):
        assert slot_unlocked = 1
    end
    _slot_unlocked.write(0)
    return ()
end

func _unlock{
        syscall_ptr: felt*,
        pedersen_ptr: HashBuiltin*,
        range_check_ptr,
    }():
    _slot_unlocked.write(1)
    return ()
end

@external
func swap{
        syscall_ptr: felt*,
        pedersen_ptr: HashBuiltin*,
        range_check_ptr,
        bitwise_ptr: BitwiseBuiltin*
    }(
        recipient: felt,
        zero_for_one: felt,
        amount_specified: Uint256,
        sqrt_price_limit_x96: Uint256,
    ) -> (amount0: Uint256, amount1: Uint256):
    alloc_locals

    let (is_valid) = uint256_eq(amount_specified, Uint256(0, 0))
    assert is_valid = 1

    #TODO: prevent reentry?
    _lock()

    let (slot0: SlotState) = _slot0.read()
    let (fee_protocol) = _swap_1(slot0, sqrt_price_limit_x96, zero_for_one)

    let (liquidity) = _liquidity.read()
    let cache = SwapCache(
        liquidity_start = liquidity,
        fee_protocol = fee_protocol
    )

    let (exact_input) = uint256_lt(Uint256(0, 0), amount_specified)

    if zero_for_one == 1:
        let (fee_growth: Uint256) = _fee_growth_global0_x128.read()
    else:
        let (fee_growth: Uint256) = _fee_growth_global1_x128.read()
    end

    let init_state = SwapState(
        amount_specified_remaining = amount_specified,
        amount_caculated = Uint256(0, 0),
        sqrt_price_x96 = slot0.sqrt_price_x96,
        tick = slot0.tick,
        fee_growth_global_x128 = fee_growth,
        protocol_fee = 0,
        liquidity = cache.liquidity_start
    )

    let (state: SwapState) = _compute_swap_step(init_state, cache, exact_input, zero_for_one, sqrt_price_limit_x96)

    _slot0.write(SlotState(
        sqrt_price_x96 = state.sqrt_price_x96,
        tick = state.tick,
    ))

    # TODO: use if to save gas? 
    #if cache.liquidity_start != state.liquidity:
    #    _liquidity.write(state.liquidity)
    #end
    _liquidity.write(state.liquidity)

    _swap_2(state, zero_for_one)

    _unlock()

    if zero_for_one == exact_input:
        let (amount0: Uint256) = uint256_sub(amount_specified, state.amount_specified_remaining)
        let amount1: Uint256 = state.amount_caculated
        return (amount0, amount1)
    end

    let amount0: Uint256 = state.amount_caculated
    let (amount1: Uint256) = uint256_sub(amount_specified, state.amount_specified_remaining)

    return (amount0, amount1)
end

func _check_ticks{
        range_check_ptr
    }(
        tick_lower: felt,
        tick_upper: felt
    ):
    let (is_valid) = Utils.is_lt(tick_lower, tick_upper)
    with_attr error_message("tick lower is greater than tick upper"):
        assert is_valid = 1
    end

    let (is_valid) = is_le(TickMath.MIN_TICK, tick_lower)
    with_attr error_message("tick is too low"):
        assert is_valid = 1
    end

    let (is_valid) = is_le(tick_upper, TickMath.MAX_TICK)
    with_attr error_message("tick is too high"):
        assert is_valid = 1
    end

    return ()
end

func _flip_tick{
        syscall_ptr: felt*,
        pedersen_ptr: HashBuiltin*,
        range_check_ptr,
        bitwise_ptr: BitwiseBuiltin*
    }(
        flipped: felt,
        tick: felt,
        tick_spacing: felt
    ):
    alloc_locals
    if flipped == 1:
        TickBitmap.flip_tick(tick, tick_spacing)
        return ()
    end
    return ()
end

func _clear_tick{
        syscall_ptr: felt*,
        pedersen_ptr: HashBuiltin*,
        range_check_ptr,
    }(clear: felt, tick: felt):
    if clear == 1:
        TickMgr.clear(tick)
        return ()
    end
    return ()
end

func _update_position_1{
        syscall_ptr: felt*,
        pedersen_ptr: HashBuiltin*,
        range_check_ptr,
        bitwise_ptr: BitwiseBuiltin*
    }(
        tick_lower: felt,
        tick_upper: felt,
        liquidity_delta: felt,
        tick: felt,
        fee_growth_global0_x128: Uint256,
        fee_growth_global1_x128: Uint256
    ) -> (flipped_lower: felt, flipped_upper: felt):
    alloc_locals

    if liquidity_delta != 0:
        let (max_liquidity_per_tick) = _max_liquidity_per_tick.read()
        let (flipped_lower: felt) = TickMgr.update(tick_lower, tick, liquidity_delta, fee_growth_global0_x128, fee_growth_global1_x128, 0, max_liquidity_per_tick)
        let (flipped_upper: felt) = TickMgr.update(tick_upper, tick, liquidity_delta, fee_growth_global0_x128, fee_growth_global1_x128, 1, max_liquidity_per_tick)

        let (tick_spacing) = _tick_spacing.read()
        _flip_tick(flipped_lower, tick_lower, tick_spacing)
        _flip_tick(flipped_upper, tick_upper, tick_spacing)
        return (flipped_lower, flipped_upper)
    end

    return (0, 0)
end

func _update_position{
        syscall_ptr: felt*,
        pedersen_ptr: HashBuiltin*,
        range_check_ptr,
        bitwise_ptr: BitwiseBuiltin*
    }(
        owner: felt,
        tick_lower: felt,
        tick_upper: felt,
        liquidity_delta: felt,
        tick: felt
    ) -> (positionInfo: PositionInfo):

    alloc_locals

    let (position: PositionInfo) = PositionMgr.get(owner, tick_lower, tick_upper)

    let (fee_growth_global0_x128: Uint256) = _fee_growth_global0_x128.read()
    let (fee_growth_global1_x128: Uint256) = _fee_growth_global1_x128.read()

    let (flipped_lower, flipped_upper) = _update_position_1(tick_lower, tick_upper, liquidity_delta, tick, fee_growth_global0_x128, fee_growth_global1_x128)

    let (fee_growth_inside0_x128: Uint256, fee_growth_inside1_x128: Uint256) = TickMgr.get_fee_growth_inside(tick_lower, tick_upper, tick, fee_growth_global0_x128, fee_growth_global1_x128)

    let (new_position: PositionInfo) = PositionMgr.update_position(position, liquidity_delta, fee_growth_inside0_x128, fee_growth_inside1_x128, owner, tick_lower, tick_upper)

    let (is_valid) = Utils.is_lt(liquidity_delta, 0)
    if is_valid == 1:
        _clear_tick(flipped_lower, tick_lower)
        _clear_tick(flipped_upper, tick_upper)
        return (new_position)
    end

    return (new_position)
end

func _modify_position{
        syscall_ptr: felt*,
        pedersen_ptr: HashBuiltin*,
        range_check_ptr,
        bitwise_ptr: BitwiseBuiltin*
    }(params: ModifyPositionParams) -> (position: PositionInfo, amount0: Uint256, amount1: Uint256):
    alloc_locals

    _check_ticks(params.tick_lower, params.tick_upper)

    let (slot0: SlotState) = _slot0.read()

    let (position: PositionInfo) = _update_position(params.owner, params.tick_lower, params.tick_upper, params.liquidity_delta, slot0.tick)

    if params.liquidity_delta != 0:
        let (sqrt_ratio0: Uint256) = TickMath.get_sqrt_ratio_at_tick(params.tick_lower)
        let (sqrt_ratio1: Uint256) = TickMath.get_sqrt_ratio_at_tick(params.tick_upper)

        let (is_valid) = Utils.is_lt(slot0.tick, params.tick_lower)
        if is_valid == 1:
            let (amount0: Uint256) = SqrtPriceMath.get_amount0_delta2(sqrt_ratio0, sqrt_ratio1, params.liquidity_delta)
            return (position, amount0, Uint256(0, 0))
        end

        let (is_valid) = Utils.is_lt(slot0.tick, params.tick_upper)
        if is_valid == 1:
            let (amount0: Uint256) = SqrtPriceMath.get_amount0_delta2(slot0.sqrt_price_x96, sqrt_ratio1, params.liquidity_delta)

            let (amount1: Uint256) = SqrtPriceMath.get_amount1_delta2(sqrt_ratio0, slot0.sqrt_price_x96, params.liquidity_delta)

            let (cur_liquidity) = _liquidity.read()
            let (liquidity) = Utils.u128_safe_add(cur_liquidity, params.liquidity_delta)
            _liquidity.write(liquidity)

            return (position, amount0, amount1)
        end

        let (amount1: Uint256) = SqrtPriceMath.get_amount1_delta2(sqrt_ratio0, sqrt_ratio1, params.liquidity_delta)
        return (position, Uint256(0, 0), amount1)
    end

    return (position, Uint256(0, 0), Uint256(0, 0))
end

@external
func add_liquidity{
        syscall_ptr: felt*,
        pedersen_ptr: HashBuiltin*,
        range_check_ptr,
        bitwise_ptr: BitwiseBuiltin*
    }(
        recipient: felt,
        tick_lower: felt,
        tick_upper: felt,
        amount: felt
    ) -> (amount0: Uint256, amount1: Uint256):
    alloc_locals

    _lock()

    let (is_valid) = Utils.is_gt(amount, 0)
    assert is_valid = 1

    let (_, amount0: Uint256, amount1: Uint256) = _modify_position(
        ModifyPositionParams(
            owner = recipient,
            tick_lower = tick_lower,
            tick_upper = tick_upper,
            liquidity_delta = amount
        )
    )

    #TODO: transfer

    #TODO: data
    #TODO: callback for contract

    _unlock()

    return (amount0, amount1)
end

@external
func remove_liquidity{
        syscall_ptr: felt*,
        pedersen_ptr: HashBuiltin*,
        range_check_ptr,
        bitwise_ptr: BitwiseBuiltin*
    }(
        recipient: felt,
        tick_lower: felt,
        tick_upper: felt,
        amount: felt,
    ) -> (amount0: Uint256, amount1: Uint256):
    alloc_locals

    _lock()

    let (position: PositionInfo, amount0: Uint256, amount1: Uint256) = _modify_position(
        ModifyPositionParams(
            owner = recipient,
            tick_lower = tick_lower,
            tick_upper = tick_upper,
            liquidity_delta = -amount
        )
    )

    let (abs_amount0: Uint256) = uint256_neg(amount0)
    let (abs_amount1: Uint256) = uint256_neg(amount1)

    let (flag1) = uint256_lt(Uint256(0, 0), abs_amount0)
    let (flag2) = uint256_lt(Uint256(0, 0), abs_amount1)

    let (is_valid) = Utils.is_gt(flag1 + flag2, 0)
    # could abs_amount greater then 2 ** 128
    if is_valid == 1:
        let tokens_owed0 = position.tokens_owed0 + abs_amount0.low
        let tokens_owed1 = position.tokens_owed1 + abs_amount1.low
        # write new position
        let new_position = PositionInfo(
            liquidity = position.liquidity,
            fee_growth_inside0_x128 = position.fee_growth_inside0_x128,
            fee_growth_inside1_x128 = position.fee_growth_inside1_x128,
            tokens_owed0 = tokens_owed0,
            tokens_owed1 = tokens_owed1,
        )
        PositionMgr.set(recipient, tick_lower, tick_upper, new_position)
        return (abs_amount0, abs_amount1)
    end

    _unlock()

    return (abs_amount0, abs_amount1)
end

@external
func setFeeProtocol{
        syscall_ptr: felt*,
        pedersen_ptr: HashBuiltin*,
        range_check_ptr
    }(
        fee_protocol0: felt,
        fee_protocol1: felt
    ):
    #TODO: lock and onlyOwner
    let fee_protocol = fee_protocol0 + fee_protocol1 * 16
    _fee_protocol.write(fee_protocol)

    return ()
end

@external
func collect{
        syscall_ptr: felt*,
        pedersen_ptr: HashBuiltin*,
        range_check_ptr
    }(
        recipient: felt,
        tick_lower: felt,
        tick_upper: felt,
        amount0_requested: felt,
        amount1_requested: felt
    ) -> (amount0: felt, amount1: felt):
    alloc_locals

    let (position: PositionInfo) = PositionMgr.get(recipient, tick_lower, tick_upper)

    let (is_valid) = Utils.is_gt(amount0_requested, position.tokens_owed0)
    let (amount0) = Utils.cond_assign(is_valid, position.tokens_owed0, amount0_requested)

    let (is_valid) = Utils.is_gt(amount1_requested, position.tokens_owed1)
    let (amount1) = Utils.cond_assign(is_valid, position.tokens_owed1, amount1_requested)

    let (is_valid) = Utils.is_gt(amount0, 0)
    let (tokens_owed0) = Utils.cond_assign(is_valid, position.tokens_owed0 - amount0, position.tokens_owed0)

    let (is_valid) = Utils.is_gt(amount1, 0)
    let (tokens_owed1) = Utils.cond_assign(is_valid, position.tokens_owed1 - amount1, position.tokens_owed1) 

    return (amount0, amount1)
end