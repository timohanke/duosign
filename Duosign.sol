/*
The MIT License (MIT)

Copyright (c) 2017 DFINITY Stiftung 

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
*/

/**
 * @title:  Duo-signing wallet.
 * @author: Timo Hanke <timo.t.hanke@gmail.com> (twitter: @timothanke)
 *
 * This contract is a minimalistic and easy-to-use "two-sig" wallet.
 * It has two or more owners and each action requires exactly two owners to
 * sign.
 *
 * Actions are:
 *  - forward funds
 *  - add owner
 *  - remove owner
 *
 * Usage:
 *  - The proposal and subsequent confirmation by the second owner are two
 *    identical calls, just made from different sender addresses.
 *  - Each action is identified by a unique nonce that can be arbitrarily chosen
 *    by the users. The two signers have to use the same nonce.
 *
 * The contract is intentionally reduced to a minimal feature set:
 *  - The signature "threshold" is not configurable, it is always 2.
 *  - There is no handling of transaction payload (data), only pure value 
 *    transfers.
 */

pragma solidity ^0.4.6;

contract Duosign {
  enum TxType {
    FWD,  // forward eth
    ADD,  // add owner
    DEL   // remove owner
  }

  enum State {
    EMPTY, // no tx initialized
    OPEN,  // tx proposed
    DONE   // tx executed
  }

  struct Transaction {
    TxType  txType;
    address addr;
    uint    value;
  }

  mapping(address => bool) public isOwner;
  mapping(uint32 => Transaction) public proposalByNonce;
  mapping(uint32 => address) public proposerByNonce;
  mapping(uint32 => State) public stateByNonce; 

  uint public nOwners;

  address[] public ownerList;  // all owners, former and current ones
  uint32[] public nonceList;   // all nonces that are in non-EMPTY state

  /**
   * Constructor
   *
   * The constructor initializes the set of owners.
   *
   * Note that the deployer is not by default an owner.
   */
  function Duosign(address[] _owners) {
     for (uint i = 0; i < _owners.length; ++i)
       toggleOwner(_owners[i], true); 
  }

  /**
   * Default function
   *
   * By default do nothing but accepting the value.
   */
  function() payable { }

  /**
   * Modifiers
   *
   * onlyowner - the sender must be an owner
   * dedup     - the nonce must be either new or related to an in-progress
   *             transaction that was opened by another owner
   */

  modifier onlyowner {
    if (!isOwner[msg.sender]) { throw; } 
    _;
  }

  modifier dedup(uint32 nonce) {
    if (stateByNonce[nonce] == State.DONE) { throw; } 
    if (stateByNonce[nonce] == State.OPEN && proposerByNonce[nonce] == msg.sender) { throw; }
    _;
  }

  /**
   * Public functions
   *
   * Actions. These functions have to be called twice by different owners.
   *  forward - forward value out of the contract 
   *  add     - add an owner to the contract
   *  del     - remove an owner of the contract
   *  ren     - replace an owner by a different one
   *
   * Non-actions. These functions can be called by a single owner.
   *  cancel  - cancel a proposed action before it is executed
   */

  /**
   * Actions.
   *
   * These functions build a Transaction struct of the corresponding type and
   * pass it to the issue function along with the nonce. The issue function
   * takes care of the rest.
   */

  function forward(address to, uint value, uint32 nonce) onlyowner dedup(nonce) public {
    issue(Transaction(TxType.FWD, to, value), nonce);
  }

  function add(address owner, uint32 nonce) onlyowner dedup(nonce) public {
    issue(Transaction(TxType.ADD, owner, 0), nonce);
  }

  function del(address owner, uint32 nonce) onlyowner dedup(nonce) public {
    issue(Transaction(TxType.DEL, owner, 0), nonce);
  }

  /**
   * A proposer can cancel its own proposal before it got executed.
   * The state of the nonce is simply advanced to DONE without executing it.
   * The nonce can not be re-used anymore.
   */
  function cancel(uint32 nonce) public {
    if (proposerByNonce[nonce] != msg.sender) { throw; }

    stateByNonce[nonce] = State.DONE;
  }

  /*
   * Internal functions
   * 
   * sameParameters - check if a new Transaction matches a previous proposal
   * issue          - opens a proposal (if Transaction is new) or calls execute
   * execute        - executes Transaction according to its type
   * toggleOwner    - add or remove an owner
   */

  function sameParameters(Transaction a, Transaction b) internal constant returns (bool) {
    return (a.txType == b.txType && a.addr == b.addr && a.value == b.value);
  }

  function issue(Transaction newTx, uint32 nonce) internal {
    // first appearance of nonce?
    if (stateByNonce[nonce] == State.EMPTY) {
      // store Transaction as a proposal
      proposerByNonce[nonce] = msg.sender;
      proposalByNonce[nonce] = newTx;
      stateByNonce[nonce] = State.OPEN;
      nonceList.push(nonce);
      return;
    } else {  // repeated appearance of nonce
      // get the previous proposal
      Transaction memory proposal = proposalByNonce[nonce];
      // new transaction must match proposal
      if (!sameParameters(newTx, proposal)) { throw; }
      // adjust state & execute
      stateByNonce[nonce] = State.DONE;
      execute(proposal);
    }
  }

  function execute(Transaction tx) internal {
    // case "forward value"
    if (tx.txType == TxType.FWD) {
      bool success = tx.addr.call.value(tx.value)();
      if (!success) { throw; } 
    }
    // case "add owner"
    else if (tx.txType == TxType.ADD) {
      toggleOwner(tx.addr, true);
    }
    // case "remove owner"
    else if (tx.txType == TxType.DEL) { 
      // require at least two remaining owners
      if (nOwners <= 2) { throw; }
      toggleOwner(tx.addr, false);
    }
  }

  function toggleOwner(address addr, bool add) internal {
    // throw if owner to be added already existed
    // throw if owner to be removed does not existed
    if (isOwner[addr] == add) { throw; }

    // add new owner
    if (add) { 
      nOwners++; 
      ownerList.push(addr);
    } else { 
      nOwners--; }
    isOwner[addr] = add;
  }
}
