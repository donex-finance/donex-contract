%lang starknet

from starkware.cairo.common.math_cmp import is_nn

namespace Utils:
    # P = 2 ** 251 + 17 * (2 ** 192) + 1
    const RANGE_BOUND = 1809251394333065606848661391547535052811553607665798349986546028067936010240 # p // 2

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
        let (is_valid) = is_nn(b - a)
        if is_valid == 1:
            return (1)
        end
        return (0)
    end
end