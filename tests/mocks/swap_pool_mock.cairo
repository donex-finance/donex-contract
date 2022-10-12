%lang starknet

from starkware.starknet.common.syscalls import library_call
from starkware.cairo.common.cairo_builtins import HashBuiltin, BitwiseBuiltin

from starkware.cairo.common.uint256 import Uint256

from openzeppelin.upgrades.library import Proxy
from openzeppelin.access.ownable.library import Ownable

from contracts.interface.ISwapPool import ISwapPool

@storage_var
func _fee_growth_global0_x128() -> (fee_growth_global_0x128: Uint256) {
}

@storage_var
func _fee_growth_global1_x128() -> (fee_growth_global_1x128: Uint256) {
}

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

@external
func set_fee_growth_global0_x128{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    value: Uint256 
) {
    _fee_growth_global0_x128.write(value);
    return (); 
}

@external
func set_fee_growth_global1_x128{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    value: Uint256 
) {
    _fee_growth_global1_x128.write(value);
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