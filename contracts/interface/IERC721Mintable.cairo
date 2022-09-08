%lang starknet

from starkware.cairo.common.uint256 import Uint256

@contract_interface
namespace IERC721Mintable:
    func mint(to: felt, tokenId: Uint256):
    end

    func burn(tokenId: Uint256):
    end
end