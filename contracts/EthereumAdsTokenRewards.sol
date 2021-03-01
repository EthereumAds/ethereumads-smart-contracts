// SPDX-License-Identifier: agpl-3.0

pragma solidity >=0.6.0 <0.8.0;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts-upgradeable/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/Initializable.sol";
import "./libs/NativeMetaTransaction.sol";
import "./libs/ContextMixin.sol";
import "./libs/IERC20MintableUpgradeable.sol";
import "./EthereumAdsLib.sol";

/**
    @title Contract for distributing EthereumAds (EAD) tokens to every entity using the service.
    @author EthereumAds Team
*/
contract EthereumAdsTokenRewards is Initializable, AccessControlUpgradeable, NativeMetaTransaction, ContextMixin {
    using SafeMathUpgradeable for uint;
    using SafeERC20Upgradeable for IERC20MintableUpgradeable;

    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant BURNER_ROLE = keccak256("BURNER_ROLE");

    uint[] public rewardValues;
    uint public mintedAmount; // needed because withdrawing to rootChain would decrease totalSupply and allow further minting
    uint public cap;

    address public validatorPoolsAddr;
    address public eadTokenAddr;
    
    IERC20MintableUpgradeable eadToken;
    IEthereumAdsValidatorPools eadValidatorPools;
    IEthereumAds ethereumAds;

    // events not necessary since rewards are temporary and ERC20 events are sufficient

    function initialize(address _ethereumAdsAddr, address _validatorPoolsAddr, uint _cap) public initializer {
        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
        setupEthereumAds(_ethereumAdsAddr);
        setupValidatorPoolsAddr(_validatorPoolsAddr);
        setupCap(_cap);
        _initializeEIP712('EthereumAdsTokenRewards', '1');
    }


    // external functions

    function rewardMint(EthereumAdsLib.Entities memory entities, uint[] memory valPools) external returns(bool) {
        require(hasRole(MINTER_ROLE, _msgSender()), "CALLER IS NOT A MINTER");

        address[6] memory recipients = [entities.campaignOwner, entities.campaignAff, entities.publisher, entities.publisherAff, entities.platform, entities.platformAff];

        if (rewardValues[0] == 0) {
            return false;
        }

        address tempRecipient;
        for (uint i=0; i<6; i++) {
            if (recipients[i] != address(0)) {
                tempRecipient = recipients[i];
            } else {
                if (i == 1) {
                    tempRecipient = entities.campaignOwner; // no campaignAff -> campaignOwner
                } else if (i == 3) {
                    tempRecipient = entities.publisher; // no publisherAff -> publisher
                } else if (i == 4) {
                    tempRecipient = entities.publisher; // no platform -> publisher
                } else if (i == 5) {
                    if (entities.platform != address(0)) {
                        tempRecipient = entities.platform; // no platformAff -> platform
                    } else {
                        tempRecipient = entities.publisher; // no platformAff -> publisher
                    }
                }
            }
            mint(tempRecipient, rewardValues[i]);
        }

        uint amount = mint(address(this), rewardValues[6]); 
        if (amount == 0) {
            return true;
        }

        for (uint i=0; i<valPools.length; i++) {
            uint valCom = ethereumAds.signerCommission();
            address validator = eadValidatorPools.signerRecipient(valPools[i]);
            
            uint amount1 = amount.mul(valCom).div(100).div(valPools.length);
            eadToken.transfer(validator, amount1);

            uint amount2 = amount.mul(uint(100).sub(valCom)).div(100).div(valPools.length);

            eadToken.approve(validatorPoolsAddr, amount2);
            eadValidatorPools.depositEAD(valPools[i], address(this), amount2);
        }

        return true;
    } 


    // public functions

    function updateEadToken() public {
        eadTokenAddr = ethereumAds.eadAddr();
        eadToken = IERC20MintableUpgradeable(eadTokenAddr);
    }


    function setupValidatorPoolsAddr(address _validatorPoolsAddr) public {
        require(hasRole(DEFAULT_ADMIN_ROLE, _msgSender()), "NOT ADMIN");
        validatorPoolsAddr = _validatorPoolsAddr;
        eadValidatorPools = IEthereumAdsValidatorPools(_validatorPoolsAddr);
    }


    function setupEthereumAds(address _ethereumAdsAddr) public {
        require(hasRole(DEFAULT_ADMIN_ROLE, _msgSender()), "NOT ADMIN");
        _setupRole(MINTER_ROLE, _ethereumAdsAddr);
        _setupRole(BURNER_ROLE, _ethereumAdsAddr);
        ethereumAds = IEthereumAds(_ethereumAdsAddr);
    }


    function setupCap(uint _cap) public {
        require(hasRole(DEFAULT_ADMIN_ROLE, _msgSender()), "NOT ADMIN");
        cap = _cap;
    }


    function setupRewardValues(uint[] memory _rewardValues) public {
        require(hasRole(DEFAULT_ADMIN_ROLE, _msgSender()), "NOT ADMIN");
        rewardValues = _rewardValues;
    }


    function mint(address _to, uint _amount) public returns(uint) {
        if (_to == address(0) || _amount == 0) {
            return 0;
        }

        require(hasRole(MINTER_ROLE, _msgSender()), "CALLER IS NOT A MINTER");
      
        if (mintedAmount.add(_amount) > cap) {
            _amount = cap.sub(mintedAmount);
        }
 
        mintedAmount = mintedAmount.add(_amount);
        assert(mintedAmount <= cap);

        eadToken.mint(_to, _amount);

        return _amount;
    }


    function burn(address _from, uint _amount) public {
        require(hasRole(BURNER_ROLE, _msgSender()), "CALLER IS NOT A BURNER");
        eadToken.burn(_from, _amount);
    }
    

    // internal functions

    function _msgSender() override internal view returns (address payable sender) {
        return ContextMixin.msgSender();
    }
}
