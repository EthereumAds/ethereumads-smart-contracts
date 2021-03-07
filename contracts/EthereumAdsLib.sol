// SPDX-License-Identifier: agpl-3.0

pragma solidity >=0.6.0 <0.8.0;
pragma experimental ABIEncoderV2;

import "./libs/QueueUint.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";

/**
    @title Contains shared structs, functions and interfaces
    @author EthereumAds Team
*/
library EthereumAdsLib {

    struct Entities {
        address platform;
        address platformAff;
        address publisher;
        address publisherAff;

        uint campaign;

        ////
        address campaignAff;
        address campaignOwner;
    }

    struct TransferPacket {
        address receiver;
        uint value;
    }

    struct Pool {
        string name;    
        string validatorInfoJSON; // gunPublicKey, endpoint, pool

        address admin;
        address signerRecipient;
        address[] signers;

        uint vptTotalSupply;
        uint eadTotalSupply;

        bool stakingAllowed;

        mapping(address => uint) scaledCompensationPerToken;
        mapping(address => uint) scaledRemainder;
        mapping(address => uint) unlockTime;
        mapping(address => uint) vptBalanceOf;
        mapping(address => mapping(address => uint)) scaledCompensationVptBalanceOf; 
        mapping(address => mapping(address => uint)) scaledCompensationCreditedTo;
    }

    struct Campaign {
        address owner;
        address affiliate;
        address tokenAddr;

        bool paused; 

        uint valPool;
        uint cpc; 
        uint timeframe;
        uint clicksPerTimeframe;

        string advertJSON;

        QueueUint transferQueue;
        IERC20Upgradeable token;
    }



    function isStringEmpty(string memory _emptyStringTest) internal pure returns(bool) {
        bytes memory tempEmptyStringTest = bytes(_emptyStringTest);
        return tempEmptyStringTest.length == 0;
    }


    // proposal: O(nn) can be reduced to O(n)
    function countUnique(uint[] memory _array) internal pure returns (uint) {
        uint count = 0;
        uint[] memory processed = new uint[](_array.length);
        uint j=0;
        for (uint i=0; i < _array.length; i++) {
            if (!isUintInArray(processed, _array[i])) {
                processed[j] = _array[i];
                j++;
                count++;
            }
        }
        return count;
    }


    function isUintInArray(uint[] memory _array, uint a) internal pure returns(bool) {
        bool res = false;
        for (uint i = 0; i < _array.length; i++) {
            if (_array[i] == a) {
                res = true;
            }
        }
        return res;
    }


    function arraysEqual(uint[] memory a, uint[] memory b) internal pure returns(bool) {
        if (a.length != b.length) {
            return false;
        }

        for (uint i = 0; i < a.length; i++) {
            if (a[i] != b[i]) {
                return false;
            }
        }
        return true;
    }


    function countNonZero(uint[] memory _arr) internal pure returns(uint) {
        uint count = 0; 
        for (uint i=0; i<_arr.length; i++) {
            if (_arr[i] != 0) {
                count++;
            }
        }
        return count;
    }


    function insertIntoArray(uint[] memory _arr, uint _addr) internal pure returns(bool) {
        for (uint i=0; i<_arr.length; i++) {
            if (_arr[i] == 0) {
                _arr[i] = _addr;
                return true;
            }
        }
        return false;
    }


    function concatenateUintArrays(uint[] memory _array1, uint[] memory _array2) internal pure returns(uint[] memory) {
        uint[] memory returnArr = new uint[](_array1.length + _array2.length);

        uint i=0;
        for (; i < _array1.length; i++) {
            returnArr[i] = _array1[i];
        }

        uint j=0;
        while (j < _array1.length) {
            returnArr[i++] = _array2[j++];
        }
        return returnArr;
    } 


    function isAddressInArray(address[] memory _array, address a) internal pure returns(bool) {
        bool res = false;
        for (uint i=0; i<_array.length; i++) {
            if (_array[i] == a) {
                res = true;
            }
        }
        return res;
    }
}


interface IEthereumAdsTokenRewards {
    function rewardMint(EthereumAdsLib.Entities memory entities, uint[] memory valPools) external returns(bool);
    function updateEadToken() external;
}

interface IEthereumAdsValidatorPools {
    function slash(uint n, uint _amount) external;
    function validatorInfoJSON(uint n) external view returns(string memory);
    function eadTotalSupply(uint n) external view returns(uint);
    function signerRecipient(uint n) external view returns(address);
    function isSigner(uint n, address addr) external view returns(bool);
    function deposit(uint n, address token, uint value) external;
    function depositEAD(uint n, address from, uint value) external;
    function updateEadToken() external;
}

interface IEthereumAdsCampaigns {
    function transferRequirements(uint n) external view returns(bool);
    function transferMult(uint n, EthereumAdsLib.TransferPacket[] memory transferPackets) external returns(bool);
    function getCampaign(uint n) external view returns(EthereumAdsLib.Campaign memory);
}

interface IEthereumAds {
    function validatorPoolSetUpdate(uint n) external;
    function slashAddr() external returns(address);
    function eadAddr() external returns(address);
    function signerCommission() external returns(uint);
    function getTokenWhiteList() external view returns(address[] memory);
}