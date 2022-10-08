%lang starknet

from starkware.starknet.common.syscalls import library_call
from starkware.cairo.common.cairo_builtins import HashBuiltin, BitwiseBuiltin

from openzeppelin.upgrades.library import Proxy
from openzeppelin.access.ownable.library import Ownable

@constructor
func constructor{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    class_hash: felt
    //owner: felt,
    //swap_pool_hash: felt
) {
    Proxy._set_implementation_hash(class_hash);


    // call intializer
    // TODO: selector
    //let (local calldata: felt*) = alloc();
    //assert calldata[0] = owner;
    //assert calldata[1] = swap_pool_hash;
    //library_call(
    //    class_hash=class_hash,
    //    function_selector='',
    //    calldata_size=2,
    //    calldata=calldata,
    //);
    return ();
}

// TODO: test
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