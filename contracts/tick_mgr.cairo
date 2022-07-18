%lang starknet

from starkware.cairo.common.math import signed_div_rem
from starkware.cairo.common.math_cmp import is_le
from starkware.cairo.common.bool import (TRUE, FALSE)
from starkware.cairo.common.uint256 import (Uint256, uint256_sub)

from contracts.tickmath import TickMath
from contracts.math_utils import Utils

struct TickInfo:
    member liquidity_gross: felt
    member liquidity_net: felt
    member fee_growth_outside0_x128: Uint256
    member fee_growth_outside1_x128: Uint256
    member initialized: felt
end

@storage_var
func TickMgr_data(tick: felt) -> (tickInfo: TickInfo):
end

namespace TickMgr:

    func get_max_liquidity_per_tick{
        range_check_ptr
        }(tick_spaceing: felt) -> (max_liquidity: felt):
        let (min_tick) = signed_div_rem(TickMath.MIN_TICK, tick_spaceing)[0] * tick_spaceing
        let (max_tick) = signed_div_rem(TickMath.MAX_TICK, tick_spaceing)[0] * tick_spaceing
        let (n_ticks) = signed_div_rem(max_tick - min_tick, tick_spaceing)[0] + 1
        let (max_liquidity, _) = signed_div_rem(0xffffffffffffffffffffffffffffffff, n_ticks) 

        return (max_liquidity)
    end

    func cross{
        range_check_ptr
        }(
        tick: felt, 
        fee_growth_global0_x128: Uint256, 
        fee_growth_global1_x128: Uint256) -> (liquidity_net: felt):
        
        let (info: TickInfo) = TickMgr_data.read(tick)
        info.fee_growth_global0_x128 = fee_growth_global0_x128 - info.fee_growth_global_0x128
        info.fee_growth_global1_x128 = fee_growth_global1_x128 - info.fee_growth_global_1x128

        #TODO: if need write to the storage
        TickMgr_data.write(tick, info)

        return (info.liquidity_net)
    end

    func update{
        range_check_ptr
        }(
        tick: felt, 
        tick_current: felt, 
        liquidity_delta: felt, 
        fee_growth_global0_x128: Uint256, 
        fee_growth_global1_x128: Uint256, 
        upper: felt, 
        max_liquidity: felt) -> (flipped: felt):

        let (info: TickInfo) = TickMgr_data.read(tick)

        let liq_gross_before = info.liquidity_gross
        let (liq_gross_after) = Utils.u128_safe_add(liq_gross_before, liquidity_delta)

        let (is_valid) = is_le(liq_gross_after, max_liquidity)
        with_attr error_message("update: liq_gross_after > max_liquidity"):
            assert is_valid = 1
        end

        if liq_gross_before == 0:
            let (is_valid) = is_le(tick, tick_current)
            if is_valid == 1:
                info.fee_growth_global0_x128 = fee_growth_global0_x128
                info.fee_growth_global1_x128 = fee_growth_global1_x128
            end
            info.initialized = TRUE
        end

        info.liquidity_gross = liq_gross_after

        if upper == TRUE:
            info.liquidity_net = info.liquidity_net - liquidity_delta
        else:
            info.liquidity_net = info.liquidity_net + liquidity_delta
        end

        TickMgr_data.write(tick, info)

        let (tmp) = Utils.is_eq(liq_gross_after, 0)
        let (tmp2) = Utils.is_eq(liq_gross_before, 0)
        if tmp != tmp2:
            return (1)
        end
        return (0)
    end

    func get_fee_groth_inside{
        range_check_ptr
        }(
        tick_lower: felt,
        tick_upper: felt,
        tick_current: felt,
        fee_growth_global0_x128: Uint256,
        fee_growth_global1_x128: Uint256) -> (fee_growth_inside0_x128: Uint256, fee_growth_inside1_x128: Uint256):

        alloc_locals
        
        let (info_lower: TickInfo) = TickMgr_data.read(tick_lower)
        let (info_upper: TickInfo) = TickMgr_data.read(tick_upper)

        let (is_valid) = is_le(tick_lower, tick_current)
        if is_valid == 1:
            tempvar fee_growth_below0_x128: Uint256 = info_lower.fee_growth_outside0_x128
            tempvar fee_growth_below1_x128: Uint256 = info_lower.fee_growth_outside1_x128
        else:
            let (tmp: Uint256) = uint256_sub(fee_growth_global0_x128, info_lower.fee_growth_outside0_x128)
            tempvar fee_growth_below0_x128: Uint256 = tmp

            let (tmp: Uint256) = uint256_sub(fee_growth_global1_x128, info_lower.fee_growth_outside1_x128)
            tempvar fee_growth_below1_x128: Uint256 = tmp
        end

        let (is_valid) = Utils.is_lt(tick_current, tick_upper)
        if is_valid == 1:
            tempvar fee_growth_above0_x128: Uint256 = info_upper.fee_growth_outside0_x128
            tempvar fee_growth_above1_x128: Uint256 = info_upper.fee_growth_outside1_x128
        else:
            let (tmp: Uint256) = fee_growth_global0_x128 - info_upper.fee_growth_outside0_x128
            tempvar fee_growth_above0_x128: Uint256 = tmp

            let (tmp: Uint256) = fee_growth_global1_x128 - info_upper.fee_growth_outside1_x128
            tempvar fee_growth_above1_x128: Uint256 = tmp
        end

        let (fee_growth_inside0_x128: Uint256) = uint256_sub(uint256_sub(fee_growth_global0_x128, fee_growth_below0_x128)[0], fee_growth_above0_x128)
        let (fee_growth_inside1_x128: Uint256) = uint256_sub(uint256_sub(fee_growth_global1_x128, fee_growth_below1_x128)[0], fee_growth_above1_x128)

        return (fee_growth_inside0_x128, fee_growth_inside1_x128)
    end
end