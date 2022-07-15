%lang starknet

from starkware.cairo.common.uint256 import (Uint256, uint256_mul, uint256_shr, uint256_shl, uint256_lt, uint256_le, uint256_add, uint256_unsigned_div_rem, uint256_signed_div_rem, uint256_or, uint256_sub, uint256_and, uint256_eq, uint256_signed_lt, uint256_neg, uint256_signed_nn)
from starkware.cairo.common.bitwise import (bitwise_and, bitwise_or)
from starkware.cairo.common.math import abs_value
from starkware.cairo.common.cairo_builtins import BitwiseBuiltin
from starkware.cairo.common.math_cmp import (is_nn, is_le)

from contracts.math_utils import Utils

namespace TickMath:

    # @dev The minimum tick that may be passed to #get_sqrt_ratio_at_tick computed from log base 1.0001 of 2**-128
    const MIN_TICK = -887272
    # @dev The maximum tick that may be passed to #get_sqrt_ratio_at_tick computed from log uint256_ltbase 1.0001 of 2**128
    const MAX_TICK = -MIN_TICK

    # @dev The minimum value that can be returned from #get_sqrt_ratio_at_tick. Equivalent to get_sqrt_ratio_at_tick(MIN_TICK)
    const MIN_SQRT_RATIO = 4295128739
    # @dev The maximum value that can be returned from #get_sqrt_ratio_at_tick. Equivalent to get_sqrt_ratio_at_tick(MAX_TICK)
    const MAX_SQRT_RATIO_LOW = 0xefd1fc6a506488495d951d5263988d26
    const MAX_SQRT_RATIO_HIGH = 0xfffd8963

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
        let (is_valid) = is_nn(0x80000 - bit)
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
        }(tick: felt) -> (price: Uint256): 

        alloc_locals

        let (abs_tick) = abs_value(tick)

        let (is_valid) = is_le(abs_tick, MAX_TICK)
        with_attr error_message("TickMath: abs_tick is too large"):
            assert is_valid = 1
        end

        let (ratio: Uint256) = get_sqrt_ratio_at_tick_abs(abs_tick)

        let (is_valid) = is_nn(tick)
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
            let (price: Uint256, _)= uint256_add(a, Uint256(1, 0))
            return (price)
        end
        return (a)
    end

    func most_significant_bit_2{
        range_check_ptr
    }(x: Uint256, r: felt, mask: Uint256, bit: felt) -> (new_x: Uint256, new_r: felt):
        let (is_valid) = uint256_le(mask, x)
        tempvar range_check_ptr = range_check_ptr
        if is_valid == 1:
            let (new_x: Uint256) = uint256_shr(x, Uint256(bit, 0))
            let new_r = r + bit
            return (new_x, new_r)
        end
        return (x, r)
    end

    func most_significant_bit{
            range_check_ptr
        }(num: Uint256) -> (r: felt):
        alloc_locals

        let (x: Uint256, r) = most_significant_bit_2(num, 0, Uint256(0, 1), 128)

        let (x: Uint256, r) = most_significant_bit_2(x, r, Uint256(0x10000000000000000, 0), 64)

        let (x: Uint256, r) = most_significant_bit_2(x, r, Uint256(0x100000000, 0), 32)

        let (x: Uint256, r) = most_significant_bit_2(x, r, Uint256(0x10000, 0), 16)

        let (x: Uint256, r) = most_significant_bit_2(x, r, Uint256(0x100, 0), 8)

        let (x: Uint256, r) = most_significant_bit_2(x, r, Uint256(0x10, 0), 4)

        let (x: Uint256, r) = most_significant_bit_2(x, r, Uint256(0x4, 0), 2)


        let (is_valid) = uint256_le(Uint256(0x2, 0), x)
        tempvar range_check_ptr = range_check_ptr
        if is_valid == 1:
            let r = r + 1
            return (r)
        end

        return (r)
    end

    # r is always > 0
    func log_step{
        range_check_ptr,
        bitwise_ptr: BitwiseBuiltin *
        } (r_in: Uint256, log_2_in: Uint256, shf_bit: felt) -> (r: Uint256, log_2: Uint256):

        alloc_locals

        let (is_valid) = Utils.is_lt(shf_bit, 50)
        if is_valid == 1:
            return (r_in, log_2_in)
        end

        let (low: Uint256, high: Uint256) = uint256_mul(r_in, r_in)

        let (r1: Uint256) = uint256_shr(low, Uint256(127, 0))

        local r: Uint256
        let (is_valid) = uint256_eq(high, Uint256(0, 0))
        if is_valid == 0:
            let (is_valid) = uint256_lt(high, Uint256(2 ** 127, 0))
            with_attr error_message("log_step overflow"):
                assert is_valid = 1
            end

            let (tmp: Uint256) = uint256_shl(high, Uint256(129, 0))
            let (tmp: Uint256, _) = uint256_add(r1, tmp)
            r.low = tmp.low
            r.high = tmp.high
            tempvar range_check_ptr = range_check_ptr
        else:
            r.low = r1.low
            r.high = r1.high
            tempvar range_check_ptr = range_check_ptr
        end

        let (f: Uint256) = uint256_shr(r, Uint256(128, 0))
        let (tmp: Uint256) = uint256_shl(f, Uint256(shf_bit, 0))
        let (log_2: Uint256) = uint256_or(log_2_in, tmp)
        let (r: Uint256) = uint256_shr(r, f)

        let (new_r: Uint256, new_log_2: Uint256) = log_step(r, log_2, shf_bit - 1)
        return (new_r, new_log_2)
    end

    func get_tick_at_sqrt_ratio{
        range_check_ptr,
        bitwise_ptr: BitwiseBuiltin*
        }(sqrt_price_x96: Uint256) -> (res: felt):
        alloc_locals

        local range_check_ptr = range_check_ptr

        let (is_valid) = uint256_le(Uint256(MIN_SQRT_RATIO, 0), sqrt_price_x96)
        with_attr error_message("tick is too low"):
            assert is_valid = 1
        end

        let (is_valid) = uint256_lt(sqrt_price_x96, Uint256(MAX_SQRT_RATIO_LOW, MAX_SQRT_RATIO_HIGH))
        with_attr error_message("tick is too high"):
            assert is_valid = 1
        end

        # change uint160 to uint192, to raise precision        
        let (ratio: Uint256) = uint256_shl(sqrt_price_x96, Uint256(32, 0))

        let (msb) = most_significant_bit(ratio)
        let (is_minus) = Utils.is_lt(msb, 128)
        if is_minus == 0:
            let (r: Uint256) = uint256_shr(ratio, Uint256(msb - 127, 0))
            tempvar range_check_ptr = range_check_ptr
        else: 
            let (r: Uint256) = uint256_shl(ratio, Uint256(127 - msb, 0))
            tempvar range_check_ptr = range_check_ptr
        end

        let (tmp: Uint256) = uint256_sub(Uint256(msb, 0), Uint256(128, 0))
        let (log_2: Uint256, _) = uint256_mul(tmp, Uint256(2 ** 64, 0))

        let (r: Uint256, log_2: Uint256) = log_step(r, log_2, 63)

        let (log_sqrt10001: Uint256, _) = uint256_mul(log_2, Uint256(255738958999603826347141, 0))

        let (t1: Uint256) = uint256_sub(log_sqrt10001, Uint256(0x28f6481ab7f045a5af012a19d003aaa, 0))

        let (tick_low: Uint256, _) = uint256_signed_div_rem(t1, Uint256(0, 1))

        let (t2: Uint256, _) = uint256_add(log_sqrt10001, Uint256(0xdb2df09e81959a81455e260799a0632f, 0))
        let (tick_high: Uint256, _) = uint256_signed_div_rem(t2, Uint256(0, 1))

        local tl
        let (not_negtive) = uint256_signed_nn(tick_low)
        if not_negtive == 0:
            let (res: Uint256) = uint256_neg(tick_low)
            tempvar res2 = -1 * res.low
            tl = res2
            tempvar range_check_ptr = range_check_ptr
        else:
            tl = tick_low.low
            tempvar range_check_ptr = range_check_ptr
        end

        local th
        let (not_negtive) = uint256_signed_nn(tick_high)
        if not_negtive == 0:
            let (res: Uint256) = uint256_neg(tick_high)
            tempvar res2 = -1 * res.low
            th = res2
            tempvar range_check_ptr = range_check_ptr
        else:
            th = tick_high.low
            tempvar range_check_ptr = range_check_ptr
        end

        let (is_valid) = uint256_eq(tick_low, tick_high)
        if is_valid == 0:
            let (res: Uint256) = get_sqrt_ratio_at_tick(th)
            let (is_valid) = uint256_le(res, sqrt_price_x96)
            if is_valid == 1:
                return (th)
            end
            return (tl)
        end

        return (tl)

    end

    # sqrt_price_x96 is Q64.96
    #func get_tick_at_sqrt_ratio{
    #    range_check_ptr,
    #    bitwise_ptr: BitwiseBuiltin*
    #    }(sqrt_price_x96: Uint256) -> (res: felt):
    #    alloc_locals

    #    local range_check_ptr = range_check_ptr

    #    let (is_valid) = uint256_le(Uint256(MIN_SQRT_RATIO, 0), sqrt_price_x96)
    #    with_attr error_message("tick is too low"):
    #        assert is_valid = 1
    #    end

    #    let (is_valid) = uint256_lt(sqrt_price_x96, Uint256(MAX_SQRT_RATIO_LOW, MAX_SQRT_RATIO_HIGH))
    #    with_attr error_message("tick is too high"):
    #        assert is_valid = 1
    #    end

    #    # change uint160 to uint192, to raise precision        
    #    let (ratio: Uint256) = uint256_shl(sqrt_price_x96, Uint256(32, 0))

    #    let (log2_ratio: Uint256) = log_2(ratio)
    #    %{ print(f"{ids.log2_ratio.low=}, {ids.log2_ratio.high=}")%}

    #    let (log_sqrt10001: Uint256) = uint256_mul_div(log2_ratio, Uint256(255738958999603826347141, 0), Uint256(2 ** 64, 0))
    #    %{ print(f"{ids.log_sqrt10001.low=} {ids.log_sqrt10001.high=}")%}

    #    let (t1: Uint256) = uint256_sub(log_sqrt10001, Uint256(0x28f6481ab7f045a5af012a19d003aaa, 0))

    #    let (tick_low: Uint256, _) = uint256_signed_div_rem(t1, Uint256(0, 1))
    #    %{ print(f"{ids.tick_low.low=} {ids.tick_low.high=}")%}

    #    let (t2: Uint256, _) = uint256_add(log_sqrt10001, Uint256(0xdb2df09e81959a81455e260799a0632f, 0))
    #    let (tick_high: Uint256, _) = uint256_signed_div_rem(t2, Uint256(0, 1))
    #    %{ print(f"{ids.tick_high.low=} {ids.tick_high.high=}")%}

    #    local tl
    #    let (not_negtive) = uint256_signed_nn(tick_low)
    #    if not_negtive == 0:
    #        let (res: Uint256) = uint256_neg(tick_low)
    #        tempvar res2 = -1 * res.low
    #        tl = res2
    #        %{ 
    #            print(f"{ids.res.low=}, {ids.res.high=}")
    #            breakpoint() 
    #        %}
    #        tempvar range_check_ptr = range_check_ptr
    #    else:
    #        tl = tick_low.low
    #        tempvar range_check_ptr = range_check_ptr
    #    end

    #    local th
    #    let (not_negtive) = uint256_signed_nn(tick_high)
    #    if not_negtive == 0:
    #        let (res: Uint256) = uint256_neg(tick_high)
    #        tempvar res2 = -1 * res.low
    #        th = res2
    #        %{ 
    #            print(f"{ids.res.low=}, {ids.res.high=}")
    #            breakpoint() 
    #        %}
    #        tempvar range_check_ptr = range_check_ptr
    #    else:
    #        th = tick_high.low
    #        tempvar range_check_ptr = range_check_ptr
    #    end

    #    let (is_valid) = uint256_eq(tick_low, tick_high)
    #    if is_valid == 0:
    #        let (res: Uint256) = get_sqrt_ratio_at_tick(tick_high.low)
    #        let (is_valid) = uint256_le(res, sqrt_price_x96)
    #        if is_valid == 1:
    #            return (th)
    #        end
    #        return (tl)
    #    end

    #    return (tl)
    #end
end