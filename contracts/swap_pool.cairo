%lang starknet

from starkware.cairo.common.cairo_builtins import (HashBuiltin, BitwiseBuiltin)
from starkware.cairo.common.uint256 import (Uint256, uint256_mul, uint256_shr, uint256_shl, uint256_lt, uint256_le, uint256_add, uint256_unsigned_div_rem, uint256_signed_div_rem, uint256_or, uint256_sub, uint256_and, uint256_eq, uint256_signed_lt, uint256_neg, uint256_signed_nn)
from starkware.cairo.common.bool import (FALSE, TRUE)
from starkware.cairo.common.math import unsigned_div_rem

from contracts.tick_mgr import TickMgr 
from contracts.tick_bitmap import TickBitmap
from contracts.position_mgr import PositionMgr
from contracts.swapmath import SwapMath
from contracts.tickmath import TickMath
from contracts.math_utils import Utils
from contracts.fullmath import FullMath

struct SlotState:
    member sqrt_price_x96: Uint256
    member tick: felt
    member fee_protocol: felt
    member unlocked: felt
end

struct SwapCache:
    member fee_protocol: felt
    member liquidity_start: felt
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
func _slot0() -> (slot0: SlotState):
end

@storage_var
func _protocol_fee_token0() -> (fee: Uint256):
end

@storage_var
func _protocol_fee_token1() -> (fee: Uint256):
end

@storage_var
func _liquidity() -> (liquidity: Uint256):
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
func _max_liquidity_per_tick() -> (max_liquidity_per_tick: Uint256):
end

@constructor
func constructor{
        syscall_ptr: felt*,
        pedersen_ptr: HashBuiltin*,
        range_check_ptr
    }(
        tick_spaceing: felt, 
        fee: felt
    ):

    _tick_spacing.write(tick_spaceing)
    _fee.write(fee)
    return ()
end

@external
func initialized{
        syscall_ptr: felt*,
        pedersen_ptr: HashBuiltin*,
        range_check_ptr
    }(sqrt_price_x96: Uint256):

    let (slot0) = _slot0.read()
    let (is_valid) = uint256_eq(slot0.sqrt_price_x96, Uint256(0, 0))
    with_attr error_message("initialized more than once"):
        assert is_valid = 1
    end

    let (tick) = TickMath.get_tick_at_sqrt_ratio(sqrt_price_x96)

    slot0.sqrt_price_x96 = sqrt_price_x96
    slot0.tick = tick
    slot0.fee_protocol = 0
    slot0.unlocked = 1

    _slot0.write(slot0)

    return ()
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
    ) -> (state: SwapState, cache: SwapCache):

    let (flag1) = uint256_eq(state.amount_specified_remaining, Uint256(0, 0))
    let (flag2) = uint256_eq(state.sqrt_price_x96, sqrt_price_limit_x96)

    if flag1 + flag2 == 0:
        return (state, cache)
    end

    let (tick_next, initialized) = TickBitmap.next_valid_tick_within_one_word(state.tick, _tick_spacing.read()[0], zero_for_one)

    let step = StepComputations(
        sqrt_price_start_x96 = state.sqrt_price_x96,
        tick_next = tick_next,
        initialized = initialized,
        sqrt_price_next_x96 = Uint256(0, 0),
        amount_in = Uint256(0, 0),
        amount_out = Uint256(0, 0),
        fee_amount = Uint256(0, 0)
    )

    let (is_valid) = Utils.is_lt(step.tick_nex, TickMath.MIN_TICK) 
    if is_valid == 1:
        step.tick_next = TickMath.MIN_TICK
    end

    let (is_valid) = Utils.is_lt(TickMath.MAX_TICK, step.tick_next) 
    if is_valid == 1:
        step.tick_nex = TickMath.MAX_TICK
    end

    let (res: Uint256) = TickMath.get_sqrt_ratio_at_tick(step.tick_next)
    step.sqrt_price_next_x96 = res

    if zero_for_one == 1:
        let (flag) = uint256_lt(step.sqrt_price_next_x96, sqrt_price_limit_x96)
    else:
        let (flag) = uint256_lt(sqrt_price_limit_x96, step.sqrt_price_next_x96)
    end

    if flag == 1:
        tempvar sqrt_price_target_x96 = sqrt_price_limit_x96
    else:
        tempvar sqrt_price_target_x96 = step.sqrt_price_next_x96
    end

    let (sqrt_price_next: Uint256, amount_in: Uint256, amount_out: Uint256, fee_amount: Uint256) = SwapMath.compute_swap_step(
        state.sqrt_price_x96,
        sqrt_price_target_x96,
        state.liquidity,
        state.amount_specified_remaining,
        _fee.read()[0]
    )

    if exact_input == 1:
        let (tmp: Uint256) = uint256_sub(state.amount_specified_remaining, uint256_add(step.amount_in, step.fee_amount)[0])
        state.amount_specified_remaining = tmp
        let (tmp: Uint256) = uint256_sub(state.amount_caculated, step.amount_out)
        state.amount_caculated = tmp
    else:
        let (tmp: Uint256, _) = uint256_add(state.amount_specified_remaining, step.amount_out)
        state.amount_specified_remaining = tmp
        let (tmp: Uint256, _) = uint256_add(state.amount_caculated, uint256_add(step.amount_in, step.fee_amount)[0])
        state.amount_caculated = tmp
    end

    if Utils.gt(cache.fee_protocol, 0)[0] == 1:
        let (delta: Uint256, _) = uint256_unsigned_div_rem(step.fee_amount, Uint256(cache.fee_protocol, 0))
        let (tmp: Uint256, _) = uint256_sub(step.fee_amount, delta)
        step.fee_amount = tmp
        let (tmp: Uint256, _) = uint256_add(state.protocol_fee, delta)
        state.protocol_fee = tmp
    end

    if Utils.is_gt(state.liquidity, 0)[0] == 1:
        let (tmp: Uint256) = FullMath.uint256_mul_div(step.fee_amount, Uint256(0, 1), step.liquidity)
        let (tmp2: Uint256, _) = uint256_add(state.fee_growth_global_x128, tmp)
        state.fee_growth_global_x128 = tmp2
    end

    if uint256_eq(state.sqrt_price_x96, step.sqrt_price_next_x96)[0] == 1:
        if step.initialized == 1:
            if zero_for_one == 1:
                let (tmp) = TickMgr.cross(step.tick_next, state.fee_growth_global_x128, _fee_growth_global1_x128.read()[0])
                let liquidity_net = -1 * tmp
            else:
                let (liquidity_net) = TickMgr.cross(step.tick_next, _fee_growth_global0_x128.read()[0], state.fee_growth_global_x128)
            end

            let (tmp) = Utils.u128_safe_add(state.liquidity, liquidity_net)
            state.liqudity = tmp
        end
        if zero_for_one == 1:
            state.tick = step.tick_next - 1
        else:
            state.tick = step.tick_next
        end
    else:
        if uint256_eq(state.sqrt_price_x96, step.sqrt_price_start_x96) == 0:
            let (tmp) = TickMath.get_tick_at_sqrt_ratio(state.sqrt_price_x96)
            state.tick = tmp
        end
    end

    let (new_state: SwapState, new_cache: SwapCache) = _compute_swap_step(state, cache, exact_input, zero_for_one, sqrt_price_limit_x96)

    return (new_state, new_cache)
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

    assert uint256_eq(amount_specified, Uint256(0, 0))[0] = 1

    let (slot0) = _slot0.read()
    assert slot0.unlocked = 1


    if zero_for_one == 1:
        assert uint256_lt(sqrt_price_limit_x96, slot0.sqrt_price_x96)[0] = 1
        assert uint256_lt(Uint256(TickMath.MIN_SQRT_RATIO, 0), sqrt_price_limit_x96)[0] = 1

        let (_, fee_protocol) = unsigned_div_rem(slot0.fee_protocol, 16)
    else:
        assert uint256_lt(slot0.sqrt_price_x96, sqrt_price_limit_x96)[0] = 1
        assert uint256_lt(sqrt_price_limit_x96, Uint256(TickMath.MAX_SQRT_RATIO_LOW, TickMath.MAX_SQRT_RATIO_HIGH))[0] = 1

        let (fee_protocol, _) = unsigned_div_rem(slot0.fee_protocol, 16)
    end

    #TODO: prevent reentry?
    slot0.unlocked = 1
    _slot0.write(slot0)

    let cache = SwapCache(
        liquidity_start = _liquidity.read()[0],
        fee_protocol = fee_protocol
    )

    let (exact_input) = uint256_lt(Uint256(0, 0), amount_specified)

    if zero_for_one == 1:
        let (fee_growth: Uint256) = _fee_growth_global0_x128.read()[0]
    else:
        let (fee_growth: Uint256) = _fee_growth_global1_x128.read()[0]
    end

    let state = SwapState(
        amount_remaining = amount_specified,
        amount_caculated = Uint256(0, 0),
        sqrt_price_x96 = slot0.sqrt_price_x96,
        tick = slot0.tick,
        fee_growth_global_x128 = fee_growth,
        protocol_fee = 0,
        liquidity = cache.liquidity_start
    )

    let (state: SwapState, cache: SwapCache) = _compute_swap_step(state, cache, exact_input, zero_for_one, sqrt_price_limit_x96)

    slot0.sqrt_price_x96 = state.sqrt_price_x96
    if state.tick != slot0.tick:
        slot0.tick = state.tick
    end

    if cache.liquidity_start != state.liquidity:
        _liquidity.write(state.liquidity)
    end

    if zero_for_one == 1:
        _fee_growth_global0_x128.write(state.fee_growth_global_x128)
        if Utils.is_gt(state.protocol_fee, 0)[0] == 1:
            let (tmp: Uint256, _) = uint256_add(_protocol_fee_token0.read()[0], state.protocol_fee)
            _protocol_fee_token0.write(tmp)
        end
    else:
        _fee_growth_global1_x128.write(state.fee_growth_global_x128)
        if Utils.is_gt(state.protocol_fee, 0)[0] == 1:
            let (tmp: Uint256, _) = uint256_add(_protocol_fee_token1.read()[0], state.protocol_fee)
            _protocol_fee_token1.write(tmp)
        end
    end

    if zero_for_one == exact_input:
        let (amount0: Uint256) = uint256_sub(amount_specified, state.amount_specified_remaining)
        let amount1: Uint256 = state.amount_caculated
        return (amount0, amount1)
    end

    let amount0: Uint256 = state.amount_caculated
    let (amount1: Uint256) = uint256_sub(amount_specified, state.amount_specified_remaining)
    return (amount0, amount1)
end
