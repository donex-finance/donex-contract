%lang starknet

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
    
    func update_position{
            range_check_ptr
        }(
            position: PositionInfo,
            liquidity_delta: felt,
            fee_growth_inside0_x128: Uint256,
            fee_growth_inside1_x128: Uint256,
        ):

        if liquidity_delta == 0:
            let (is_valid) = Utils.is_gt(position.liquidity, 0)
            with_attr error_message("disallow pokes for 0 liquidity positions"):
                assert is_valid = 1
            end
            tempvar liquidity_next = 0
        else:
            let (tmp) = Utils.u128_safe_add(position.liquidity, liquidity_delta)
            tempvar liquidity_next = tmp
        end

        let (tokens_owed0: Uint256) = FullMath.uint256_mul_div(uint256_sub(fee_growth_inside0_x128, position.fee_growth_inside0_x128)[0], position.liquidity, Uint256(0, 1))
        let (tokens_owed1: Uint256) = FullMath.uint256_mul_div(uint256_sub(fee_growth_inside1_x128, position.fee_growth_inside1_x128)[0], position.liquidity, Uint256(0, 1))

        if liquidity_delta != 0:
            position.liquidity = liquidity_next
        end

        position.fee_growth_inside0_x128 = fee_growth_inside0_x128
        position.fee_growth_inside1_x128 = fee_growth_inside1_x128

        let (tmp) = uint256_lt(Uint256(0, 0), tokens_owed0)
        let (tmp2) = uint256_lt(Uint256(0, 0), tokens_owed1)
        let is_valid = Utils.is_lt(0, tmp + tmp2)
        if is_valid == 1:
            #TODO: if tokens_owed* < 0
            position.tokens_owed0 = tokens_owed0.low
            position.tokens_owed1 = tokens_owed1.low
        end

        return ()
    end

    func get{
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