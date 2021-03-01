// SPDX-License-Identifier: agpl-3.0

pragma solidity >=0.6.0 <0.8.0;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "./libs/UintSetLib.sol";
import "./libs/NativeMetaTransaction.sol";
import "./libs/ContextMixin.sol";
import "./libs/QueueAddress.sol";
import "./EthereumAdsLib.sol";


/**
    @title Main contract for processing click events and assigning validator subsets
    @author EthereumAds Team
*/
contract EthereumAds is Initializable, AccessControlUpgradeable, NativeMetaTransaction, ContextMixin {

    using SafeMathUpgradeable for uint;
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using UintSetLib for UintSetLib.Set;

    mapping(address => Platform) public platforms;
    mapping(address => Participant) participants;
    mapping(address => uint) minimumCpc;
    mapping(address => bool) tokenApproval;
    mapping(bytes32 => Click) public clicks; 
    mapping(bytes32 => bool) public ips;
    mapping(string => address) public affiliates;

    address[] public tokenWhiteList;

    QueueAddress clicksQueue;

    address public eadAddr;
    address public eadTokenRewardsAddr;
    address public slashAddr;
    address public validatorPoolsAddr;
    address public campaignsAddr;

    uint public minimumValidatorStake;
    uint public slashingAmount;
    uint public inactivityTimeout;

    uint8 public validatorPoolCommission;
    uint8 public signerCommission;

    IERC20Upgradeable eadToken;
    UintSetLib.Set validatorSet;

    IEthereumAdsTokenRewards eadTokenRewards;
    IEthereumAdsValidatorPools eadValidatorPools;
    IEthereumAdsCampaigns eadCampaigns;

    struct Platform {
        string name;
        uint8 commission;
    }

    struct Participant {
        uint[] validators;
    }

    struct Click {
        uint[] approvals; 
        uint[] disapprovals;
        uint[] validatorSet;
        bool clickCounted;
        uint timestamp;
    }

    event LogProcessClick(
        address indexed platform,
        address indexed publisher,
        address indexed advertiser,
        uint campaign,
        string clickDataJSON,
        bool rewardable,
        bytes32 clickId,
        bool confirmed
    );

    // used to overcome "indexed" limit of 3 per event
    event LogProcessClickAffiliate(
        address indexed platformAffiliate,
        address indexed publisherAffiliate,
        address indexed advertiserAffiliate,
        uint campaign,
        string clickDataJSON,
        bool rewardable,
        bytes32 clickId,
        bool confirmed
    );

    event LogSetPlatform(
        address indexed platform,
        string indexed platformName,
        uint8 platformCommission
    );
    
    event LogSetAffiliate(
        string indexed affiliateName,
        address indexed affiliate
    );

    event LogSetTokenApproval(
        address indexed token,
        bool approval
    );

    event LogChangeSettings(
        address eadAddr,
        address eadTokenRewardsAddr,
        address validatorPoolsAddr,
        address campaignsAddr,
        address slashAddr,
        uint8 validatorPoolCommission,
        uint8 signerCommission,
        uint minimumValidatorStake,
        uint slashingAmount,
        uint inactivityTimeout
    );

    event LogValidatorPoolSetChange(
        uint pool,
        uint value,
        bool insertion
    );

    event LogValidatorAssignment(
        address indexed addr,
        string indexed userType,
        uint[] valPools,
        string[] validatorInfoJSON
    );


    function initialize(address _admin, address _eadAddr, address _eadTokenRewardsAddr, address _campaignsAddr, address _validatorPoolsAddr, address _slashAddr, uint8 _validatorPoolCommission, uint8 _signerCommission, uint _minimumValidatorStake, uint _slashingAmount) public initializer {
        _setupRole(DEFAULT_ADMIN_ROLE, _admin);
        eadAddr = _eadAddr;
        eadToken = IERC20Upgradeable(_eadAddr);

        eadTokenRewardsAddr = _eadTokenRewardsAddr;
        eadTokenRewards = IEthereumAdsTokenRewards(eadTokenRewardsAddr);
        eadTokenRewards.updateEadToken();
    

        validatorPoolsAddr = _validatorPoolsAddr;
        eadValidatorPools = IEthereumAdsValidatorPools(_validatorPoolsAddr);
        eadValidatorPools.updateEadToken();

        campaignsAddr = _campaignsAddr;
        eadCampaigns = IEthereumAdsCampaigns(_campaignsAddr);

        slashAddr = _slashAddr;
        validatorPoolCommission = _validatorPoolCommission;
        signerCommission = _signerCommission;

        minimumValidatorStake = _minimumValidatorStake;
        slashingAmount = _slashingAmount;

        inactivityTimeout = 60 seconds;

        clicksQueue = new QueueAddress();
        _initializeEIP712('EthereumAds', '1');
    }


    // external functions

    function changeSettings(address _eadAddr, address _eadTokenRewardsAddr, address _validatorPoolsAddr, address _campaignsAddr, address _slashAddr, uint8 _validatorPoolCommission, uint8 _signerCommission, uint _minimumValidatorStake, uint _slashingAmount, uint _inactivityTimeout) external {
        require(hasRole(DEFAULT_ADMIN_ROLE, _msgSender()), "NOT ADMIN");
        require(_validatorPoolCommission <= 100, "COMMISSION GREATER THAN 100");
        if (_eadAddr != address(0)) { // beware not to mess up pools
            eadAddr = _eadAddr;
            eadToken = IERC20Upgradeable(_eadAddr);
            eadValidatorPools.updateEadToken();
            eadTokenRewards.updateEadToken();
        }
        if (_eadTokenRewardsAddr != address(0)) {
            eadTokenRewardsAddr = _eadTokenRewardsAddr;
            eadTokenRewards = IEthereumAdsTokenRewards(_eadTokenRewardsAddr);
        }
        if (_validatorPoolsAddr != address(0)) {
            validatorPoolsAddr = _validatorPoolsAddr;
            eadValidatorPools = IEthereumAdsValidatorPools(_validatorPoolsAddr);
        }
        if (_campaignsAddr != address(0)) {
            campaignsAddr = _campaignsAddr;
            eadCampaigns = IEthereumAdsCampaigns(_campaignsAddr);
        }
        if (_slashAddr != address(0)) {
            slashAddr = _slashAddr;
        }
        if (_validatorPoolCommission != 0) {
            validatorPoolCommission = _validatorPoolCommission;
        }
        if (_signerCommission != 0) {
            signerCommission = _signerCommission;
        }
        if (_minimumValidatorStake != 0) {
            minimumValidatorStake = _minimumValidatorStake;
        }
        if (_slashingAmount != 0) {
            slashingAmount = _slashingAmount;
        }      
        if (_inactivityTimeout != 0) {
            inactivityTimeout = _inactivityTimeout;
        }   
        emit LogChangeSettings(_eadAddr, _eadTokenRewardsAddr, _validatorPoolsAddr, _campaignsAddr, _slashAddr, _validatorPoolCommission, _signerCommission, _minimumValidatorStake, _slashingAmount, _inactivityTimeout);
    }


    function setTokenApproval(address _tokenAddr, uint _minimumCpc, bool _approval) external {
        require(hasRole(DEFAULT_ADMIN_ROLE, _msgSender()), "NOT ADMIN");
        tokenApproval[_tokenAddr]  = _approval; 
        minimumCpc[_tokenAddr] = _minimumCpc;
        if (_approval) {
            whitelistTokens(_tokenAddr);
        }
        emit LogSetTokenApproval(_tokenAddr, _approval);
    }


    function getValidatorSubSetInfo(address _publisher, address _advertiser) external view returns(string[] memory) {
        uint[] memory pValPools = getValPool(_publisher);
        uint[] memory aValPools = getValPool(_advertiser);
        uint[] memory valPools = EthereumAdsLib.concatenateUintArrays(pValPools, aValPools);
        return getValidatorInfoJSON(valPools);
    }


    function setPlatform(string memory _platformName, uint8 _platformCommission) external {
        require(_platformCommission <= 50, "COMMISSION GREATER THAN 50");
        platforms[_msgSender()] = Platform(_platformName, _platformCommission);
        emit LogSetPlatform(_msgSender(), _platformName, _platformCommission);
    } 
    

    function setAffiliate(string memory _affiliateName) external {
        affiliates[_affiliateName] = _msgSender();
        emit LogSetAffiliate(_affiliateName, _msgSender());
    } 


    /**
        @notice Called by each validator subset node to process a click event received from the adviewer
        @dev Resolves affiliate names to addresses and calls processClick
    */
    function processClickWithAffiliateNames(address _platform, string memory _platformAffName, address _publisher, string memory _publisherAffName, uint _campaign, uint _pValPool, uint _pool, string memory _clickDataJSON, bytes32 _ipHash, bool _rewardable, bool _approved) external returns(bool) {
        EthereumAdsLib.Entities memory entities = EthereumAdsLib.Entities(_platform, affiliates[_platformAffName], _publisher, affiliates[_publisherAffName], _campaign, address(0), address(0));
        return processClick(entities, _pValPool, _pool, _clickDataJSON, _ipHash, _rewardable, _approved);
    }


    function getTokenWhiteList() external view returns(address[] memory) {
        return tokenWhiteList;
    }


    /** 
        @notice Called by validatorPools contract when EAD tokens are staked, unstaked or slashed in order to include or remove the validator pool
                from the public validator set if its stake exceeds or falls short of the minimumValidatorStake respectively.
    */
    function validatorPoolSetUpdate(uint n) external {
        require(_msgSender() == validatorPoolsAddr, "NOT VALIDATORPOOLS");
        uint value = eadValidatorPools.eadTotalSupply(n);
        if (value >= minimumValidatorStake) {
            if (!validatorSet.exists(n)) {
                validatorSet.insert(n);
                emit LogValidatorPoolSetChange(n, value, true);
            }
        } else {
            if (validatorSet.exists(n)) {
                validatorSet.remove(n);
                emit LogValidatorPoolSetChange(n, value, false);
            } 
        }
    }


    /**
        @dev currently unused, but potentially useful in the future
    */
    function validatorPoolSetGetEntry(uint i) external view returns(uint, uint) {
        return (validatorSet.keyAtIndex(i), eadValidatorPools.eadTotalSupply(validatorSet.keyAtIndex(i)));
    }


    /**
        @dev currently unused, but potentially useful in the future
    */
    function validatorPoolSetGetCount() external view returns(uint) {
        return validatorSet.count();
    }


    // public functions

    /** 
        @notice Generate clickId by hashing input parameters of processClick function.
        @dev clickId is used in processClick to aggregate validator votes. 
    */
    function getClickId(EthereumAdsLib.Entities memory _entities, uint _pValPool, uint _aValPool, string memory _clickDataJSON, bytes32 _ipHash, bool _rewardable) public pure returns(bytes32) {
        return keccak256(abi.encode(_entities,_pValPool, _aValPool, _clickDataJSON, _ipHash, _rewardable));
    }


    /**
        @notice Select validator pool in which token t falls if we put all tokens of validator pools from public validator pool set in a row
                next to each other
    */
    function validatorAtToken(uint t, uint[] memory _excluded) public view returns(uint) {
        uint sum = 0;
        for (uint i=0; i<validatorSet.count(); i++) {
            if (EthereumAdsLib.isUintInArray(_excluded, validatorSet.keyAtIndex(i))) {
                continue;
            }
            uint balance = eadValidatorPools.eadTotalSupply(validatorSet.keyAtIndex(i));
            if (t >= sum && t < sum.add(balance)) {
                return validatorSet.keyAtIndex(i);
            }
            sum = sum.add(balance);
        }
        revert("VALIDATORATTOKEN FAULTY");
    }


    /**
        @notice Calculates the sum of all EAD tokens staked in public validator set excluding validators in exclusion list.
    */
    function validatorSetTotalStakeExcluded(uint[] memory _excluded) public view returns(uint) {
        uint sum = 0;
        for (uint i=0; i<validatorSet.count(); i++) {
            if (EthereumAdsLib.isUintInArray(_excluded, validatorSet.keyAtIndex(i))) {
                continue;
            }
            uint balance = eadValidatorPools.eadTotalSupply(validatorSet.keyAtIndex(i));
            sum = sum.add(balance);
        }
        return sum;
    }


    /**
        @notice Calculates a validator subset of length _len based on _hash without using validator pools in _excluded.
                The probability of a validator pool being selected is linearly proportional to its EthereumAds (EAD) token stake.
        @dev Random token is uniformly selected from [0, N] with N representing the sum of all EAD tokens staked in public validator set
             excluding validators in exclusion list. Selection is calculated by modulo operation of uint represenation of hash and N. 
             Assumption: uint(hash)) >> N
    */
    function calcValidatorSubSet(bytes32 _hash, uint _len, uint[] memory _excluded) public view returns(uint[] memory) {
        if (_len >= validatorSet.count()) {
            return validatorSet.toArray();
        }

        uint[] memory subSet = new uint[](_len);

        for(uint i=0; i < _len; i++) {
            uint[] memory excludedPlus = EthereumAdsLib.concatenateUintArrays(subSet, _excluded);
            uint rndToken = uint(_hash).mod(validatorSetTotalStakeExcluded(excludedPlus));
            uint validator = validatorAtToken(rndToken, excludedPlus);
            if (!EthereumAdsLib.isUintInArray(subSet, validator) && !EthereumAdsLib.isUintInArray(_excluded, validator)) {
                EthereumAdsLib.insertIntoArray(subSet, validator);
            }
            _hash = keccak256(abi.encode(_hash, validator));
        }

        assert(EthereumAdsLib.countNonZero(subSet) == _len);

        return subSet;
    } 


    /** 
        @notice Punishes validator pool by slashing staked EAD tokens if no vote was cast within inactivityTimeout.
        @dev Is called automatically in processClick by dequeuing.
    */
    function slashForInactivity(bytes32 _clickId) public returns(bool) {
        if (block.timestamp.sub(clicks[_clickId].timestamp) > inactivityTimeout) {
            for (uint i=0; i<clicks[_clickId].validatorSet.length;i++) {
                if (!EthereumAdsLib.isUintInArray(clicks[_clickId].approvals, clicks[_clickId].validatorSet[i]) && !EthereumAdsLib.isUintInArray(clicks[_clickId].disapprovals, clicks[_clickId].validatorSet[i])) {
                    eadValidatorPools.slash(clicks[_clickId].validatorSet[i], slashingAmount);
                }
            }
            return true;
        } else {
            return false;
        }
    }


    /**
        @notice Called by each validator subset signer to process a click event received from the adviewer
        @dev Calls payments(...) when validator super-majority is reached, _ipHash has not reached payments before, and campaign has funds and allowance to pay 
    */
    function processClick(EthereumAdsLib.Entities memory _entities, uint _pValPool, uint _pool, string memory _clickDataJSON, bytes32 _ipHash, bool _rewardable, bool _approved) public returns(bool) {
        EthereumAdsLib.Campaign memory campaign = eadCampaigns.getCampaign(_entities.campaign);
        
        require(tokenApproval[campaign.tokenAddr], "TOKEN NOT APPROVED");
        require(campaign.cpc >= minimumCpc[campaign.tokenAddr], "CPC TOO LOW");
        require(!ips[_ipHash], "IPHASH REACHED PAYMENTS BEFORE");
        require(_entities.publisher != _entities.publisherAff, "CANNOT BE OWN AFFILIATE");

        eadCampaigns.transferRequirements(_entities.campaign);

        _entities.campaignAff = campaign.affiliate;
        _entities.campaignOwner = campaign.owner;
        uint aValPool = campaign.valPool; 

        bytes32 clickId = getClickId(_entities, _pValPool, aValPool, _clickDataJSON, _ipHash, _rewardable);

        emit LogProcessClick(_entities.platform, _entities.publisher, _entities.campaignOwner, _entities.campaign, _clickDataJSON, _rewardable, clickId, false);
        emit LogProcessClickAffiliate(_entities.platformAff, _entities.publisherAff, _entities.campaignAff, _entities.campaign, _clickDataJSON, _rewardable, clickId, false);

        if (clicksQueue.firstItem() != bytes32(0)) {
            if (slashForInactivity(clicksQueue.firstItem())) {
                clicksQueue.dequeue();
            }
        }

        uint[] memory valPools = getSetValPools(_entities.publisher, _entities.campaignOwner);

        if (_pValPool != 0) {
            valPools[0] = _pValPool;
        }

        if (aValPool != 0) {
            valPools[valPools.length-1] = aValPool;
        }

        if (clicks[clickId].timestamp == 0) {
            clicks[clickId].timestamp = block.timestamp;
            clicks[clickId].validatorSet = valPools;
            clicksQueue.enqueue(clickId);
        }

        if (_pool != 0) {
            require(EthereumAdsLib.isUintInArray(valPools, _pool), "POOL NOT IN SUBSET");
            require(eadValidatorPools.isSigner(_pool, _msgSender()), "SENDER NOT POOL SIGNER"); // implies creation check 

            if (!EthereumAdsLib.isUintInArray(clicks[clickId].approvals, _pool) && !EthereumAdsLib.isUintInArray(clicks[clickId].disapprovals, _pool)) {
                if (_approved) {
                    clicks[clickId].approvals.push(_pool);
                } else {
                    clicks[clickId].disapprovals.push(_pool);
                }
            } else {
                return false; 
            }
        }
        
        //proposal: should disapproval count negative?
        if (clicks[clickId].approvals.length * 100 < (EthereumAdsLib.countUnique(valPools) * 66)) {
            return false;
        }

        payments(_entities, campaign, valPools, _clickDataJSON, clickId, _rewardable);
        
        //proposal: garbage collection?
        ips[_ipHash] = true; 

        return true;
    }


    // internal function

    function _msgSender() override internal view returns (address payable sender) {
        return ContextMixin.msgSender();
    }


    function whitelistTokens(address _token) internal {
        if (!EthereumAdsLib.isAddressInArray(tokenWhiteList, _token)) {
            tokenWhiteList.push(_token);
        }
    }


    /**
        @notice Calculates new validator pool in case it was removed from public validator set
    */
    function replaceOutcasts(uint[] memory _validators) internal view returns (uint[] memory) {
        for (uint i=0; i < _validators.length; i++) {
            if (!validatorSet.exists(_validators[i])) {
                _validators[i] = calcValidatorSubSet(keccak256(abi.encode(_validators[i])),1,_validators)[0];
            }
        }
        return _validators;
    }


    /**
        @notice Accumulates JSON information about each validator pool in array.
        @dev Used by adviewer to get REST API endpoints of each validator pool to send events to.
    */
    function getValidatorInfoJSON(uint[] memory _valPools) internal view returns(string[] memory) {
        string[] memory validatorInfoJSON = new string[](_valPools.length);
        for (uint i=0; i < _valPools.length; i++) {
            validatorInfoJSON[i] = eadValidatorPools.validatorInfoJSON(_valPools[i]);
        }

        return validatorInfoJSON;
    }


    /**
        @notice Gets the validator pool for given address
    */
    function getValPool(address p) internal view returns(uint[] memory) {
        uint[] memory pValPools;
        if (participants[p].validators.length > 0) {
            // validator pools have already been set, only replace validators in case they were removed from public validator set
            pValPools = replaceOutcasts(participants[p].validators);
        } else {
            // validator pools have not been set before, therefore calculate them
            pValPools = calcValidatorSubSet(keccak256((abi.encode(p))), 2, new uint[](0));
        }
        return pValPools;
    }


    function getSetValPools(address _publisher, address _advertiser) internal returns(uint[] memory) {
        uint[] memory pValPools = getValPool(_publisher);

        if (!EthereumAdsLib.arraysEqual(participants[_publisher].validators, pValPools)) {
            participants[_publisher].validators = pValPools;
            emit LogValidatorAssignment(_publisher, "publisher", pValPools, getValidatorInfoJSON(pValPools));
        }

        uint[] memory aValPools = getValPool(_advertiser);

        if (!EthereumAdsLib.arraysEqual(participants[_advertiser].validators, aValPools)) {
            participants[_advertiser].validators = aValPools;
            emit LogValidatorAssignment(_advertiser, "advertiser", aValPools, getValidatorInfoJSON(aValPools));
        }

        uint[] memory valPools = EthereumAdsLib.concatenateUintArrays(pValPools, aValPools);
        return valPools;
    }


    /**
        @notice Calculate payment amounts from campaign to all other entities and validator pools. Optionally calls for EthereumAds tokens to be rewarded to all entities.
    */
    function payments(EthereumAdsLib.Entities memory _entities, EthereumAdsLib.Campaign memory _campaign, uint[] memory _valPools, string memory _clickDataJSON, bytes32 _clickId, bool _rewardable) internal {
        address tokenAddr = _campaign.tokenAddr;
        require(tokenApproval[tokenAddr], "TOKEN NOT APPROVED");

        uint cpc = _campaign.cpc;
        EthereumAdsLib.TransferPacket[] memory transferPackets = new EthereumAdsLib.TransferPacket[](10);

        if (_rewardable) {
            require(cpc >= minimumCpc[tokenAddr], "CPC TOO LOW FOR REWARD");
            eadTokenRewards.rewardMint(_entities, _valPools);
        }
        
        uint temp = uint(100).sub(validatorPoolCommission).sub(platforms[_entities.platform].commission); 
        
        uint tIndex;

        transferPackets[tIndex] = EthereumAdsLib.TransferPacket(_entities.publisher, cpc.mul(temp).div(100));
        tIndex++;

        uint8 platformCommission = platforms[_entities.platform].commission;
        if (platformCommission > 0) {
            uint temp3 = cpc.mul(platformCommission).div(100);
            transferPackets[tIndex] = EthereumAdsLib.TransferPacket(_entities.platform, temp3);
            tIndex++;
        }  
        
        uint tokenValue = cpc.mul(validatorPoolCommission).div(100);

        transferPackets[tIndex] = EthereumAdsLib.TransferPacket(address(this), tokenValue);
        tIndex++;

        delegatePayments(_entities.campaign, _campaign.tokenAddr, transferPackets, _valPools, tokenValue);

        emitProcessClickEvents(_entities, _clickDataJSON, _rewardable, _clickId);
    }


    /**
        @notice Sends Transferpackets to campaign contract execute transfers, and delegates payments to each validator pool  
        @dev split into separate function because stack size exceeded in payments(...) otherwise
    */
    function delegatePayments(uint _campaign, address _tokenAddr, EthereumAdsLib.TransferPacket[] memory _transferPackets, uint[] memory _valPools, uint _tokenValue) internal {
        eadCampaigns.transferMult(_campaign, _transferPackets);
        
        uint tokenValuePerPool = _tokenValue.div(_valPools.length);
        
        for (uint i=0; i < _valPools.length; i++) {
            payValidatorPool(_tokenAddr, _valPools[i], tokenValuePerPool);
        }
 
    }


    /**
        @dev split into separate function because stack size exceeded in payments(...) otherwise
    */
    function emitProcessClickEvents(EthereumAdsLib.Entities memory _entities, string memory _clickDataJSON, bool _rewardable, bytes32 _clickId) internal {
        emit LogProcessClick(_entities.platform, _entities.publisher, _entities.campaignOwner, _entities.campaign, _clickDataJSON, _rewardable, _clickId, true);
        emit LogProcessClickAffiliate(_entities.platformAff, _entities.publisherAff, _entities.campaignAff, _entities.campaign, _clickDataJSON, _rewardable, _clickId, true);

    }


    /**
        @notice The majority of tokens are deposited into the validator pool which can be withdrawn by stakers. 
                Additionally a commission is sent to the signer of the validator pool to incentivize the operation of the validator node.
    */
    function payValidatorPool(address _tokenAddr, uint _valPool, uint _tokenValuePerPool) internal {
            IERC20Upgradeable erc20 = IERC20Upgradeable(_tokenAddr);
            uint value1 = _tokenValuePerPool.mul(uint(100).sub(signerCommission)).div(100);
            erc20.approve(validatorPoolsAddr, value1);
            eadValidatorPools.deposit(_valPool, _tokenAddr, value1);

            address signerRecipient = eadValidatorPools.signerRecipient(_valPool);
            erc20.transfer(signerRecipient, _tokenValuePerPool.mul(signerCommission).div(100));
    }
}