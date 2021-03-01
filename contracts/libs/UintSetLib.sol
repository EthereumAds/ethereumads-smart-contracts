// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0 <0.8.0;

/* 
    Modified by EthereumAds Team from:
    Hitchens UnorderedAddressSet v0.93
    Library for managing CRUD operations in dynamic uint sets.
    https://github.com/rob-Hitchens/UnorderedKeySet
    Copyright (c), 2019, Rob Hitchens, the MIT License
*/

library UintSetLib {
    
    struct Set {
        mapping(uint => uint) keyPointers;
        uint[] keyList;
    }
    

    function insert(Set storage self, uint key) internal {
        require(key != uint(0), "UintSetLib(100) - Key cannot be 0x0");
        require(!exists(self, key), "UintSetLib(101) - Address (key) already exists in the set.");
        self.keyList.push(key);
        self.keyPointers[key] = self.keyList.length-1;
    }
    

    function remove(Set storage self, uint key) internal {
        require(exists(self, key), "UintSetLib(102) - Address (key) does not exist in the set.");
        uint keyToMove = self.keyList[count(self)-1];
        uint rowToReplace = self.keyPointers[key];
        self.keyPointers[keyToMove] = rowToReplace;
        self.keyList[rowToReplace] = keyToMove;
        delete self.keyPointers[key];

        self.keyList.pop();
    }


    function clear(Set storage self) internal {
        while(count(self) > 0) {
            remove(self, keyAtIndex(self, count(self) - 1));
        }
    }


    function count(Set storage self) internal view returns(uint) {
        return(self.keyList.length);
    }


    function exists(Set storage self, uint key) internal view returns(bool) {
        if(self.keyList.length == 0) return false;
        return self.keyList[self.keyPointers[key]] == key;
    }


    function keyAtIndex(Set storage self, uint index) internal view returns(uint) {
        return self.keyList[index];
    }


    function toArray(Set storage self) internal view returns(uint[] memory) {
        uint[] memory result = new uint[](count(self));
        for (uint i=0; i<count(self); i++) {
            result[i] = keyAtIndex(self, i);
        }
        return result;
    }
}