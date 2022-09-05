%lang starknet

from starkware.cairo.common.cairo_builtins import (HashBuiltin, BitwiseBuiltin)
from starkware.cairo.common.uint256 import (Uint256, uint256_le, uint256_add)

from library.openzeppelin.token.erc721.IERC721 import IERC721

from contracts.interface.IERC721Mintable import IERC721Mintable
from contracts.interface.ISwapPool import ISwapPool
from contracts.tickmath import TickMath

struct UserPosition:
    member pool_address: felt
    member owner: felt
    member tick_lower: felt
    member tick_upper: felt
end

@storage_var
func _token_id() -> (res: Uint256):
end

@storage_var
func _positions(token_id: Uint256) -> (position: UserPosition):
end

@storage_var
func _erc721_contract() -> (address: felt):
end

@event
func IncreaseLiquidity(token_id: Uint256, liquidity: felt, amount0: Uint256, amount1: Uint256):
end

@constructor
func constructor{
        syscall_ptr: felt*,
        pedersen_ptr: HashBuiltin*,
        range_check_ptr
    }():
    return ()
end

#@view
#func get_user_positions{
#        syscall_ptr: felt*,
#        pedersen_ptr: HashBuiltin*,
#        range_check_ptr
#    }(address: felt):
#end

@view
func get_erc721_contract{
        syscall_ptr: felt*,
        pedersen_ptr: HashBuiltin*,
        range_check_ptr
    }() -> (address: felt):
    let (address) = _erc721_contract.read()
    return (address)
end

@external
func intialize{
        syscall_ptr: felt*,
        pedersen_ptr: HashBuiltin*,
        range_check_ptr
    }(erc721_contract: felt):
    # only can be initilize once
    let (old) = _erc721_contract.read()
    with_attr error_message("user_position_mgr: only can be initilize once"):
        assert old = 0
    end

    _erc721_contract.write(erc721_contract)
    return ()
end

func _get_pool_address{
        syscall_ptr: felt*,
        pedersen_ptr: HashBuiltin*,
        range_check_ptr
    }(
        token0: felt,
        token1: felt,
        fee: felt
    ) -> (address: felt):
    # TODO: get the pool address
    return (0)
end

func _get_mint_liuqidity{
        syscall_ptr: felt*,
        pedersen_ptr: HashBuiltin*,
        range_check_ptr
    }(
        pool_address: felt, 
        tick_lower: felt, 
        tick_upper: felt, 
        amount0_desired: Uint256, 
        amount1_desired: Uint256
    ) -> (liquidity: felt):
    alloc_locals

    let (sqrt_price_x96: Uint256, _) = IswapPool.get_cur_slot(contract_address=pool_address)
    let (sqrtRatioA: Uint256) = TickMath.get_sqrt_ratio_at_tick(tick_lower)
    let (sqrtRatioB: Uint256) = TickMath.get_sqrt_ratio_at_tick(tick_upper)

    let (liquidity) = LiquidityAmounts.get_liquidity_for_amounts(
        sqrt_price_x96,
        sqrtRatioA,
        sqrtRatioB,
        amount0_desired,
        amount1_desired
    )

    return (liquidity)
end

@external
func add_liquidity{
        syscall_ptr: felt*,
        pedersen_ptr: HashBuiltin*,
        range_check_ptr
    }(
        recipient: felt,
        token0: felt,
        token1: felt,
        fee: felt,
        tick_lower: felt,
        tick_upper: felt,
        amount0_desired: Uint256,
        amount1_desired: Uint256,
        amount0_min: Uint256,
        amount1_min: Uint256
    ):
    alloc_locals

    let (cur_token_id: Uint256) = _token_id.read()
    let (new_token_id: Uint256, _) = uint256_add(cur_token_id, Uint256(1, 0))
    _token_id.write(new_token_id)

    # mint position
    # get the pool address
    let (pool_address) = _get_pool_address(token0, token1, fee)

    # remote call the add_liquidity function
    let (liquidity) = _get_mint_liuqidity(pool_address, tick_lower, tick_upper, amount0_desired, amount1_desired)

    let (amount0: Uint256, amount1: Uint256) = ISwapPool.add_liquidity(
        contract_address=pool_address,
        recipient=recipient,
        tick_lower=tick_lower,
        tick_upper=tick_upper,
        liquidity=liquidity)
    let (flag1) = uint256_le(amount0_min, amount0)
    let (flag2) = uint256_le(amount1_min, amount1)
    let flag = flag1 + flag2
    with_attr error_message("price slippage check"):
        assert flag = 2
    end

    # mint the erc721
    let (erc721_contract) = _erc721_contract.read()
    IERC721Mintable.mint(
        contract_address=erc721_contract,
        to=recipient, 
        tokenId=cur_token_id
    )

    # write the position
    let position = UserPosition(
        pool_address=pool_address,
        owner=recipient,
        tick_lower=tick_lower,
        tick_upper=tick_upper
    )
    _positions.write(new_token_id, position)

    IncreaseLiquidity.emit(new_token_id, liquidity, amount0, amount1)

    return ()
end
