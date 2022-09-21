%lang starknet

from starkware.cairo.common.uint256 import Uint256

from contracts.position_mgr import PositionInfo

@contract_interface
namespace ISwapPoolCallback {
    func add_liquidity_callback(amount0: Uint256, amount1: Uint256, data: felt) {
    }

    func swap_callback(amount0: Uint256, amount1: Uint256, data: felt) {
    } 
}