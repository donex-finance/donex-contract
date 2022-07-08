from starkware.cairo.common.uint256 import (Uint256, uint256_mul, uint256_shr, uint256_lt, uint256_add, uint256_unsigned_div_rem)
from starkware.cairo.common.bitwise import bitwise_and
from starkware.cairo.common.math_cmp import (is_nn, is_le)
from starkware.cairo.common.math import abs_value
from starkware.cairo.common.cairo_builtins import BitwiseBuiltin

namespace TickMath:
    # @dev The minimum tick that may be passed to #get_sqrt_ratio_at_tick computed from log base 1.0001 of 2**-128
    const MIN_TICK = -887272
    # @dev The maximum tick that may be passed to #get_sqrt_ratio_at_tick computed from log uint256_ltbase 1.0001 of 2**128
    const MAX_TICK = -MIN_TICK

    # @dev The minimum value that can be returned from #get_sqrt_ratio_at_tick. Equivalent to get_sqrt_ratio_at_tick(MIN_TICK)
    const MIN_SQRT_RATIO_LOW = 4295128739
    const MIN_SQRT_RATIO_HIGH = 0
    # @dev The maximum value that can be returned from #get_sqrt_ratio_at_tick. Equivalent to get_sqrt_ratio_at_tick(MAX_TICK)
    const MAX_SQRT_RATIO_LOW = 0xefd1fc6a506488495d951d5263988d26
    const MAX_SQRT_RATIO_HIGH = 0xfffd8963

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
        let (is_valid) = is_nn(bit - 0x80001)
        if is_valid == 1:
            return (ratio)
        end

        let (is_valid) = bitwise_and(abs_tick, bit)
        if is_valid != 0:
            let (arg) = get_sqrt_arg(bit)
            let (res1: Uint256, _) = uint256_mul(ratio, Uint256(arg, 0))
            #%{
            #    print(f"get_sqrt_price {ids.bit=} {ids.res1.low=}, {ids.res1.high=}")
            #    #breakpoint()
            #%}
            let (res2: Uint256) = uint256_shr(res1, Uint256(128, 0))
            #%{
            #    print(f"get_sqrt_price2 {ids.bit=} {ids.res2.low=}, {ids.res2.high=}")
            #    #breakpoint()
            #%}
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
        }(tick: felt) -> (res: Uint256): 

        alloc_locals

        let (abs_tick) = abs_value(tick)

        let (is_valid) = is_le(abs_tick, MAX_TICK)
        with_attr error_message("TickMath: abs_tick is too large"):
            assert is_valid = 1
        end

        let (local ratio: Uint256) = get_sqrt_ratio_at_tick_abs(abs_tick)

        let (is_valid) =  is_nn(tick)
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
            let (res3, _) = uint256_add(a, Uint256(1, 0))
            return (res=res3)
        end
        return (res=a)
    end
end