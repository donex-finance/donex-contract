%lang starknet

from starkware.cairo.common.uint256 import Uint256

from contracts.position_mgr import PositionInfo

@contract_interface
namespace IUserPositionMgr {
    func initializer(
        owner: felt,
        swap_pool_hash: felt,
        swap_pool_proxy_hash: felt,
        name: felt,
        symbol: felt
    ) {
    }
}