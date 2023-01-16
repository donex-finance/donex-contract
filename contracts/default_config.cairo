%lang starknet

namespace Config {
    // default fee, this means the protocol will get the 20%(1 / 5) of all the swap fee
    const DEFAULT_FEE = 2000;

    // swap_fee_rate / SWAP_FEE_FACTOR
    const SWAP_FEE_FACTOR = 10000;
}