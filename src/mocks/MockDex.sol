// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";

interface IERC20 {
    function balanceOf(address owner) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

contract MockDex {
    using SafeTransferLib for address payable;

    IERC20 token;

    constructor(address tokenAddress) payable {
        token = IERC20(tokenAddress);
    }

    function swapERC20ToETH(uint256 amount) public {
        token.transferFrom(msg.sender, address(this), amount);
        payable(msg.sender).safeTransferETH(amount);
    }

    function swapETHtoERC20(uint256) public payable {
        token.transfer(msg.sender, msg.value);
    }

    receive() external payable {}
}
