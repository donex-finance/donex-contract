%lang starknet

namespace Utils:
    # P = 2 ** 251 + 17 * (2 ** 192) + 1
    const RANGE_BOUND = 1809251394333065606848661391547535052811553607665798349986546028067936010240 # p // 2

    func is_nn{
        range_check_ptr
        }(a) -> (res: felt): 
        alloc_locals
        local res
        %{
            res = 1
            if (ids.a % PRIME) > ids.RANGE_BOUND: 
                res = 0
            ids.res = res
        %}
        return (res)
        #%{ memory[ap] = 0 if 0 <= (ids.a % PRIME) < ids.RANGE_BOUND else 1 %}
        #jmp out_of_range if [ap] != 0; ap++
        #[range_check_ptr] = a
        #let range_check_ptr = range_check_ptr + 1
        #return (res=1)

        #out_of_range:
        #%{ memory[ap] = 0 if 0 <= ((-ids.a - 1) % PRIME) < ids.RANGE_BOUND else 1 %}
        #jmp need_felt_comparison if [ap] != 0; ap++
        #assert [range_check_ptr] = (-a) - 1
        #let range_check_ptr = range_check_ptr + 1
        #return (res=0)

        #need_felt_comparison:
        #assert_le_felt(RANGE_BOUND, a)
        #return (res=0)
    end

    func is_le{
        range_check_ptr
        }(a, b) -> (res : felt):

        return is_nn(b - a)
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
        let (is_valid) = is_nn(b - a)
        if is_valid == 1:
            return (1)
        end
        return (0)
    end
end