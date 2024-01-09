// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";

contract MockERC20Votes is ERC20Votes {

    constructor() ERC20("DEFINITELY", "A") ERC20Permit("A") {
        _mint(msg.sender, 1);
    }

}