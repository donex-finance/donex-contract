%lang starknet

from starkware.cairo.common.cairo_builtins import (HashBuiltin, BitwiseBuiltin)
from starkware.cairo.common.uint256 import (Uint256, uint256_mul, uint256_shr, uint256_shl, uint256_lt, uint256_le, uint256_add, uint256_unsigned_div_rem, uint256_signed_div_rem, uint256_or, uint256_sub, uint256_and, uint256_eq, uint256_signed_lt, uint256_neg, uint256_signed_nn)
from starkware.cairo.common.bool import (FALSE, TRUE)
from starkware.cairo.common.math import unsigned_div_rem
from starkware.cairo.common.math_cmp import is_le

from contracts.tick_mgr import TickMgr 
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
    member fee_protocol: felt
    member unlocked: felt
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

    _tick_spacing.write(tick_spacing)
    _fee.write(fee)
    return ()
end

@external
func initialized{
        syscall_ptr: felt*,
        pedersen_ptr: HashBuiltin*,
        range_check_ptr,
        bitwise_ptr: BitwiseBuiltin*
    }(sqrt_price_x96: Uint256):
    alloc_locals

    let (slot0) = _slot0.read()
    let (is_valid) = uint256_eq(slot0.sqrt_price_x96, Uint256(0, 0))
    with_attr error_message("initialized more than once"):
        assert is_valid = 1
    end

    let (tick) = TickMath.get_tick_at_sqrt_ratio(sqrt_price_x96)

    slot0.sqrt_price_x96.low = sqrt_price_x96.low
    slot0.sqrt_price_x96.high = sqrt_price_x96.high
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
    alloc_locals
    let syscall_ptr2 = syscall_ptr
    let pedersen_ptr2 = pedersen_ptr
    let range_check_ptr2 = range_check_ptr
    let bitwise_ptr2 = bitwise_ptr

    let (flag1) = uint256_eq(state.amount_specified_remaining, Uint256(0, 0))
    let (flag2) = uint256_eq(state.sqrt_price_x96, sqrt_price_limit_x96)

    if flag1 + flag2 == 0:
        return (state, cache)
    end

    let (tick_spacing) = _tick_spacing.read()

    let (tick_next, initialized) = TickBitmap.next_valid_tick_within_one_word(state.tick, tick_spacing, zero_for_one)

    let step = StepComputations(
        sqrt_price_start_x96 = state.sqrt_price_x96,
        tick_next = tick_next,
        initialized = initialized,
        sqrt_price_next_x96 = Uint256(0, 0),
        amount_in = Uint256(0, 0),
        amount_out = Uint256(0, 0),
        fee_amount = Uint256(0, 0)
    )

    let (is_valid) = Utils.is_lt(tick_next, TickMath.MIN_TICK) 
    if is_valid == 1:
        step.tick_next = TickMath.MIN_TICK
    end

    let (is_valid) = Utils.is_lt(TickMath.MAX_TICK, tick_next) 
    if is_valid == 1:
        step.tick_next = TickMath.MAX_TICK
    end

    let (res: Uint256) = TickMath.get_sqrt_ratio_at_tick(step.tick_next)
    step.sqrt_price_next_x96.low = res.low
    step.sqrt_price_next_x96.high = res.high

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

    let (fee) = _fee.read()
    let (sqrt_price_next: Uint256, amount_in: Uint256, amount_out: Uint256, fee_amount: Uint256) = SwapMath.compute_swap_step(
        state.sqrt_price_x96,
        sqrt_price_target_x96,
        state.liquidity,
        state.amount_specified_remaining,
        fee,
    )

    with range_check_ptr:
        if exact_input == 1:
            let (tmp1: Uint256, _) = uint256_add(step.amount_in, step.fee_amount)
            let (tmp2: Uint256) = uint256_sub(state.amount_specified_remaining, tmp1)
            state.amount_specified_remaining.low = tmp2.low
            state.amount_specified_remaining.high = tmp2.high

            let (tmp3: Uint256) = uint256_sub(state.amount_caculated, step.amount_out)
            state.amount_caculated.low = tmp3.low
            state.amount_caculated.high = tmp3.high
        else:
            let (tmp: Uint256, _) = uint256_add(state.amount_specified_remaining, step.amount_out)
            state.amount_specified_remaining.low = tmp.low
            state.amount_specified_remaining.high = tmp.high

            let (tmp2: Uint256, _) = uint256_add(step.amount_in, step.fee_amount)
            let (tmp3: Uint256, _) = uint256_add(state.amount_caculated, tmp2)
            state.amount_caculated.low = tmp3.low
            state.amount_caculated.high = tmp3.high
        end
    end
    let range_check_ptr = range_check_ptr2

    with range_check_ptr:
        let (is_valid) = Utils.is_gt(cache.fee_protocol, 0)
        if is_valid == 1:
            let (delta: Uint256, _) = uint256_unsigned_div_rem(step.fee_amount, Uint256(cache.fee_protocol, 0))
            let (tmp: Uint256) = uint256_sub(step.fee_amount, delta)
            step.fee_amount.low = tmp.low
            step.fee_amount.high = tmp.high
            #TODO: overflow?
            let (tmp: Uint256, _) = uint256_add(Uint256(state.protocol_fee, 0), delta)
            state.protocol_fee = tmp.low
        end
    end
    let range_check_ptr = range_check_ptr2

    with range_check_ptr, bitwise_ptr:
        let (is_valid) = Utils.is_gt(state.liquidity, 0)
        if is_valid == 1:
            let (tmp: Uint256, _) = FullMath.uint256_mul_div(step.fee_amount, Uint256(0, 1), Uint256(state.liquidity, 0))
            let (tmp2: Uint256, _) = uint256_add(state.fee_growth_global_x128, tmp)
            state.fee_growth_global_x128.low = tmp2.low
            state.fee_growth_global_x128.high = tmp2.high
        end
    end
    let range_check_ptr = range_check_ptr2
    let bitwise_ptr = bitwise_ptr2

    with syscall_ptr, pedersen_ptr, range_check_ptr, bitwise_ptr:
        let (is_valid) = uint256_eq(state.sqrt_price_x96, step.sqrt_price_next_x96)
        if is_valid == 1:
            if step.initialized == 1:
                local liquidity_net
                if zero_for_one == 1:
                    let (fee_growth_global1_x128: Uint256) = _fee_growth_global1_x128.read()
                    let (tmp_felt) = TickMgr.cross(step.tick_next, state.fee_growth_global_x128, fee_growth_global1_x128)
                    tempvar tmp_felt2 = -tmp_felt
                    liquidity_net = tmp_felt2
                    tempvar range_check_ptr = range_check_ptr
                else:
                    let (fee_growth_global0_x128: Uint256) = _fee_growth_global0_x128.read()
                    let (tmp_felt) = TickMgr.cross(step.tick_next, fee_growth_global0_x128, state.fee_growth_global_x128)
                    liquidity_net = tmp_felt
                    tempvar range_check_ptr = range_check_ptr
                end

                let (tmp_felt) = Utils.u128_safe_add(state.liquidity, liquidity_net)
                state.liquidity = tmp_felt
            end
            if zero_for_one == 1:
                state.tick = step.tick_next - 1
            else:
                state.tick = step.tick_next
            end
        else:
            let (is_valid) = uint256_eq(state.sqrt_price_x96, step.sqrt_price_start_x96)
            if is_valid == 0:
                let (tmp_felt) = TickMath.get_tick_at_sqrt_ratio(state.sqrt_price_x96)
                state.tick = tmp_felt
            end
        end
    end
    let syscall_ptr = syscall_ptr2
    let pedersen_ptr = pedersen_ptr2
    let range_check_ptr = range_check_ptr2
    let bitwise_ptr = bitwise_ptr2

    return _compute_swap_step(state, cache, exact_input, zero_for_one, sqrt_price_limit_x96)
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
    let syscall_ptr2 = syscall_ptr
    let pedersen_ptr2 = pedersen_ptr
    let range_check_ptr2 = range_check_ptr
    let bitwise_ptr2 = bitwise_ptr

    let (is_valid) = uint256_eq(amount_specified, Uint256(0, 0))
    assert is_valid = 1

    let (slot0: SlotState) = _slot0.read()
    assert slot0.unlocked = 1

    local fee_protocol
    with range_check_ptr:
        if zero_for_one == 1:
            let (is_valid) = uint256_lt(sqrt_price_limit_x96, slot0.sqrt_price_x96)
            assert is_valid = 1

            let (is_valid) = uint256_lt(Uint256(TickMath.MIN_SQRT_RATIO, 0), sqrt_price_limit_x96)
            assert is_valid = 1

            let (_, tmp_felt) = unsigned_div_rem(slot0.fee_protocol, 16)
            fee_protocol = tmp_felt
        else:
            let (is_valid) = uint256_lt(slot0.sqrt_price_x96, sqrt_price_limit_x96)
            assert is_valid = 1

            let (is_valid) = uint256_lt(sqrt_price_limit_x96, Uint256(TickMath.MAX_SQRT_RATIO_LOW, TickMath.MAX_SQRT_RATIO_HIGH))
            assert is_valid = 1

            let (tmp_felt, _) = unsigned_div_rem(slot0.fee_protocol, 16)
            fee_protocol = tmp_felt
        end
    end
    let range_check_ptr = range_check_ptr2

    #TODO: prevent reentry?
    slot0.unlocked = 1
    _slot0.write(slot0)

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

    let state = SwapState(
        amount_specified_remaining = amount_specified,
        amount_caculated = Uint256(0, 0),
        sqrt_price_x96 = slot0.sqrt_price_x96,
        tick = slot0.tick,
        fee_growth_global_x128 = fee_growth,
        protocol_fee = 0,
        liquidity = cache.liquidity_start
    )

    let (state: SwapState, cache: SwapCache) = _compute_swap_step(state, cache, exact_input, zero_for_one, sqrt_price_limit_x96)

    slot0.sqrt_price_x96.low = state.sqrt_price_x96.low
    slot0.sqrt_price_x96.high = state.sqrt_price_x96.high
    if state.tick != slot0.tick:
        slot0.tick = state.tick
    end

    with syscall_ptr, pedersen_ptr, range_check_ptr:
        if cache.liquidity_start != state.liquidity:
            _liquidity.write(state.liquidity)
        end
    end
    let syscall_ptr = syscall_ptr2
    let pedersen_ptr = pedersen_ptr2
    let range_check_ptr = range_check_ptr2

    with syscall_ptr, pedersen_ptr, range_check_ptr:
        if zero_for_one == 1:
            _fee_growth_global0_x128.write(state.fee_growth_global_x128)

            let (is_valid) = Utils.is_gt(state.protocol_fee, 0)
            if is_valid == 1:
                let (protocol_fee_token0: Uint256) = _protocol_fee_token0.read()
                let (tmp: Uint256, _) = uint256_add(protocol_fee_token0, Uint256(state.protocol_fee, 0))
                _protocol_fee_token0.write(tmp)
            end
        else:
            _fee_growth_global1_x128.write(state.fee_growth_global_x128)
            let (is_valid) = Utils.is_gt(state.protocol_fee, 0)
            if is_valid == 1:
                let (protocol_fee_token1: Uint256) = _protocol_fee_token1.read()
                let (tmp: Uint256, _) = uint256_add(protocol_fee_token1, Uint256(state.protocol_fee, 0))
                _protocol_fee_token1.write(tmp)
            end
        end
    end
    let syscall_ptr = syscall_ptr2
    let pedersen_ptr = pedersen_ptr2
    let range_check_ptr = range_check_ptr2

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
    with_attr error_message("TLU"):
        assert is_valid = 1
    end

    let (is_valid) = is_le(TickMath.MIN_TICK, tick_lower)
    with_attr error_message("TLM"):
        assert is_valid = 1
    end

    let (is_valid) = is_le(tick_upper, TickMath.MAX_TICK)
    with_attr error_message("TUM"):
        assert is_valid = 1
    end
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
        tick: felt) -> (positionInfo: PositionInfo):

    let (position: PositionInfo) = PositionMgr.get(owner, tick_lower, tick_upper)

    let (fee_growth_global0_x128: Uint256) = _fee_growth_global0_x128.read()
    let (fee_growth_global1_x128: Uint256) = _fee_growth_global1_x128.read()

    if liquidity_delta != 0:
        let (max_liquidity_per_tick) = _max_liquidity_per_tick.read()
        let (flipped_lower: felt) = TickMgr.update(tick_lower, tick, liquidity_delta, fee_growth_global0_x128, fee_growth_global1_x128, 0, max_liquidity_per_tick)
        let (flipped_uppder: felt) = TickMgr.update(tick_upper, tick, liquidity_delta, fee_growth_global0_x128, fee_growth_global1_x128, 1, max_liquidity_per_tick)

        let (tick_spacing) = _tick_spacing.read()
        if flipped_lower == 1:
            TickBitmap.flip_tick(tick_lower, tick_spacing)
        end

        if flipped_uppder == 1:
            TickBitmap.flip_tick(tick_upper, tick_spacing)
        end
    end

    let (fee_growth_inside0_x128: Uint256, fee_growth_inside1_x128: Uint256) = TickMgr.get_fee_growth_inside(tick_lower, tick_upper, tick, fee_growth_global0_x128, fee_growth_global1_x128)

    let (new_position: PositionInfo) = PositionMgr.update_position(position, liquidity_delta, fee_growth_inside0_x128, fee_growth_inside1_x128)

    let (is_valid) = Utils.is_lt(liquidity_delta, 0)
    if is_valid == 1:
        if flipped_lower == 1:
            TickMgr.clear(tick_lower)
        end

        if flipped_uppder == 1:
            TickMgr.clear(tick_upper)
        end
    end

    return (new_position)
end

func _modify_position{
        syscall_ptr: felt*,
        pedersen_ptr: HashBuiltin*,
        range_check_ptr,
        bitwise_ptr: BitwiseBuiltin*
    }(params: ModifyPositionParams) -> (position: PositionInfo, amount0: Uint256, amount1: Uint256):

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

            amount1 = SqrtPriceMath.get_amount1_delta2(sqrt_ratio0, slot0.sqrt_price_x96, params.liquidity_delta)

            let (cur_liquidity) = _liquidity.read()
            let liquidity = Utils.u128_safe_add(cur_liquidity, params.liquidity_delta)
            _liquidity.write(liquidity)

            return (position, amount0, amount1)
        end

        let (amount1: Uint256) = SqrtPriceMath.get_amount1_delta2(sqrt_ratio0, sqrt_ratio1, params.liquidity_delta)
        return (position, Uint256(0, 0), amount1)
    end

    return (position, Uint256(0, 0), Uint256(0, 0))
end

@external
func mint{
        syscall_ptr: felt*,
        pedersen_ptr: HashBuiltin*,
        range_check_ptr,
        bitwise_ptr: BitwiseBuiltin*
    }(
        recipient: felt,
        tickLower: felt,
        tickUpper: felt,
        amount: felt,
    ) -> (amount0: Uint256, amount1: Uint256):

    #TODO: lock

    let (is_valid) = Utils.is_gt(amount, 0)
    assert is_valid = 1

    let (position: PositionInfo, amount0: Uint256, amount1: Uint256) = _modify_position(
        ModifyPositionParams(
            owner = recipient,
            tick_lower = tickLower,
            tick_upper = tickUpper,
            liquidity_delta = amount
        )
    )

    #TODO: transfer

    return (amount0, amount1)
end

@external
func burn{
        syscall_ptr: felt*,
        pedersen_ptr: HashBuiltin*,
        range_check_ptr,
        bitwise_ptr: BitwiseBuiltin*
    }(
        recipient: felt,
        tickLower: felt,
        tickUpper: felt,
        amount: felt,
    ) -> (amount0: Uint256, amount1: Uint256):

    #TODO: lock
    let (position: PositionInfo, amount0: Uint256, amount1: Uint256) = _modify_position(
        ModifyPositionParams(
            owner = recipient,
            tick_lower = tickLower,
            tick_upper = tickUpper,
            liquidity_delta = amount
        )
    )

    #TODO: update position
    return (-amount0, -amount1)
end

#@external
#func setFeeProtocol{
#        syscall_ptr: felt*,
#        pedersen_ptr: HashBuiltin*,
#        range_check_ptr,
#        bitwise_ptr: BitwiseBuiltin*
#    }(
#        fee_protocol0: felt,
#        fee_protocol1: felt
#    ):
#    #TODO: onlyOwner
#    let (fee_protocol_ptr: Uint256) = fee_protocol
#    _fee_protocol.write(fee_protocol_ptr)
#end