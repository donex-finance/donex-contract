%lang starknet

from starkware.cairo.common.uint256 import Uint256

from contracts.position_mgr import PositionInfo

@contract_interface
namespace ISwapPool {
    func get_cur_slot() -> (sqrt_price_x96: Uint256, tick: felt) {
    }

    func get_position(owner: felt, tick_lower: felt, tick_upper: felt) -> (position: PositionInfo) {
    }

    func add_liquidity(recipient: felt, tick_lower: felt, tick_upper: felt, liquidity: felt) -> (
        amount0: Uint256, amount1: Uint256
    ) {
    }

    func remove_liquidity(tick_lower: felt, tick_upper: felt, liquidity: felt) -> (
        amount0: Uint256, amount1: Uint256
    ) {
    }

    func swap(
        recipient: felt,
        zero_for_one: felt,
        amount_specified: Uint256,
        sqrt_price_limit_x96: Uint256,
    ) -> (amount0: Uint256, amount1: Uint256) {
    }

    func collect(
        recipient: felt,
        tick_lower: felt,
        tick_upper: felt,
        amount0_requested: felt,
        amount1_requested: felt,
    ) -> (amount0: felt, amount1: felt) {
    }

    func collect_protocol(recipient: felt, amount0_requested: felt, amount1_requested: felt) -> (
        amount0: felt, amount1: felt
    ) {
    }

    func set_fee_protocol(fee_protocol0: felt, fee_protocol1: felt) {
    }
}
