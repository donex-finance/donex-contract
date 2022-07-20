%lang starknet

from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.cairo.common.uint256 import Uint256
from starkware.cairo.common.cairo_builtins import BitwiseBuiltin

from contracts.fullmath import FullMath

@view
func uint256_mul_div{
        syscall_ptr: felt*,
        pedersen_ptr: HashBuiltin*,
        range_check_ptr,
        bitwise_ptr: BitwiseBuiltin*
    } (a: Uint256, b: Uint256, c: Uint256) -> (res: Uint256):
    let (res: Uint256, _) = FullMath.uint256_mul_div(a, b, c)
    return (res)
end

@view
func uint256_mul_div_roundingup{
        syscall_ptr: felt*,
        pedersen_ptr: HashBuiltin*,
        range_check_ptr,
        bitwise_ptr: BitwiseBuiltin*
    } (a: Uint256, b: Uint256, c: Uint256) -> (res: Uint256):
    let (res: Uint256) = FullMath.uint256_mul_div_roundingup(a, b, c)
    return (res)
end

@view
func uint256_div_roundingup{
        syscall_ptr: felt*,
        pedersen_ptr: HashBuiltin*,
        range_check_ptr,
        bitwise_ptr: BitwiseBuiltin*
    } (a: Uint256, b: Uint256) -> (res: Uint256):
    let (res: Uint256) = FullMath.uint256_div_roundingup(a, b)
    return (res)
end