// SPDX-License-Identifier: agpl-3.0

pragma solidity >=0.6.0 <0.8.0;

contract QueueAddress {
    mapping(uint => bytes32) queue;
    uint public first = 1;
    uint public last = 0;

    function enqueue(bytes32 data) public {
        last += 1;
        queue[last] = data;
    }

    function dequeue() public returns (bytes32) {
        //require(last >= first);  // non-empty queue
        if (first > last) {
            return bytes32(0);
        }

        bytes32 data = queue[first];

        delete queue[first];
        first += 1;
        return data;
    }

    function firstItem() public view returns (bytes32) {
        //require(last >= first);  // non-empty queue
        if (first > last) {
            return bytes32(0);
        }

        return queue[first];
    }
}