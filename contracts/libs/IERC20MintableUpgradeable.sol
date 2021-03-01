// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0 <0.8.0;

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";

interface IERC20MintableUpgradeable is IERC20Upgradeable {
    function mint(address _addr, uint _amount) external;
    function burn(address _addr, uint _amount) external;
}