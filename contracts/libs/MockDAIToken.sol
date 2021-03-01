// SPDX-License-Identifier: agpl-3.0

pragma solidity >=0.6.0 <0.8.0;
pragma experimental ABIEncoderV2;

import "./NativeMetaTransaction.sol";
import "./ContextMixin.sol";

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20CappedUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/Initializable.sol";

import "@openzeppelin/contracts-upgradeable/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";

import "../EthereumAdsLib.sol";

contract MockDAIToken is Initializable, ERC20CappedUpgradeable, AccessControlUpgradeable, NativeMetaTransaction, ContextMixin  {
    using SafeMathUpgradeable for uint;

    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant BURNER_ROLE = keccak256("BURNER_ROLE");
    bytes32 public constant DEPOSITOR_ROLE = keccak256("DEPOSITOR_ROLE");

    address public childChainManager;

    function _msgSender() override internal view returns (address payable sender) {
        return ContextMixin.msgSender();
    }

    function initialize(string memory _tokenName, string memory _tokenSymbol, uint _cap, uint _initialSupply, address _childChainManager) public initializer {
        __ERC20_init(_tokenName, _tokenSymbol);
        __ERC20Capped_init(_cap);

        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _setupRole(MINTER_ROLE, _msgSender()); 

        _mint(_msgSender(), _initialSupply); 

        childChainManager = _childChainManager;

        _initializeEIP712(_tokenName, '1');
    }

    function mint(address to, uint amount) public returns(uint) {
        if (to == address(0) || amount == 0) {
            return 0;
        }

        require(hasRole(MINTER_ROLE, _msgSender()), "CALLER IS NOT A MINTER");
      
        _mint(to, amount);

        return amount;
    }

    function burn(address from, uint amount) external {
        require(hasRole(BURNER_ROLE, _msgSender()), "CALLER IS NOT A BURNER");
        _burn(from, amount);
    }

    /**
     * @notice called when token is deposited on root chain
     * @dev Should be callable only by ChildChainManager
     * Should handle deposit by minting the required amount for user
     * Make sure minting is done only by this function
     * @param user user address for whom deposit is being done
     * @param depositData abi encoded amount
     */
    function deposit(address user, bytes calldata depositData)
        external
    {
        require(hasRole(DEPOSITOR_ROLE, _msgSender()), "CALLER IS NOT A DEPOSITOR");
        uint amount = abi.decode(depositData, (uint));
        _mint(user, amount);
    }

    /**
     * @notice called when user wants to withdraw tokens back to root chain
     * @dev Should burn user's tokens. This transaction will be verified when exiting on root chain
     * @param amount amount of tokens to withdraw
     */
    function withdraw(uint amount) external {
        _burn(_msgSender(), amount);
    }
}
