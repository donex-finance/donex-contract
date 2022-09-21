%lang starknet

from starkware.cairo.common.uint256 import Uint256

from contracts.position_mgr import PositionInfo

@contract_interface
namespace ISwapPoolCallback {
    func add_liquidity_callback(token0: felt, amount0: Uint256, token1: felt, amount1: Uint256, data: felt) {
    }

    func swap_callback(token0: felt, amount0: Uint256, token1: felt, amount1: Uint256, data: felt) {
    } 
}