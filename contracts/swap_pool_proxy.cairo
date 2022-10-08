%lang starknet

from starkware.starknet.common.syscalls import library_call
from starkware.cairo.common.cairo_builtins import HashBuiltin, BitwiseBuiltin

from openzeppelin.upgrades.library import Proxy
from openzeppelin.access.ownable.library import Ownable

from contracts.interface.ISwapPool import ISwapPool

@constructor
func constructor{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    class_hash: felt,
    tick_spacing: felt, 
    fee: felt, 
    token_a: felt, 
    token_b: felt, 
    owner: felt 
) {
    Proxy._set_implementation_hash(class_hash);

    ISwapPool.library_call_initializer(class_hash=class_hash, tick_spacing=tick_spacing, fee=fee, token_a=token_a, token_b=token_b, owner=owner);
    return ();
}

@external
func upgrade{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    new_implementation : felt
) {
    Ownable.assert_only_owner();
    Proxy._set_implementation_hash(new_implementation);
    return ();
}

//
// Fallback functions
//
@external
@raw_input
@raw_output
func __default__{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr, bitwise_ptr: BitwiseBuiltin*}(
    selector: felt, calldata_size: felt, calldata: felt*
) -> (retdata_size: felt, retdata: felt*) {
    let (class_hash) = Proxy.get_implementation_hash();

    let (retdata_size: felt, retdata: felt*) = library_call(
        class_hash=class_hash,
        function_selector=selector,
        calldata_size=calldata_size,
        calldata=calldata,
    );
    return (retdata_size, retdata);
}