// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

// import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "../tokens/ERC20.sol";


contract MockERC20 is ERC20{
    constructor(string memory _name, string memory _symbol, uint8 _decimals){
        name = _name;
        symbol = _symbol;
        decimals = _decimals;
    }

    function mint(address _to, uint256 _amount) public{
        _mint(_to, _amount);
    }

    function burn(address _from, uint256 _amount) public{
        _burn(_from, _amount);
    }

}