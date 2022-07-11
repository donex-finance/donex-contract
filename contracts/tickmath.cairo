%lang starknet

from starkware.cairo.common.uint256 import (Uint256, uint256_mul, uint256_shr, uint256_lt, uint256_le, uint256_add, uint256_unsigned_div_rem)
from starkware.cairo.common.bitwise import (bitwise_and, bitwise_or)
from starkware.cairo.common.math import abs_value
from starkware.cairo.common.cairo_builtins import BitwiseBuiltin

from contracts.math_utils import Utils

namespace TickMath:

    const MAX_INT = 1809251394333065606848661391547535052811553607665798349986546028067936010240

    # @dev The minimum tick that may be passed to #get_sqrt_ratio_at_tick computed from log base 1.0001 of 2**-128
    const MIN_TICK = -887272
    # @dev The maximum tick that may be passed to #get_sqrt_ratio_at_tick computed from log uint256_ltbase 1.0001 of 2**128
    const MAX_TICK = -MIN_TICK

    # @dev The minimum value that can be returned from #get_sqrt_ratio_at_tick. Equivalent to get_sqrt_ratio_at_tick(MIN_TICK)
    const MIN_SQRT_RATIO = 4295128739
    # @dev The maximum value that can be returned from #get_sqrt_ratio_at_tick. Equivalent to get_sqrt_ratio_at_tick(MAX_TICK)
    const MAX_SQRT_RATIO = 1461446703485210103287273052203988822378723970342

    const TWO127 = 0x80000000000000000000000000000000
    const TWO128_1 = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF


    func get_sqrt_arg{
            range_check_ptr,
        } (bit: felt) -> (res: felt):
        if bit == 0x2:
            return (0xfff97272373d413259a46990580e213a)
        end
        if bit == 0x4:
            return (0xfff2e50f5f656932ef12357cf3c7fdcc)
        end
        if bit == 0x8:
            return (0xffe5caca7e10e4e61c3624eaa0941cd0)
        end
        if bit == 0x10:
            return (0xffcb9843d60f6159c9db58835c926644)
        end
        if bit == 0x20:
            return (0xff973b41fa98c081472e6896dfb254c0)
        end
        if bit == 0x40:
            return (0xff2ea16466c96a3843ec78b326b52861)
        end
        if bit == 0x80:
            return (0xfe5dee046a99a2a811c461f1969c3053)
        end
        if bit == 0x100:
            return (0xfcbe86c7900a88aedcffc83b479aa3a4)
        end
        if bit == 0x200:
            return (0xf987a7253ac413176f2b074cf7815e54)
        end
        if bit == 0x400:
            return (0xf3392b0822b70005940c7a398e4b70f3)
        end
        if bit == 0x800:
            return (0xe7159475a2c29b7443b29c7fa6e889d9)
        end
        if bit == 0x1000:
            return (0xd097f3bdfd2022b8845ad8f792aa5825)
        end
        if bit == 0x2000:
            return (0xa9f746462d870fdf8a65dc1f90e061e5)
        end
        if bit == 0x4000:
            return (0x70d869a156d2a1b890bb3df62baf32f7)
        end
        if bit == 0x8000:
            return (0x31be135f97d08fd981231505542fcfa6)
        end
        if bit == 0x10000:
            return (0x9aa508b5b7a84e1c677de54f3e99bc9)
        end
        if bit == 0x20000:
            return (0x5d6af8dedb81196699c329225ee604)
        end
        if bit == 0x40000:
            return (0x2216e584f5fa1ea926041bedfe98)
        end
        if bit == 0x80000:
            return (0x48a170391f7dc42444e8fa2)
        end

        # revert
        assert bit = 0x2
        return (0)
    end


    func get_sqrt_price{
            range_check_ptr,
            bitwise_ptr: BitwiseBuiltin*
        }(ratio: Uint256, abs_tick: felt, bit: felt) -> (res: Uint256):
        alloc_locals
        # check if bit > 0x80000
        let (is_valid) = Utils.is_nn(0x80000 - bit)
        if is_valid == 0:
            return (ratio)
        end

        let (is_valid) = bitwise_and(abs_tick, bit)
        if is_valid != 0:
            let (arg) = get_sqrt_arg(bit)
            let (res1: Uint256, _) = uint256_mul(ratio, Uint256(arg, 0))
            let (res2: Uint256) = uint256_shr(res1, Uint256(128, 0))
            let (res3: Uint256) = get_sqrt_price(res2, abs_tick, bit * 2)
            return (res3)
        end

        let (res: Uint256) = get_sqrt_price(ratio, abs_tick, bit * 2)
        return (res)
    end

    func get_sqrt_ratio_at_tick_abs{
            range_check_ptr,
            bitwise_ptr: BitwiseBuiltin*
        }(abs_tick: felt) -> (res: Uint256): 
        let (is_valid) = bitwise_and(abs_tick, 0x1)

        if is_valid != 0:
            let res1 = Uint256(0xfffcb933bd6fad37aa2d162d1a594001, 0)
            let (res2: Uint256) = get_sqrt_price(res1, abs_tick, 0x2)
            return (res2)
        end
        
        let (res: Uint256) = get_sqrt_price(Uint256(0, 1), abs_tick, 0x2)
        return (res)
    end

    func get_sqrt_ratio_at_tick{
            range_check_ptr,
            bitwise_ptr: BitwiseBuiltin*
        }(tick: felt) -> (price: felt): 

        alloc_locals

        let (abs_tick) = abs_value(tick)

        let (is_valid) = Utils.is_le(abs_tick, MAX_TICK)
        with_attr error_message("TickMath: abs_tick is too large"):
            assert is_valid = 1
        end

        let (local ratio: Uint256) = get_sqrt_ratio_at_tick_abs(abs_tick)

        let (is_valid) = Utils.is_nn(tick)
        if is_valid == 1:
            let (tmp: Uint256, _) = uint256_unsigned_div_rem(Uint256(0xffffffffffffffffffffffffffffffff, 0xffffffffffffffffffffffffffffffff), ratio)
            tempvar ratio2 = tmp
            tempvar range_check_ptr = range_check_ptr
        else:
            tempvar ratio2 = ratio
            tempvar range_check_ptr = range_check_ptr
        end

        # this divides by 1<<32 rounding up to go from a Q128.128 to a Q128.96.
        # we then downcast because we know the result always fits within 160 bits due to our tick input constraint
        # we round up in the division so getTickAtSqrtRatio of the output price is always consistent

        let (a, r) = uint256_unsigned_div_rem(ratio2, Uint256(2**32, 0))
        let (is_valid) = uint256_lt(Uint256(0, 0), r)
        if is_valid == 1:
            let price = a.low + 1 + a.high  * (2 ** 128)
            return (price)
        end
        let price = a.low + a.high * (2 ** 128)
        return (price)
    end

    #func mostSignificantBit{
    #        range_check_ptr
    #    }(num: felt) -> (r: felt):
    #    alloc_locals

    #    let (is_valid) = Utils.is_gt(num, 0)
    #    assert is_valid = 1

    #    tempvar x = num
    #    tempvar r = 0

    #    let (is_valid) = Utils.is_ge(x, 0x100000000000000000000000000000000)
    #    tempvar range_check_ptr = range_check_ptr
    #    if is_valid == 1:
    #        %{ ids.x = ids.x >> 128 %}
    #        tempvar r = r + 128
    #        tempvar range_check_ptr = range_check_ptr
    #    end

    #    tempvar r2 = r
    #    let (is_valid) = Utils.is_ge(x, 0x10000000000000000)
    #    #tempvar range_check_ptr = range_check_ptr
    #    if is_valid == 1:
    #        %{ ids.x = ids.x >> 64 %}
    #        tempvar range_check_ptr = range_check_ptr
    #        tempvar r2 = r + 64
    #        #tempvar range_check_ptr = range_check_ptr
    #    end

    #    let (is_valid) = Utils.is_ge(x, 0x100000000)
    #    tempvar range_check_ptr = range_check_ptr
    #    if is_valid == 1:
    #        %{ ids.x = ids.x >> 32 %}
    #        tempvar r = r + 32
    #        tempvar range_check_ptr = range_check_ptr
    #    end

    #    let (is_valid) = Utils.is_ge(x, 0x10000)
    #    tempvar range_check_ptr = range_check_ptr
    #    if is_valid == 1:
    #        %{ ids.x = ids.x >> 16 %}
    #        tempvar r = r + 16
    #        tempvar range_check_ptr = range_check_ptr
    #    end

    #    let (is_valid) = Utils.is_ge(x, 0x100)
    #    tempvar range_check_ptr = range_check_ptr
    #    if is_valid == 1:
    #        %{ ids.x = ids.x >> 8 %}
    #        tempvar r = r + 8
    #        tempvar range_check_ptr = range_check_ptr
    #    end

    #    let (is_valid) = Utils.is_ge(x, 0x10)
    #    tempvar range_check_ptr = range_check_ptr
    #    if is_valid == 1:
    #        %{ ids.x = ids.x >> 4 %}
    #        tempvar r = r + 4
    #        tempvar range_check_ptr = range_check_ptr
    #    end

    #    let (is_valid) = Utils.is_ge(x, 0x4)
    #    tempvar range_check_ptr = range_check_ptr
    #    if is_valid == 1:
    #        %{ ids.x = ids.x >> 2 %}
    #        tempvar r = r + 2
    #        tempvar range_check_ptr = range_check_ptr
    #    end

    #    let (is_valid) = Utils.is_ge(x, 0x2)
    #    tempvar range_check_ptr = range_check_ptr
    #    if is_valid == 1:
    #        tempvar r = r + 1
    #        tempvar range_check_ptr = range_check_ptr
    #    end

    #    return (r)
    #end

    func mostSignificantBit{
            range_check_ptr
        }(num: felt) -> (r: felt):
        alloc_locals

        let (is_valid) = Utils.is_gt(num, 0)
        assert is_valid = 1

        local x
        local r

        %{
            tx = ids.num
            tr = 0
            if tx >= 0x100000000000000000000000000000000:
                tx >>= 128
                tr += 128

            if tx >= 0x10000000000000000:
                tx >>= 64
                tr += 64

            if tx >= 0x100000000:
                tx >>= 32
                tr += 32

            if tx >= 0x10000:
                tx >>= 16
                tr += 16

            if tx >= 0x100:
                tx >>= 8
                tr += 8

            if tx >= 0x10:
                tx >>= 4
                tr += 4

            if tx >= 0x4:
                tx >>= 2
                tr += 2

            if tx >= 0x2:
                tr += 1

            ids.x = tx
            ids.r = tr
        %}

        return (r)
    end

    func _log_2_recur{
        range_check_ptr,
        bitwise_ptr: BitwiseBuiltin*
        }(bit: felt, x: felt, index: felt, result: felt) -> (res: felt):
        alloc_locals

        let (is_valid) = Utils.is_lt(index, 128)
        if is_valid == 0:
            return (result)
        end

        tempvar nx = 0
        %{ ids.nx = (x << 1) + ((x * x + ids.TWO127) >> 128) %}
        let (is_valid) = Utils.is_gt(x, TWO128_1)

        local new_res = result
        if is_valid == 1:
            let (new_res2) = bitwise_or(result, bit)
            local new_res = new_res2
            tempvar range_check_ptr = range_check_ptr
            tempvar bitwise_ptr: BitwiseBuiltin* = bitwise_ptr
            %{ ids.nx = (ids.nx >> 1) - TWO127 %}
            let (is_valid) = Utils.is_gt(x, 0)
            if is_valid == 1:
                return (new_res)
            end
        end
        tempvar new_bit = bit
        %{ ids.new_bit = bit >> 1 %}

        let (res) = _log_2_recur(new_bit, nx, index + 1, new_res)
        return (res)
    end

    func get_right_num_from_hint{
        range_check_ptr
    }(is_minus: felt, num: felt) -> (res: felt):
        if is_minus == 1:
            let res = num * -1
            return (res)
        end
        return (num)
    end

    # num is Q128.96
    func log_2{
        range_check_ptr,
        bitwise_ptr: BitwiseBuiltin*
        }(num: felt) -> (res: felt, is_minus: felt):
        alloc_locals

        let (is_valid) = Utils.is_gt(num, 0)
        assert is_valid = 1

        let (local msb) = mostSignificantBit(num)

        local x

        # check if msb > 128
        let (is_minus) = Utils.is_lt(msb, 128)
        if is_valid == 0:
            %{ 
                ids.x = ids.num >> (ids.msb - 128) 
            %}
            tempvar range_check_ptr = range_check_ptr
        else: 
            %{ 
                ids.x = ids.num << (128 - ids.msb) 
            %}
            tempvar range_check_ptr = range_check_ptr
        end

        let (local x2) = bitwise_and(x, TWO128_1)

        local res2
        %{ 
            res = (ids.msb - 128) << 128 
            if (res < 0):
                P = 2 ** 251 + 17 * (2 ** 192) + 1
                res = P - res
            # TODO: if res < 0, ids.res2 only got the abs(res), why?
            ids.res2 = res
        %}

        let (res3) = get_right_num_from_hint(is_minus, res2)

        #let (res4) = _log_2_recur(TWO127, x, res2)
        local res4
        %{        
            bit = ids.TWO127
            x = ids.x2
            res = ids.res3
            P = 2 ** 251 + 17 * (2 ** 192) + 1
            if ids.is_minus == 1:
                res = -1 * (P - res)
            for i in range(128):
                x = (x << 1) + ((x * x + ids.TWO127) >> 128)
                if x > ids.TWO128_1:
                    res |= bit
                    x = (x >> 1) - ids.TWO127
                bit = bit >> 1
                #print('log_2:', i, x, bit, res)
                if x <= 0:
                    break
            if res < 0:
                res = P - res
            ids.res4 = res
        %}

        let (res5) = get_right_num_from_hint(is_minus, res4)
        return (res5, is_minus)
    end

    # sqrt_price_x96 is Q64.96
    func get_tick_at_sqrt_ratio{
        range_check_ptr,
        bitwise_ptr: BitwiseBuiltin*
        }(sqrt_price_x96: felt) -> (res: felt):
        alloc_locals

        let (is_valid) = Utils.is_le(MIN_SQRT_RATIO, sqrt_price_x96)
        with_attr error_message("tick is too low"):
            assert is_valid = 1
        end

        let (is_valid) = Utils.is_gt(MAX_SQRT_RATIO, sqrt_price_x96)
        with_attr error_message("tick is too high"):
            assert is_valid = 1
        end

        # change uint160 to uint192, to raise precision        
        let ratio = sqrt_price_x96 * (2 ** 32)

        let (log2_ratio, is_minus) = log_2(ratio)
        tempvar range_check_ptr = range_check_ptr
        tempvar bitwise_ptr: BitwiseBuiltin* = bitwise_ptr

        local log_sqrt10001
        # TODO: precision in python
        %{ 
            log2_ratio = ids.log2_ratio
            P = 2 ** 251 + 17 * (2 ** 192) + 1
            if ids.is_minus == 1:
                log2_ratio = -1 * (P - log2_ratio)
            log_sqrt10001 = (log2_ratio * 255738958999603826347141 >> 64) 
            if log_sqrt10001 < 0:
                log_sqrt10001 = P - log_sqrt10001
            ids.log_sqrt10001 = log_sqrt10001
        %}

        let (log_sqrt10001_correction) = get_right_num_from_hint(is_minus, log_sqrt10001)

        local tick_low
        local tick_high
        %{ 
            P = 2 ** 251 + 17 * (2 ** 192) + 1
            log_sqrt10001_correction = ids.log_sqrt10001_correction
            if ids.is_minus == 1:
                log_sqrt10001_correction = -1 * (P - log_sqrt10001_correction)

            tick_low = (log_sqrt10001_correction - 3402992956809132418596140100660247210) >> 128 
            if tick_low < 0:
                tick_low = P - tick_low
            ids.tick_low = tick_low

            tick_high = (log_sqrt10001_correction + 291339464771989622907027621153398088495) >> 128 
            if tick_high < 0:
                tick_high = P - tick_high
            ids.tick_high = tick_high
        %}

        let (local tick_low_correction) = get_right_num_from_hint(is_minus, tick_low)
        let (local tick_high_correction) = get_right_num_from_hint(is_minus, tick_high)


        if tick_low_correction != tick_high_correction:
            let (price) = get_sqrt_ratio_at_tick(tick_high_correction)
            tempvar range_check_ptr = range_check_ptr
            tempvar bitwise_ptr: BitwiseBuiltin* = bitwise_ptr
            let (is_valid) = Utils.is_le(price, sqrt_price_x96)
            tempvar range_check_ptr = range_check_ptr
            tempvar bitwise_ptr: BitwiseBuiltin* = bitwise_ptr
            if is_valid == 1:
                return (tick_high_correction)
            else:
                tempvar range_check_ptr = range_check_ptr
                tempvar bitwise_ptr: BitwiseBuiltin* = bitwise_ptr
            end
        else:
            tempvar range_check_ptr = range_check_ptr
            tempvar bitwise_ptr: BitwiseBuiltin* = bitwise_ptr
        end

        return (tick_low_correction)
    end
end