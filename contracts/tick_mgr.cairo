%lang starknet

from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.cairo.common.math import signed_div_rem, unsigned_div_rem
from starkware.cairo.common.math_cmp import is_le
from starkware.cairo.common.bool import TRUE, FALSE
from starkware.cairo.common.uint256 import Uint256, uint256_sub

from contracts.tickmath import TickMath
from contracts.math_utils import Utils

struct TickInfo {
    liquidity_gross: felt,
    liquidity_net: felt,
    fee_growth_outside0_x128: Uint256,
    fee_growth_outside1_x128: Uint256,
    initialized: felt,
}

@storage_var
func TickMgr_data(tick: felt) -> (tickInfo: TickInfo) {
}

namespace TickMgr {
    const bound = 2 ** 127;

    func get_max_liquidity_per_tick{range_check_ptr}(tick_spacing: felt) -> (max_liquidity: felt) {
        alloc_locals;

        let (tmp, rem) = signed_div_rem(TickMath.MIN_TICK, tick_spacing, bound);
        let (is_valid) = Utils.is_gt(rem, 0);
        if (is_valid == 1) {
            tempvar min_tick = (tmp + 1) * tick_spacing;
        } else {
            tempvar min_tick = tmp * tick_spacing;
        }

        let (tmp, _) = unsigned_div_rem(TickMath.MAX_TICK, tick_spacing);
        let max_tick = tmp * tick_spacing;

        let (tmp, _) = unsigned_div_rem(max_tick - min_tick, tick_spacing);
        let n_ticks = tmp + 1;

        let (max_liquidity, _) = unsigned_div_rem(Utils.MAX_UINT128, n_ticks);

        return (max_liquidity,);
    }

    func cross{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
        tick: felt, fee_growth_global0_x128: Uint256, fee_growth_global1_x128: Uint256
    ) -> (liquidity_net: felt) {
        let (info: TickInfo) = TickMgr_data.read(tick);
        let (fee_growth_outside0_x128: Uint256) = uint256_sub(
            fee_growth_global0_x128, info.fee_growth_outside0_x128
        );
        let (fee_growth_outside1_x128: Uint256) = uint256_sub(
            fee_growth_global1_x128, info.fee_growth_outside1_x128
        );

        TickMgr_data.write(
            tick,
            TickInfo(
            liquidity_gross=info.liquidity_gross,
            liquidity_net=info.liquidity_net,
            fee_growth_outside0_x128=fee_growth_outside0_x128,
            fee_growth_outside1_x128=fee_growth_outside1_x128,
            initialized=info.initialized
            ),
        );

        return (info.liquidity_net,);
    }

    func _update_1{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
        tick: felt,
        tick_current: felt,
        info: TickInfo,
        fee_growth_global0_x128: Uint256,
        fee_growth_global1_x128: Uint256,
    ) -> (fee_growth_outside0_x128: Uint256, fee_growth_outside1_x128: Uint256, initialized: felt) {
        if (info.liquidity_gross == 0) {
            let is_valid = is_le(tick, tick_current);
            if (is_valid == 1) {
                return (fee_growth_global0_x128, fee_growth_global1_x128, TRUE);
            }
            return (info.fee_growth_outside0_x128, info.fee_growth_outside1_x128, TRUE);
        }

        return (info.fee_growth_outside0_x128, info.fee_growth_outside1_x128, info.initialized);
    }

    func update{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
        tick: felt,
        tick_current: felt,
        liquidity_delta: felt,
        fee_growth_global0_x128: Uint256,
        fee_growth_global1_x128: Uint256,
        upper: felt,
        max_liquidity: felt,
    ) -> (flipped: felt) {
        alloc_locals;

        let (info: TickInfo) = TickMgr_data.read(tick);

        let liq_gross_before = info.liquidity_gross;
        let (liq_gross_after) = Utils.u128_safe_add(liq_gross_before, liquidity_delta);

        let is_valid = is_le(liq_gross_after, max_liquidity);
        with_attr error_message("update: liq_gross_after > max_liquidity") {
            assert is_valid = 1;
        }

        let (
            fee_growth_outside0_x128: Uint256, fee_growth_outside1_x128: Uint256, initialized: felt
        ) = _update_1(tick, tick_current, info, fee_growth_global0_x128, fee_growth_global1_x128);

        if (upper == TRUE) {
            tempvar liquidity_net = info.liquidity_net - liquidity_delta;
        } else {
            tempvar liquidity_net = info.liquidity_net + liquidity_delta;
        }

        TickMgr_data.write(
            tick,
            TickInfo(
            liquidity_gross=liq_gross_after,
            liquidity_net=liquidity_net,
            fee_growth_outside0_x128=fee_growth_outside0_x128,
            fee_growth_outside1_x128=fee_growth_outside1_x128,
            initialized=initialized
            ),
        );

        let (tmp) = Utils.is_eq(liq_gross_after, 0);
        let (tmp2) = Utils.is_eq(liq_gross_before, 0);
        if (tmp != tmp2) {
            return (1,);
        }
        return (0,);
    }

    func _get_fee_growth_inside_1{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
        tick_lower: felt,
        tick_current: felt,
        fee_growth_global0_x128: Uint256,
        fee_growth_global1_x128: Uint256,
    ) -> (fee_growth_below0_x128: Uint256, fee_growth_below1_x128: Uint256) {
        alloc_locals;

        let (info_lower: TickInfo) = TickMgr_data.read(tick_lower);

        let is_valid = is_le(tick_lower, tick_current);
        if (is_valid == 1) {
            return (info_lower.fee_growth_outside0_x128, info_lower.fee_growth_outside1_x128);
        }

        let (fee_growth_below0_x128: Uint256) = uint256_sub(
            fee_growth_global0_x128, info_lower.fee_growth_outside0_x128
        );

        let (fee_growth_below1_x128: Uint256) = uint256_sub(
            fee_growth_global1_x128, info_lower.fee_growth_outside1_x128
        );

        return (fee_growth_below0_x128, fee_growth_below1_x128);
    }

    func _get_fee_growth_inside_2{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
        tick_upper: felt,
        tick_current: felt,
        fee_growth_global0_x128: Uint256,
        fee_growth_global1_x128: Uint256,
    ) -> (fee_growth_above0_x128: Uint256, fee_growth_above1_x128: Uint256) {
        alloc_locals;

        let (info_upper: TickInfo) = TickMgr_data.read(tick_upper);

        let (is_valid) = Utils.is_lt_signed(tick_current, tick_upper);
        if (is_valid == 1) {
            return (info_upper.fee_growth_outside0_x128, info_upper.fee_growth_outside1_x128);
        }

        let (fee_growth_above0_x128: Uint256) = uint256_sub(
            fee_growth_global0_x128, info_upper.fee_growth_outside0_x128
        );

        let (fee_growth_above1_x128: Uint256) = uint256_sub(
            fee_growth_global1_x128, info_upper.fee_growth_outside1_x128
        );

        return (fee_growth_above0_x128, fee_growth_above1_x128);
    }

    func get_fee_growth_inside{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
        tick_lower: felt,
        tick_upper: felt,
        tick_current: felt,
        fee_growth_global0_x128: Uint256,
        fee_growth_global1_x128: Uint256,
    ) -> (fee_growth_inside0_x128: Uint256, fee_growth_inside1_x128: Uint256) {
        alloc_locals;

        let (
            fee_growth_below0_x128: Uint256, fee_growth_below1_x128: Uint256
        ) = _get_fee_growth_inside_1(
            tick_lower, tick_current, fee_growth_global0_x128, fee_growth_global1_x128
        );

        let (
            fee_growth_above0_x128: Uint256, fee_growth_above1_x128: Uint256
        ) = _get_fee_growth_inside_2(
            tick_upper, tick_current, fee_growth_global0_x128, fee_growth_global1_x128
        );

        let (tmp: Uint256) = uint256_sub(fee_growth_global0_x128, fee_growth_below0_x128);
        let (fee_growth_inside0_x128: Uint256) = uint256_sub(tmp, fee_growth_above0_x128);

        let (tmp: Uint256) = uint256_sub(fee_growth_global1_x128, fee_growth_below1_x128);
        let (fee_growth_inside1_x128: Uint256) = uint256_sub(tmp, fee_growth_above1_x128);

        return (fee_growth_inside0_x128, fee_growth_inside1_x128);
    }

    func set_tick{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
        tick: felt, tickInfo: TickInfo
    ) {
        TickMgr_data.write(tick, tickInfo);
        return ();
    }

    func get_tick{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(tick: felt) -> (
        tickInfo: TickInfo
    ) {
        let (tickInfo: TickInfo) = TickMgr_data.read(tick);
        return (tickInfo,);
    }

    func clear{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(tick: felt) {
        TickMgr_data.write(
            tick,
            TickInfo(
            liquidity_gross=0,
            liquidity_net=0,
            fee_growth_outside0_x128=Uint256(0, 0),
            fee_growth_outside1_x128=Uint256(0, 0),
            initialized=0
            ),
        );
        return ();
    }
}
