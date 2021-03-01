// SPDX-License-Identifier: agpl-3.0

pragma solidity >=0.6.0 <0.8.0;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/SafeERC20Upgradeable.sol";
import "./libs/NativeMetaTransaction.sol";
import "./libs/ContextMixin.sol";
import "./EthereumAdsLib.sol";

/**
    @title Contract for setting up validator pools and staking EthereumAds (EAD) tokens to specific validators
    @author EthereumAds Team
*/
contract EthereumAdsValidatorPools is Initializable, AccessControlUpgradeable, NativeMetaTransaction, ContextMixin {
    using SafeMathUpgradeable for uint;
    using SafeERC20Upgradeable for IERC20Upgradeable;

    bytes32 public constant SLASHER_ROLE = keccak256("SLASHER_ROLE");

    uint public numPools;
    uint public scaling;
    uint public unlockDuration;
    address eadTokenAddr;
    IERC20Upgradeable eadToken;
    IEthereumAds ethereumAds;

    mapping(uint => EthereumAdsLib.Pool) public pools; // starting at 1, index 0 reserved for "NOT SET"
    
    event LogSetValidatorInfoJSON(string validatorInfoJSON);
    event LogChangeAdmin(address admin);
    event LogChangeStakingAllowed(bool stakingAllowed);
    event LogChangeSignerRecipient(address signerRecipient);
    event LogAddSigner(address signer);
    event Transfer(address indexed from, address indexed to, uint value);
    event LogStake(uint value, uint vptTotalSupply, uint eadTotalSupply, uint mintValue);
    event LogStake0(uint mintValue);
    event LogUnstake(uint value, uint eadTotalSupply, uint vptTotalSupply, uint eadValue);
    event LogValidatorPoolCreate(uint indexed pool, string indexed name);
    event LogDeposit(uint indexed pool, address indexed addr, address indexed token, uint value);
    event LogDepositEAD(uint indexed pool, address indexed addr, uint value);
    event LogWithdraw(uint indexed pool, address indexed addr);
    event LogSlash(uint indexed pool, address indexed slasher, uint value);
    event LogRequestUnlock(uint indexed pool, address indexed addr);

    function initialize(address _ethereumAdsAddr) public initializer {
        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _setupRole(SLASHER_ROLE, _ethereumAdsAddr);

        setupEthereumAds(_ethereumAdsAddr);
        unlockDuration = 30 days;
        scaling = uint(10) ** 8;
        _initializeEIP712('EthereumAdsValidatorPools', '1');
    }


    // external functions

    function changeSettings(uint _unlockDuration) external {
        require(hasRole(DEFAULT_ADMIN_ROLE, _msgSender()), "NOT ADMIN");
        unlockDuration = _unlockDuration;
    }


    function validatorInfoJSON(uint n) external view returns(string memory) {
        return pools[n].validatorInfoJSON;
    }


    function signerRecipient(uint n) external view returns(address) {
        return pools[n].signerRecipient;
    }


    function eadTotalSupply(uint n) external view returns(uint) {
        return pools[n].eadTotalSupply;
    }


    function createPool(string memory _poolName, address[] memory _signers) external returns(uint) {
        EthereumAdsLib.Pool storage pool = pools[++numPools];
        pool.name = _poolName;
        pool.signers = _signers;
        pool.admin = _signers[0];
        pool.signerRecipient = _signers[0];
        pool.stakingAllowed = true;
        emit LogValidatorPoolCreate(numPools, _poolName); 
        return numPools; // index identical to length/num because we start at index 1
    }


    /** 
        @notice Used to share tokens with all stakers who can withdraw them in relation to their stake in the pool
        @dev EthereumAds (EAD) tokens have to be handled differently
    */
    function deposit(uint n, address _token, uint _amount) external {
        if (_token == eadTokenAddr) {
            depositEAD(n, _msgSender(), _amount);
            return;
        }

        address[] memory tokenList = ethereumAds.getTokenWhiteList();
        require(EthereumAdsLib.isAddressInArray(tokenList, _token), "TOKEN NOT WHITELISTED");

        uint available = (_amount.mul(scaling)).add(pools[n].scaledRemainder[_token]);
        pools[n].scaledCompensationPerToken[_token] = pools[n].scaledCompensationPerToken[_token].add(available.div(pools[n].vptTotalSupply));
        pools[n].scaledRemainder[_token] = available.mod(pools[n].vptTotalSupply);
        IERC20Upgradeable(_token).transferFrom(_msgSender(), address(this), _amount);
        emit LogDeposit(n, _msgSender(), _token, _amount);
    }


    function unstakeValue(uint n, address _addr) external view returns(uint) {
        uint value = pools[n].vptBalanceOf[_addr];
        return value.mul(pools[n].eadTotalSupply).div(pools[n].vptTotalSupply.add(value));
    }


    function isSigner(uint n, address _addr) external view returns(bool) {
        return EthereumAdsLib.isAddressInArray(pools[n].signers, _addr);
    }


    // public functions

    function setupEthereumAds(address _ethereumAdsAddr) public {
        require(hasRole(DEFAULT_ADMIN_ROLE, _msgSender()), "NOT ADMIN");
        ethereumAds = IEthereumAds(_ethereumAdsAddr);
    }


    function setValidatorInfoJSON(uint n, string memory _validatorInfoJSON) public {
        require(_msgSender() == pools[n].admin, "MUST BE ADMIN");
        pools[n].validatorInfoJSON = _validatorInfoJSON;
        emit LogSetValidatorInfoJSON(pools[n].validatorInfoJSON);
    }


    function changeAdmin(uint n, address _admin) public {
        require(_msgSender() == pools[n].admin, "MUST BE ADMIN");
        pools[n].admin = _admin;
        emit LogChangeAdmin(pools[n].admin);
    }


    function changeStakingAllowed(uint n, bool _stakingAllowed) public {
        require(_msgSender() == pools[n].admin, "MUST BE ADMIN");
        pools[n].stakingAllowed = _stakingAllowed;
        emit LogChangeStakingAllowed(pools[n].stakingAllowed);
    }


    function changeSignerRecipient(uint n, address _signerRecipient) public {
        require(_msgSender() == pools[n].admin, "MUST BE ADMIN");
        pools[n].signerRecipient = _signerRecipient;
        emit LogChangeSignerRecipient(pools[n].signerRecipient);
    }


    function addSigner(uint n, address _signer) public {
        require(_msgSender() == pools[n].admin, "MUST BE ADMIN");
        require(!EthereumAdsLib.isAddressInArray(pools[n].signers, _signer), "ALREADY SIGNER");
        pools[n].signers.push(_signer);
        emit LogAddSigner(_signer);
    }


    function updateEadToken() public {
        eadTokenAddr = ethereumAds.eadAddr();
        eadToken = IERC20Upgradeable(eadTokenAddr);
    }


    /** 
        @notice Used to deposit EthereumAds tokens into pool. These are available to stakers by using unstake(...) 
                in contrast to using withdraw() for other tokens.
    */
    function depositEAD(uint n, address _from, uint _amount) public {
        pools[n].eadTotalSupply = pools[n].eadTotalSupply.add(_amount);
        eadToken.transferFrom(_from, address(this), _amount); 
        ethereumAds.validatorPoolSetUpdate(n); 
        emit LogDepositEAD(n, _from, _amount);
    }


    /** 
        @notice Used by stakers to withdraw payment tokens like DAI, ETH that were deposited into the pool with deposit(...)
    */
    function withdraw(uint n) public {
        address[] memory tokenList = ethereumAds.getTokenWhiteList();
        update(n, _msgSender());
        for (uint i; i < tokenList.length; i++) {
            address token = tokenList[i];
            uint amount = pools[n].scaledCompensationVptBalanceOf[token][_msgSender()].div(scaling);
            pools[n].scaledCompensationVptBalanceOf[token][_msgSender()] = pools[n].scaledCompensationVptBalanceOf[token][_msgSender()].mod(scaling);  // retain the remainder
            _msgSender().transfer(amount);
        }
        emit LogWithdraw(n, _msgSender());
    }
    

    function withdrawAmount(uint n, address _token, address _account) public view returns(uint) {
        uint owed =
            pools[n].scaledCompensationPerToken[_token].sub(pools[n].scaledCompensationCreditedTo[_token][_account]);
        uint temp = pools[n].scaledCompensationVptBalanceOf[_token][_account].add(pools[n].vptBalanceOf[_account].mul(owed));
        return temp.div(scaling);
    }


    /** 
        @notice Used to punish the validator pool's misbehavior like inactivity. Sends EthereumAds tokens to a slasher address.
    */
    function slash(uint n, uint _amount) public {
        require(hasRole(SLASHER_ROLE, _msgSender()), "NOT SLASHER");
        pools[n].eadTotalSupply = pools[n].eadTotalSupply.sub(_amount);
        eadToken.transfer(ethereumAds.slashAddr(), _amount);
        ethereumAds.validatorPoolSetUpdate(n); 
        emit LogSlash(n, _msgSender(), _amount);
    }


    /** 
        @notice Used by stakers to request the right to use unstake(...) which will be available after "unlockDuration".
    */
    function requestUnlock(uint n) public {
        require(pools[n].eadTotalSupply > 0, "POOL DOES NOT EXIST");
        require(pools[n].unlockTime[_msgSender()] == 0);
        pools[n].unlockTime[_msgSender()] = block.timestamp.add(unlockDuration);
        emit LogRequestUnlock(n, _msgSender());
    }


    /** 
        @notice Used to stake EthereumAds tokens into validator pool in order to increase its credibility, i.e. Proof of Stake
    */
    function stake(uint n, uint _amount) public {
        require(pools[n].stakingAllowed, "STAKING CLOSED"); // existance check implied

        pools[n].unlockTime[_msgSender()] = 0;
        eadToken.transferFrom(_msgSender(), address(this), _amount);
        pools[n].eadTotalSupply = pools[n].eadTotalSupply.add(_amount);

        if (pools[n].eadTotalSupply.sub(_amount) > 0) {
            uint mintValue = _amount.mul(pools[n].vptTotalSupply).div(pools[n].eadTotalSupply.sub(_amount)); 
            emit LogStake(_amount, pools[n].vptTotalSupply, pools[n].eadTotalSupply, mintValue);
            mint(n, _msgSender(), mintValue); // y1 = x1 * (Y/X) | Y/X are after stake
        } else {
            mint(n, _msgSender(), _amount);
            emit LogStake0(_amount);
        }

        ethereumAds.validatorPoolSetUpdate(n);

        emit Transfer(address(0), _msgSender(), _amount);
    }


    /** 
        @notice Used to unstake EthereumAds tokens from validator pool in order to decrease its credibility, i.e. Proof of Stake
    */
    function unstake(uint n) public {
        require(pools[n].unlockTime[_msgSender()] != 0 && block.timestamp > pools[n].unlockTime[_msgSender()], "NOT UNLOCKED"); // existance check implied

        pools[n].unlockTime[_msgSender()] = 0;
        uint value = pools[n].vptBalanceOf[_msgSender()];
        burn(n, _msgSender(), value);

        uint eadValue = value.mul(pools[n].eadTotalSupply).div(pools[n].vptTotalSupply.add(value)); // y1 * X / Y | X,Y before unstake
        emit LogUnstake(value, pools[n].eadTotalSupply, pools[n].vptTotalSupply, eadValue);

        pools[n].eadTotalSupply = pools[n].eadTotalSupply.sub(eadValue);
        eadToken.transfer(_msgSender(), eadValue);
        ethereumAds.validatorPoolSetUpdate(n);

        emit Transfer(_msgSender(), address(0), value);
    }


    function mint(uint n, address _addr, uint _amount) internal {
        pools[n].vptTotalSupply = pools[n].vptTotalSupply.add(_amount);
        pools[n].vptBalanceOf[_addr] = pools[n].vptBalanceOf[_addr].add(_amount);
    }


    function burn(uint n, address _addr, uint _amount) internal {
        pools[n].vptTotalSupply = pools[n].vptTotalSupply.sub(_amount);
        pools[n].vptBalanceOf[_addr] = pools[n].vptBalanceOf[_addr].sub(_amount);
    }


    /** 
        @notice Used to keep track of the amount of tokens a staker is credited to.
    */
    function update(uint n, address _account) internal {
        address[] memory tokenList = ethereumAds.getTokenWhiteList(); 

        for (uint i; i < tokenList.length; i++) {
            address token = tokenList[i];
            uint owed =
                pools[n].scaledCompensationPerToken[token].sub(pools[n].scaledCompensationCreditedTo[token][_account]);
            pools[n].scaledCompensationVptBalanceOf[token][_account] = pools[n].scaledCompensationVptBalanceOf[token][_account].add(pools[n].vptBalanceOf[_account].mul(owed));
            pools[n].scaledCompensationCreditedTo[token][_account] = pools[n].scaledCompensationPerToken[token];
        }
    }


    function _msgSender() override internal view returns (address payable sender) {
        return ContextMixin.msgSender();
    }
}