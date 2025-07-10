// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.7.0 <0.9.0;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title TokenA
 * @dev Token ERC20 básico para usar en el SimpleSwap
 * Representa el primer token del par de trading
 */

contract TokenB is ERC20, Ownable {
    constructor(uint256 initialSupply) ERC20("TokenB", "TKB") Ownable(msg.sender) {
        // Minta el supply inicial al deployer (con 18 decimales)
        _mint(msg.sender, initialSupply * 10 ** decimals());
    }

    function mint(address to, uint256 amount) public onlyOwner {
        _mint(to, amount);
    }
}
