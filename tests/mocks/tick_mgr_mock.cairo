%lang starknet

from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.cairo.common.uint256 import Uint256
from starkware.cairo.common.cairo_builtins import BitwiseBuiltin

from contracts.tick_mgr import (TickMgr, TickInfo)

@view
func get_max_liquidity_per_tick{
        syscall_ptr: felt*,
        pedersen_ptr: HashBuiltin*,
        range_check_ptr
    } (tick_spacing: felt) -> (res: felt):
    let (res) = TickMgr.get_max_liquidity_per_tick(tick_spacing)
    return (res)
end

@external
func cross{
        syscall_ptr: felt*,
        pedersen_ptr: HashBuiltin*,
        range_check_ptr
    }(
        tick: felt, 
        fee_growth_global0_x128: Uint256, 
        fee_growth_global1_x128: Uint256
    ) -> (liquidity_net: felt):
    let (res) = TickMgr.cross(tick, fee_growth_global0_x128, fee_growth_global1_x128)
    return (res)
end

@external
func update{
        syscall_ptr: felt*,
        pedersen_ptr: HashBuiltin*,
        range_check_ptr
    }(
        tick: felt, 
        tick_current: felt, 
        liquidity_delta: felt, 
        fee_growth_global0_x128: Uint256, 
        fee_growth_global1_x128: Uint256, 
        upper: felt, 
        max_liquidity: felt
    ) -> (flipped: felt):
    let (res) = TickMgr.update(tick, tick_current, liquidity_delta, fee_growth_global0_x128, fee_growth_global1_x128, upper, max_liquidity)
    return (res)
end

@external
func get_fee_growth_inside{
        syscall_ptr: felt*,
        pedersen_ptr: HashBuiltin*,
        range_check_ptr
    }(
        tick_lower: felt,
        tick_upper: felt,
        tick_current: felt,
        fee_growth_global0_x128: Uint256,
        fee_growth_global1_x128: Uint256
    ) -> (fee_growth_inside0_x128: Uint256, fee_growth_inside1_x128: Uint256):
    let (fee_growth_inside0_x128: Uint256, fee_growth_inside1_x128: Uint256) = TickMgr.get_fee_growth_inside(tick_lower, tick_upper, tick_current, fee_growth_global0_x128, fee_growth_global1_x128)
    return (fee_growth_inside0_x128, fee_growth_inside1_x128)
end

@external
func set_tick{
        syscall_ptr: felt*,
        pedersen_ptr: HashBuiltin*,
        range_check_ptr
    }(tick: felt, tickInfo: TickInfo):
    TickMgr.set_tick(tick, tickInfo)
    return ()
end

@view
func get_tick{
        syscall_ptr: felt*,
        pedersen_ptr: HashBuiltin*,
        range_check_ptr
    }(tick: felt) -> (tickInfo: TickInfo):
    let (tickInfo: TickInfo) = TickMgr.get_tick(tick)
    return (tickInfo)
end