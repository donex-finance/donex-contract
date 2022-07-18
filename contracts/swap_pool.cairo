%lang starknet

from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.cairo.common.uint256 import (Uint256, uint256_lt)
from starkware.cairo.common.bool import (FALSE, TRUE)

from contracts.tick_mgr import TickMgr 
from contracts.tick_bitmap import TickBitmap
from contracts.position_mgr import PositionMgr

struct SlotState:
    member sqrt_price_x96: Uint256
    member tick: felt
    member fee_protocoal: felt
    member unlocked: felt
end

struct SwapCache:
    member fee_protocoal: felt
    member liquidity_start: felt
end

struct SwapState:
    member amount_remaining: Uint256
    member amount_caculated: Uint256
    member sqrt_price_x96: Uint256
    member tick: felt 
    member fee_growth_global_x128: Uint256
    member protocol_fee: felt
    member liquidity: felt
end

struct StepComputations: 
    member sqrt_price_x96: Uint256
    member tick_next: felt
    member initialized: felt
    member sqrt_price_next_x96: Uint256
    member amount_in: Uint256
    member amount_out: Uint256
    member fee_amount: Uint256
end

struct ProtocolFees:
    member token0: Uint256
    member token1: Uint256
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
func _protocol_fee() -> (protocol_fee: ProtocolFees):
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
