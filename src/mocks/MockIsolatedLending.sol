// // SPDX-License-Identifier: MIT
// pragma solidity ^0.8.16;

// // import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
// // import "solmate/mixins/ERC4626.sol";
// // import "solmate/tokens/ERC20.sol";

// import "../tokens/ERC4626.sol";

// contract MockIsolatedLending is ERC4626{
//     uint256 totalBorrow;
//     uint256 totalAsset;

//     constructor(address _asset, string memory _name, string memory _symbol) ERC4626(ERC20(_asset), _name, _symbol){
//     }

//     function totalAssets() public view override returns(uint256){
//         return asset.balanceOf(address(this)) + totalBorrow;
//     }

//     function afterDeposit(uint256 assets, uint256 shares) internal override{
//         totalAsset += assets;
//     }

//     function beforeWithdraw(uint256 assets, uint256 shares) internal override{
//         totalAsset -= assets;
//     }

// }