// SPDX-License-Identifier: agpl-3.0

pragma solidity >=0.6.0 <0.8.0;

contract QueueUint {
    mapping(uint => uint) queue;
    uint public first = 1;
    uint public last = 0;

    function enqueue(uint data) public {
        last += 1;
        queue[last] = data;
    }

    function dequeue() public returns (uint) {
        //require(last >= first);  // non-empty queue
        if (first > last) {
            return 0;
        }

        uint data = queue[first];

        delete queue[first];
        first += 1;
        return data;
    }

    function firstItem() public view returns (uint) {
        //require(last >= first);  // non-empty queue
        if (first > last) {
            return 0;
        }

        return queue[first];
    }

    function size() public view returns (uint) {
        if (first > last) {
            return 0;
        } 
        return last-first+1;   
    }
 }