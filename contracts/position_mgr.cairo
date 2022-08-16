%lang starknet

from starkware.cairo.common.cairo_builtins import (HashBuiltin, BitwiseBuiltin)
from starkware.cairo.common.uint256 import (Uint256, uint256_lt, uint256_sub)

from contracts.fullmath import FullMath
from contracts.math_utils import Utils

struct PositionInfo:
    member liquidity: felt
    member fee_growth_inside0_x128: Uint256
    member fee_growth_inside1_x128: Uint256
    member tokens_owed0: felt
    member tokens_owed1: felt
end

@storage_var
func _positions(address: felt, tick_lower: felt, tick_high: felt) -> (position: PositionInfo):
end

namespace PositionMgr:

    func _update_position_1{
            range_check_ptr
        }(
            liquidity_delta: felt,
            liquidity: felt
        ) -> (res: felt):
        if liquidity_delta == 0:
            let (is_valid) = Utils.is_gt(liquidity, 0)
            with_attr error_message("disallow pokes for 0 liquidity positions"):
                assert is_valid = 1
            end
            return (liquidity)
        end

        let (liquidity_next) = Utils.u128_safe_add(liquidity, liquidity_delta)
        return (liquidity_next)
    end
    
    func update_position{
            range_check_ptr,
            bitwise_ptr: BitwiseBuiltin*
        }(
            position: PositionInfo,
            liquidity_delta: felt,
            fee_growth_inside0_x128: Uint256,
            fee_growth_inside1_x128: Uint256,
        ) -> (new_position: PositionInfo):

        alloc_locals

        let (liquidity) = _update_position_1(liquidity_delta, position.liquidity)

        let (tmp256: Uint256) = uint256_sub(fee_growth_inside0_x128, position.fee_growth_inside0_x128)
        let (tmp256_2: Uint256, _) = FullMath.uint256_mul_div(tmp256, Uint256(position.liquidity, 0), Uint256(0, 1))
        let tokens_owed0 = tmp256_2.low

        let (tmp256: Uint256) = uint256_sub(fee_growth_inside1_x128, position.fee_growth_inside1_x128)
        let (tmp256_2: Uint256, _) = FullMath.uint256_mul_div(tmp256, Uint256(position.liquidity, 0), Uint256(0, 1))
        let tokens_owed1 = tmp256_2.low

        let (tmp) = Utils.is_lt(0, tokens_owed0)
        let (tmp2) = Utils.is_lt(0, tokens_owed1)
        let (is_valid) = Utils.is_lt(0, tmp + tmp2)
        if is_valid == 1:
            #TODO: if tokens_owed* < 0
            return (PositionInfo(liquidity=liquidity, fee_growth_inside0_x128=fee_growth_inside0_x128, fee_growth_inside1_x128=fee_growth_inside1_x128, tokens_owed0=tokens_owed0, tokens_owed1=tokens_owed1))
        end

        return (PositionInfo(liquidity=liquidity, fee_growth_inside0_x128=fee_growth_inside0_x128, fee_growth_inside1_x128=fee_growth_inside1_x128, tokens_owed0=position.tokens_owed0, tokens_owed1=position.tokens_owed1))
    end

    func get{
            syscall_ptr: felt*,
            pedersen_ptr: HashBuiltin*,
            range_check_ptr
        }(
            address: felt,
            tick_lower: felt,
            tick_high: felt
        ) -> (position: PositionInfo):
        let (position: PositionInfo) = _positions.read(address, tick_lower, tick_high)
        return (position)
    end

end