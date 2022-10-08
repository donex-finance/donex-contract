"""Utilities for testing Cairo contracts."""

import os
import sys
from pathlib import Path
import math
import time
from starkware.starknet.public.abi import get_selector_from_name
from starkware.starknet.compiler.compile import compile_starknet_files
from starkware.starkware_utils.error_handling import StarkException
from starkware.starknet.testing.starknet import StarknetContract
from starkware.starknet.business_logic.execution.objects import Event
from nile.signer import Signer
from inspect import signature
from starkware.starknet.testing.starknet import Starknet
from mpmath import mp, sqrt
mp.dps = 100


MAX_UINT256 = (2**128 - 1, 2**128 - 1)
MAX_UINT128 = 2 ** 128 - 1
INVALID_UINT256 = (MAX_UINT256[0] + 1, MAX_UINT256[1])
ZERO_ADDRESS = 0
TRUE = 1
FALSE = 0

PRECISION = 200

TRANSACTION_VERSION = 0

P = 2 ** 251 + 17 * (2 ** 192) + 1
MAX_FELT_INT = 1809251394333065606848661391547535052811553607665798349986546028067936010240

class FeeAmount:
  LOW = 500
  MEDIUM = 3000
  HIGH = 10000

TICK_SPACINGS = {
  FeeAmount.LOW: 10,
  FeeAmount.MEDIUM: 60,
  FeeAmount.HIGH: 200,
}

_root = Path(__file__).parent.parent


def contract_path(name):
    if name.startswith("tests/"):
        return str(_root / name)
    else:
        return str(_root / "src" / name)


def str_to_felt(text):
    b_text = bytes(text, "ascii")
    return int.from_bytes(b_text, "big")


def felt_to_str(felt):
    b_felt = felt.to_bytes(31, "big")
    return b_felt.decode()


def uint(a):
    return(a, 0)


def to_uint(a):
    """Takes in value, returns uint256-ish tuple."""
    return (a & ((1 << 128) - 1), a >> 128)


def from_uint(uint):
    """Takes in uint256-ish tuple, returns value."""
    return uint[0] + (uint[1] << 128)


def add_uint(a, b):
    """Returns the sum of two uint256-ish tuples."""
    a = from_uint(a)
    b = from_uint(b)
    c = a + b
    return to_uint(c)


def sub_uint(a, b):
    """Returns the difference of two uint256-ish tuples."""
    a = from_uint(a)
    b = from_uint(b)
    c = a - b
    return to_uint(c)


def mul_uint(a, b):
    """Returns the product of two uint256-ish tuples."""
    a = from_uint(a)
    b = from_uint(b)
    c = a * b
    return to_uint(c)


def div_rem_uint(a, b):
    """Returns the quotient and remainder of two uint256-ish tuples."""
    a = from_uint(a)
    b = from_uint(b)
    c = math.trunc(a / b)
    m = a % b
    return (to_uint(c), to_uint(m))

def felt_to_int(a):
    if a > MAX_FELT_INT:
        return a - P
    return a

async def assert_revert(fun, reverted_with=None):
    try:
        await fun
        assert False
    except StarkException as err:
        _, error = err.args
        if reverted_with is not None:
            assert reverted_with in error['message']


def assert_event_emitted(tx_exec_info, from_address, name, data):
    assert Event(
        from_address=from_address,
        keys=[get_selector_from_name(name)],
        data=data,
    ) in tx_exec_info.raw_events


def get_contract_def(path):
    """Returns the contract definition from the contract path"""
    path = contract_path(path)
    contract_def = compile_starknet_files(
        files=[path],
        debug_info=True
    )
    return contract_def


def cached_contract(state, definition, deployed):
    """Returns the cached contract"""
    contract = StarknetContract(
        state=state,
        abi=definition.abi,
        contract_address=deployed.contract_address,
        deploy_call_info=deployed.deploy_call_info
    )
    return contract


class TestSigner():
    """
    Utility for sending signed transactions to an Account on Starknet.

    Parameters
    ----------

    private_key : int

    Examples
    ---------
    Constructing a TestSigner object

    >>> signer = TestSigner(1234)

    Sending a transaction

    >>> await signer.send_transaction(
            account, contract_address, 'contract_method', [arg_1]
        )

    Sending multiple transactions

    >>> await signer.send_transaction(
            account, [
                (contract_address, 'contract_method', [arg_1]),
                (contract_address, 'another_method', [arg_1, arg_2])
            ]
        )
                           
    """
    def __init__(self, private_key):
        self.signer = Signer(private_key)
        self.public_key = self.signer.public_key
        
    async def send_transaction(self, account, to, selector_name, calldata, nonce=None, max_fee=0):
        return await self.send_transactions(account, [(to, selector_name, calldata)], nonce, max_fee)

    async def send_transactions(self, account, calls, nonce=None, max_fee=0):
        if nonce is None:
            execution_info = await account.get_nonce().call()
            nonce, = execution_info.result

        build_calls = []
        for call in calls:
            build_call = list(call)
            build_call[0] = hex(build_call[0])
            build_calls.append(build_call)

        (call_array, calldata, sig_r, sig_s) = self.signer.sign_transaction(hex(account.contract_address), build_calls, nonce, max_fee)
        return await account.__execute__(call_array, calldata, nonce).execute(signature=[sig_r, sig_s])

#def encode_price_sqrt(reserve1, reserve2):
#    """
#    Encode the price sqrt as a uint256.
#    """
#    a = Context(prec=PRECISION).create_decimal(reserve1)
#    b = Context(prec=PRECISION).create_decimal(reserve2)
#    c = Context(prec=PRECISION).create_decimal(2 ** 96)
#    a = (a / b).sqrt() * c
#    return to_uint(int(a))

def encode_price_sqrt(reserve1, reserve2):
    a = mp.mpf(reserve1)
    b = mp.mpf(reserve2)
    c = sqrt((a / b)) * mp.mpf(2 ** 96)
    return to_uint(int(c))

def expand_to_18decimals(n):
    return n * (10 ** 18)

def int_to_felt(n):
    if n < 0:
        return P + n
    return n

def get_min_tick(tick_spacing):
    return math.ceil(-887272 / tick_spacing) * tick_spacing

def get_max_tick(tick_spacing):
    return math.floor(887272 / tick_spacing) * tick_spacing

async def init_contract(contract_file, constructor_calldata=None, starknet=None):
    if not starknet:
        starknet = await Starknet.empty()
    begin = time.time()
    compiled_contract = compile_starknet_files(
        [contract_file], debug_info=True, disable_hint_validation=True
    )
    print('compile contract time:', time.time() - begin)

    kwargs = {
        "contract_class": compiled_contract,
        "constructor_calldata": constructor_calldata
        }

    begin = time.time()
    contract = await starknet.deploy(**kwargs)
    print('deploy contract time:', time.time() - begin)

    return compiled_contract, contract

class Account:
    """
    Utility for deploying Account contract.

    Parameters
    ----------

    public_key : int

    Examples
    ----------

    >>> starknet = await State.init()
    >>> account = await Account.deploy(public_key)

    """
    #sys.path.append(os.path.join(Path(__file__).parent, 'library'))
    path = 'tests/mocks/Account.cairo'
    get_class = compile_starknet_files(
        files=[path],
        debug_info=True
    )

    async def deploy(public_key):
        starknet = await Starknet.empty()
        account = await starknet.deploy(
            contract_class=Account.get_class,
            constructor_calldata=[public_key]
        )
        return account