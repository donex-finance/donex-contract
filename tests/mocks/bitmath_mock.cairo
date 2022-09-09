%lang starknet

from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.cairo.common.uint256 import Uint256
from starkware.cairo.common.cairo_builtins import BitwiseBuiltin

from contracts.bitmath import BitMath

@view
func most_significant_bit{
    syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr, bitwise_ptr: BitwiseBuiltin*
}(num: Uint256) -> (res: felt) {
    let (res) = BitMath.most_significant_bit(num);
    return (res,);
}

@view
func least_significant_bit{
    syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr, bitwise_ptr: BitwiseBuiltin*
}(num: Uint256) -> (res: felt) {
    let (res) = BitMath.least_significant_bit(num);
    return (res,);
}
