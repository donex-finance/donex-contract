%lang starknet

struct Slot0:
    member sqrtPrice: felt
    member tick: felt
    member oIndex: felt
    member ocNext: felt
    member feeProtocol: felt
    member unlocked: felt
end

@constructor
func constructor{}()
