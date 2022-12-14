%lang starknet

from starkware.cairo.common.uint256 import Uint256

from contracts.position_mgr import PositionInfo

@contract_interface
namespace IUserPositionMgr {
    func get_pool_address(token0: felt, token1: felt, fee: felt) -> (pool_address: felt) {
    }
}