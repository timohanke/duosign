# Two-signature Ethereum wallet

## Overview

This contract is a minimalistic and easy-to-use "two-sig" wallet.
It has two or more owners and each action requires exactly two owners to
sign.

Actions are:

 - forward funds
 - add owner
 - remove owner

Usage:

 - The proposal and subsequent confirmation by the second owner are two
   identical calls, just made from different sender addresses.
 - Each action is identified by a unique nonce that can be arbitrarily chosen
   by the users. The two signers have to use the same nonce.

The contract is intentionally reduced to a minimal feature set:

 - The signature "threshold" is not configurable, it is always 2.
 - There is no handling of transaction payload (data), only pure value 
   transfers.

## Example

Contract is deployed with
`Duosign([addr1, addr2, addr3])`.

User1 with `addr1` issues `forward(addr4, 10**18, 7)` where `10**18` means 1 ether and `7` is an arbitrarily chosen nonce.
User1 sends the nonce to User2.

User2 with `addr2` issues `forward(addr4, 10**18, 7)`. The transaction gets executed only if all parameters match (destination address, value and nonce).
