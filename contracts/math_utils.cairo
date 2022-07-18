%lang starknet

from starkware.cairo.common.math_cmp import (is_nn, is_le)

namespace Utils:
    # P = 2 ** 251 + 17 * (2 ** 192) + 1
    # const MAX_FELT_INT = 1809251394333065606848661391547535052811553607665798349986546028067936010240 # p // 2

    func is_eq(a: felt, b: felt) -> (res: felt):
        if a == b:
            return (1)
        end
        return (0)
    end

    func is_gt{
        range_check_ptr
        }(a: felt, b: felt) -> (res: felt): 

        let (is_valid) = is_nn(b - a)
        if is_valid == 1:
            return (0)
        end
        return (1)
    end

    func is_ge{
        range_check_ptr
        }(a: felt, b: felt) -> (res: felt):
        let (is_valid) = is_nn(a - b)
        return (is_valid)
    end

    func is_lt{
        range_check_ptr
        }(a: felt, b: felt) -> (res: felt):
        let (is_valid) = is_nn(a - b)
        if is_valid == 0:
            return (1)
        end
        return (0)
    end

    # 0 <= res < 2 ** 128
    func u128_safe_add{
        range_check_ptr
        }(a: felt, b: felt) -> (res: felt):

        let res = a + b
        let (is_valid) = is_nn(res)
        with_attr error_message("safe_add: minus result"):
            assert is_valid = 1
        end

        let (is_valid) = is_le(res, 0xffffffffffffffffffffffffffffffff)
        with_attr error_message("safe_add: overflow"):
            assert is_valid = 1
        end

        return (res)
    end
end