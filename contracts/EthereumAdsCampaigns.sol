// SPDX-License-Identifier: agpl-3.0

pragma solidity >=0.6.0 <0.8.0;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts-upgradeable/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/Initializable.sol";
import "./libs/NativeMetaTransaction.sol";
import "./libs/ContextMixin.sol";
import "./EthereumAdsLib.sol";

/**
    @title Contract for setting up campaigns
    @dev Advertisers set allowance to this contract and transfers are executed here
    @author EthereumAds Team
*/
contract EthereumAdsCampaigns is Initializable, AccessControlUpgradeable, NativeMetaTransaction, ContextMixin {
    using SafeMathUpgradeable for uint;
    using SafeERC20Upgradeable for IERC20Upgradeable;

    bytes32 public constant ETHEREUMADS_ROLE = keccak256("ETHEREUMADS_ROLE");

    uint public numCampaigns;
    IEthereumAds ethereumAds;

    mapping(uint => EthereumAdsLib.Campaign) public campaigns;
 
    event LogSetPauseState(uint indexed campaign, bool indexed paused);
    event LogResetAllowance(address indexed owner, uint indexed campaign);
    event LogCampaignEvent(
        uint indexed campaign,
        uint indexed valPool,
        address indexed advertiser,
        uint cpc,
        uint timeframe, 
        uint clicksPerTimeframe,
        string advertJSON,
        uint8 action // 0:create, 1: change, 2: close, 3: withdraw
    );


    function initialize(address _ethereumAdsAddr) public initializer {
        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _setupRole(ETHEREUMADS_ROLE, _ethereumAdsAddr);
        setupEthereumAds(_ethereumAdsAddr);
        _initializeEIP712('EthereumAdsCampaigns', '1');
    }


    // external functions

    function getCampaign(uint n) external view returns(EthereumAdsLib.Campaign memory) {
        return campaigns[n];
    }

     
    function createCampaign(uint _cpc, uint _timeframe, uint _clicksPerTimeframe, address _tokenAddr, address _affiliate, string memory _advertJSON, uint _valPool) external returns(uint) {
        EthereumAdsLib.Campaign storage campaign = campaigns[++numCampaigns];
        campaign.advertJSON = _advertJSON;
        campaign.owner = _msgSender();
        campaign.affiliate = _affiliate;
        campaign.cpc = _cpc;
        campaign.timeframe = _timeframe;
        campaign.clicksPerTimeframe = _clicksPerTimeframe;
        campaign.tokenAddr = _tokenAddr; 
        campaign.valPool = _valPool;
        campaign.transferQueue = new QueueUint();
        campaign.token = IERC20Upgradeable(_tokenAddr);

        ethereumAds.getSetValPoolsFromCampaigns(campaign.owner, false, campaign.valPool);

        emit LogCampaignEvent(numCampaigns, _valPool, _msgSender(), _cpc, _timeframe, _clicksPerTimeframe,  _advertJSON, 0);
        return numCampaigns;
    } 


    function changeCampaign(uint n, uint _cpc, uint _timeframe, uint _clicksPerTimeframe, string memory _advertJSON) external {
        require(_msgSender() == campaigns[n].owner, 'NOT CAMPAIGN OWNER');

        campaigns[n].advertJSON = _advertJSON;
        campaigns[n].cpc = _cpc;
        campaigns[n].timeframe = _timeframe;
        campaigns[n].clicksPerTimeframe = _clicksPerTimeframe;
        emit LogCampaignEvent(numCampaigns, campaigns[n].valPool, _msgSender(), _cpc, _timeframe, _clicksPerTimeframe,  _advertJSON, 1);
    } 


    /** 
        @notice Transfer all payments in TransferPacket given that all requirements are met. Enqueue click for rate limiting.
    */
    function transferMult(uint n, EthereumAdsLib.TransferPacket[] memory _transferPackets) external returns(bool) {
        require(_transferPackets.length < 20, "TOO MANY TRANSFERS");
        require(hasRole(ETHEREUMADS_ROLE, _msgSender()), "NOT ETHEREUMADS");

        transferRequirements(n);
        
        campaigns[n].transferQueue.enqueue(block.timestamp);
        if (campaigns[n].transferQueue.size() > campaigns[n].clicksPerTimeframe) {
            campaigns[n].transferQueue.dequeue();
        }

        for(uint i=0; i < _transferPackets.length; i++) {
            if (_transferPackets[i].value == 0) {
                continue;
            }
            transfer(n, _transferPackets[i].receiver, _transferPackets[i].value);
        }
        return true;
    }

    
    function setPauseState(uint n, bool _paused) external {
        require(hasRole(DEFAULT_ADMIN_ROLE, _msgSender()) || hasRole(ETHEREUMADS_ROLE, _msgSender()) || _msgSender() == campaigns[n].owner, "NOT AUTHORIZED");

        campaigns[n].paused = _paused;
        emit LogSetPauseState(n, _paused);
    } 


    function resetAllowance(uint n) external {
        campaigns[n].token.transferFrom(msg.sender, msg.sender, campaigns[n].token.allowance(msg.sender, address(this)));
        emit LogResetAllowance(msg.sender, n);
    } 


    // public functions

    function setupEthereumAds(address _ethereumAdsAddr) public {
        require(hasRole(DEFAULT_ADMIN_ROLE, _msgSender()), "NOT ADMIN");
        ethereumAds = IEthereumAds(_ethereumAdsAddr);
    }


    /** 
        @notice Makes sures a set of requirements is met before transfers are allowed
    */
    function transferRequirements(uint n) public view returns(bool) {
        // ensure maximum clicks per timeframe are not exceeded by checking two conditions, at least one has to be true
        // 1. there are fewer clicks in transferQueue than the threshold clicksPerTimeframe
        // 2. the first, i.e. oldest item in the queue is older than timeframe
        require(campaigns[n].transferQueue.size() < campaigns[n].clicksPerTimeframe || block.timestamp.sub(campaigns[n].transferQueue.firstItem()) > campaigns[n].timeframe, "TIMEFRAME BUDGET EXCEEDED");
        
        // ensure advertiser can pay
        require(campaigns[n].token.allowance(campaigns[n].owner, address(this)) >= campaigns[n].cpc, "ALLOWANCE TOO SMALL");
        require(campaigns[n].token.balanceOf(campaigns[n].owner) >= campaigns[n].cpc, "OWNER BALANCE TOO SMALL");
        
        // ensure not paused
        require(!campaigns[n].paused, "CAMPAIGN PAUSED");
        require(!campaigns[0].paused, "ALL CAMPAIGNS PAUSED");

        return true;
    }


    // internal functions 

    function _msgSender() override internal view returns (address payable sender) {
        return ContextMixin.msgSender();
    }


    function transfer(uint n, address _receiver, uint _amount) internal returns(bool) {
        require(_amount <= campaigns[n].cpc, "TRANSFER GREATER CPC");

        campaigns[n].token.transferFrom(campaigns[n].owner, _receiver, _amount);
        
        return true;
    }
}
