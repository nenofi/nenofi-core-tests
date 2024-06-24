pragma solidity 0.8.18;

import "forge-std/Test.sol";
import "./BaseTest.sol";
import "../src/Neno.sol";
// import "../src/veNeno.sol";
// import "../src/Minter.sol";
// import "../src/RewardsDistributor.sol";

contract LendingMediumRiskTest is BaseTest {
    // Neno public neno;
    // Minter public minter;
    // RewardsDistributor public rewardsDistributor;
    uint128 public constant MAX_DEPOSIT_SIZE = type(uint128).max;
    uint256 private constant BORROW_OPENING_FEE = 50; // 0.05%
    uint256 private constant BORROW_OPENING_FEE_PRECISION = 1e5;

    function deployBase() public {
        initUsers();
        deployTokens();
        mintStables();
        deployOracles();
        deployMultiFeeDistribution();
        deployIsolatedLending();
    }

    function testSetUp() public {
        deployBase();
        assertEq(
            WETHUSDCPool.name(),
            "NenoLend MediumRisk: Wrapped ETH/USD Coin-Chainlink"
        );
        assertEq(WETHUSDCPool.symbol(), "nlmr-WETH/USDC-LINK");
    }

    function testOwner() public {
        deployBase();
        console.log(mediumRiskMasterContract.owner());
        assertEq(mediumRiskMasterContract.owner(), address(this));

        mediumRiskMasterContract.setOwner(address(0x1), false);
        assertEq(mediumRiskMasterContract.owner(), address(0x1));

        vm.startPrank(address(0x1));
        vm.expectRevert("NenoLend: owner is zero address");
        mediumRiskMasterContract.setOwner(address(0x0), false);
    }

    function testOwner2() public {
        deployBase();
        mediumRiskMasterContract.setOwner(address(0x0), true);
        assertEq(mediumRiskMasterContract.owner(), address(0x0));
    }

    function testDualSetUp() public {
        deployBase();
        vm.expectRevert();
        IsolatedLendingV01MediumRisk(
            nenoFactory.deploy(
                address(mediumRiskMasterContract),
                abi.encode(
                    address(wethOracle),
                    address(WETH),
                    address(USDC),
                    "NenoLend MediumRisk: Wrapped ETH/USD Coin-Chainlink",
                    "nlmr-WETH/USDC-LINK"
                ),
                true
            )
        );

        assertEq(
            WETHUSDCPool.name(),
            "NenoLend MediumRisk: Wrapped ETH/USD Coin-Chainlink"
        );
        assertEq(WETHUSDCPool.symbol(), "nlmr-WETH/USDC-LINK");
    }

    function testInitCollateralZero() public {
        deployBase();
        vm.expectRevert("NenoLend: bad pair");
        IsolatedLendingV01MediumRisk(
            nenoFactory.deploy(
                address(mediumRiskMasterContract),
                abi.encode(
                    address(wethOracle),
                    address(0x0),
                    address(USDC),
                    "NenoLend MediumRisk: Wrapped ETH/USD Coin-Chainlink",
                    "nlmr-WETH/USDC-LINK"
                ),
                true
            )
        );
    }

    function testCallInitTwice() public {
        deployBase();
        vm.expectRevert("NenoLend: already initialized");
        WETHUSDCPool.init(
            abi.encode(
                address(wethOracle),
                address(WETH),
                address(USDC),
                "NenoLend MediumRisk: Wrapped ETH/USD Coin-Chainlink",
                "nlmr-WETH/USDC-LINK"
            )
        );
    }

    function testInitMasterContract() public {
        deployBase();
        mediumRiskMasterContract.init(
            abi.encode(
                address(wethOracle),
                address(USDC),
                address(WETH),
                "NenoLend MediumRisk: Wrapped ETH/USD Coin-Chainlink",
                "nlmr-WETH/USDC-LINK"
            )
        );
    }

    function testDeposit() public {
        deployBase();
        depositAssetToLending();
        for (uint i = 0; i < lenders.length; i++) {
            assertEq(WETHUSDCPool.balanceOf(lenders[i]), 100_000e6);
            assertEq(USDC.balanceOf(lenders[i]), 0);
        }
        for (uint i = 0; i < borrowers.length; i++) {
            assertEq(WETH.balanceOf(borrowers[i]), 2e18);
        }
    }

    function testOracle() public {
        deployBase();
        (, int256 collateralPrice, , , ) = ethFeed.latestRoundData();
        (, int256 assetPrice, , , ) = usdcFeed.latestRoundData();
        assertEq(
            wethOracle.latestPrice(),
            (uint256(collateralPrice) * 1e6) / (uint256(assetPrice))
        );
        assertEq(
            usdcOracle.latestPrice(),
            (uint256(assetPrice) * 1e18) / (uint256(collateralPrice))
        );
    }

    function testCollateralValue() public {
        deployBase();
        for (uint i = 0; i < borrowers.length; i++) {
            vm.startPrank(address(borrowers[i]));
            uint WETH_bal = WETH.balanceOf(address(borrowers[i]));
            WETH.approve(
                address(WETHUSDCPool),
                WETH.balanceOf(address(borrowers[i]))
            );
            WETHUSDCPool.addCollateral(WETH.balanceOf(address(borrowers[i])));
            assertEq(
                WETHUSDCPool.userCollateralValue(address(borrowers[i])),
                wethOracle.latestPrice() * 2
            ); //2 WETHS

            WETHUSDCPool.removeCollateral(WETH_bal);
            assertEq(
                WETHUSDCPool.userCollateralValue(address(borrowers[i])),
                0
            );
            vm.stopPrank();
        }
    }

    function testBorrowSolvent() public {
        deployBase();
        depositAssetToLending();
        for (uint i = 0; i < borrowers.length; i++) {
            vm.startPrank(address(borrowers[i]));
            WETH.approve(
                address(WETHUSDCPool),
                WETH.balanceOf(address(borrowers[i]))
            );
            WETHUSDCPool.addCollateral(WETH.balanceOf(address(borrowers[i])));
            vm.stopPrank();
            assertEq(
                WETHUSDCPool.userCollateralValue(address(borrowers[i])),
                wethOracle.latestPrice() * 2
            ); //2 WETHS
            vm.startPrank(address(borrowers[i]));
            WETHUSDCPool.borrow(100e6);
            assertEq(WETHUSDCPool.isSolvent(borrowers[i]), true);
            assertEq(
                USDC.balanceOf(borrowers[i]) +
                    ((USDC.balanceOf(borrowers[i]) * BORROW_OPENING_FEE) /
                        BORROW_OPENING_FEE_PRECISION),
                WETHUSDCPool.totalAmountBorrowed(borrowers[i])
            );

            vm.stopPrank();
        }
    }

    function testDepositAndWithdrawAsset(uint256 amount) public {
        deployBase();
        amount = bound(amount, 1, MAX_DEPOSIT_SIZE);

        vm.startPrank(lender0);
        USDC.mint(address(lender0), amount);
        USDC.approve(address(WETHUSDCPool), amount);
        WETHUSDCPool.deposit(amount, address(lender0));
        vm.stopPrank();
        assertEq(WETHUSDCPool.balanceOf(address(lender0)), amount);
        assertEq(WETHUSDCPool.totalAssets(), amount);
        assertEq(WETHUSDCPool.totalSupply(), amount);

        vm.startPrank(lender0);
        WETHUSDCPool.withdraw(amount, address(lender0), address(lender0));
        vm.stopPrank();
        assertEq(WETHUSDCPool.balanceOf(address(lender0)), 0);
        assertEq(WETHUSDCPool.totalAssets(), 0);
        assertEq(WETHUSDCPool.totalSupply(), 0);
        assertEq(WETHUSDCPool.borrowAmountToShares(1000e6), 1000e6);

        WETHUSDCPool.accrue();
        (uint256 interest, ) = WETHUSDCPool.accrueInfo();
        assertEq(interest, 317097920);
    }

    function testDepositAndWithdrawAssetNonOwnerApprovals(
        uint256 amount
    ) public {
        deployBase();
        amount = bound(amount, 1, MAX_DEPOSIT_SIZE);

        vm.startPrank(lender0);
        USDC.mint(address(lender0), amount);
        USDC.approve(address(WETHUSDCPool), amount);
        WETHUSDCPool.deposit(amount, address(lender0));
        vm.stopPrank();
        assertEq(WETHUSDCPool.balanceOf(address(lender0)), amount);
        assertEq(WETHUSDCPool.totalAssets(), amount);
        assertEq(WETHUSDCPool.totalSupply(), amount);

        vm.startPrank(lender1);
        vm.expectRevert(stdError.arithmeticError);
        WETHUSDCPool.withdraw(amount, address(lender0), address(lender0));
        vm.stopPrank();
    }

    function testDepositAndWithdrawAssetNonOwnerWithApprovals(
        uint256 amount
    ) public {
        deployBase();
        amount = bound(amount, 1, MAX_DEPOSIT_SIZE);

        vm.startPrank(lender0);
        USDC.mint(address(lender0), amount);
        USDC.approve(address(WETHUSDCPool), amount);
        WETHUSDCPool.deposit(amount, address(lender0));
        WETHUSDCPool.approve(lender1, amount);
        vm.stopPrank();
        assertEq(WETHUSDCPool.balanceOf(address(lender0)), amount);
        assertEq(WETHUSDCPool.totalAssets(), amount);
        assertEq(WETHUSDCPool.totalSupply(), amount);

        vm.startPrank(lender1);
        WETHUSDCPool.withdraw(amount, address(lender0), address(lender0));
        vm.stopPrank();
        assertEq(WETHUSDCPool.balanceOf(address(lender0)), 0);
        assertEq(WETHUSDCPool.totalAssets(), 0);
        assertEq(WETHUSDCPool.totalSupply(), 0);
    }

    function testDepositAndWithdrawAssetToNonOwnerWithApprovals(
        uint256 amount
    ) public {
        deployBase();
        amount = bound(amount, 1, MAX_DEPOSIT_SIZE);

        vm.startPrank(lender0);
        USDC.mint(address(lender0), amount);
        USDC.approve(address(WETHUSDCPool), amount);
        WETHUSDCPool.deposit(amount, address(lender0));
        WETHUSDCPool.approve(lender1, amount);
        vm.stopPrank();
        assertEq(WETHUSDCPool.balanceOf(address(lender0)), amount);
        assertEq(WETHUSDCPool.totalAssets(), amount);
        assertEq(WETHUSDCPool.totalSupply(), amount);

        vm.startPrank(lender1);
        WETHUSDCPool.withdraw(amount, address(lender1), address(lender0));
        vm.stopPrank();
        assertEq(WETHUSDCPool.balanceOf(address(lender0)), 0);
        assertEq(WETHUSDCPool.totalAssets(), 0);
        assertEq(WETHUSDCPool.totalSupply(), 0);
    }

    function testMintAndRedeemAsset(uint256 amount) public {
        deployBase();
        amount = bound(amount, 1, MAX_DEPOSIT_SIZE);

        vm.startPrank(lender0);
        USDC.mint(address(lender0), amount);
        USDC.approve(address(WETHUSDCPool), amount);
        WETHUSDCPool.mint(amount, address(lender0));
        vm.stopPrank();

        assertEq(WETHUSDCPool.balanceOf(address(lender0)), amount);
        assertEq(WETHUSDCPool.totalAssets(), amount);
        assertEq(WETHUSDCPool.totalSupply(), amount);

        vm.startPrank(lender0);
        WETHUSDCPool.redeem(amount, address(lender0), address(lender0));
        vm.stopPrank();
        assertEq(WETHUSDCPool.balanceOf(address(lender0)), 0);
        assertEq(WETHUSDCPool.totalAssets(), 0);
        assertEq(WETHUSDCPool.totalSupply(), 0);
    }

    function testMintAndRedeemAssetNonOwnerApprovals(uint256 amount) public {
        deployBase();
        amount = bound(amount, 1, MAX_DEPOSIT_SIZE);

        vm.startPrank(lender0);
        USDC.mint(address(lender0), amount);
        USDC.approve(address(WETHUSDCPool), amount);
        WETHUSDCPool.mint(amount, address(lender0));
        vm.stopPrank();

        assertEq(WETHUSDCPool.balanceOf(address(lender0)), amount);
        assertEq(WETHUSDCPool.totalAssets(), amount);
        assertEq(WETHUSDCPool.totalSupply(), amount);

        vm.startPrank(lender1);
        vm.expectRevert(stdError.arithmeticError);
        WETHUSDCPool.redeem(amount, address(lender1), address(lender0));
        vm.stopPrank();
    }

    function testAddAndRemoveCollateral(uint256 amount) public {
        deployBase();
        amount = bound(amount, 1, MAX_DEPOSIT_SIZE);

        // console.log("WETH balance: %s", WETH.balanceOf(address(borrower0)));
        vm.startPrank(borrower0);
        WETH.mint(borrower0, amount);
        WETH.approve(address(WETHUSDCPool), amount);
        WETHUSDCPool.addCollateral(amount);
        // console.log("User collateral amt: %s",WETHUSDCPool.userCollateralAmount(address(borrower0)));
        assertEq(WETHUSDCPool.userCollateralAmount(address(borrower0)), amount);
        // console.log("User collateral val: %s", WETHUSDCPool.userCollateralValue(address(borrower0)));

        WETHUSDCPool.removeCollateral(amount);
        vm.stopPrank();
        assertEq(WETHUSDCPool.userCollateralAmount(address(borrower0)), 0);
    }

    function testBorrow() public {
        deployBase();

        vm.startPrank(lender0);
        USDC.mint(address(lender0), 100000e6);
        USDC.approve(address(WETHUSDCPool), 100000e6);
        WETHUSDCPool.deposit(100000e6, address(lender0));
        vm.stopPrank();
        assertEq(WETHUSDCPool.balanceOf(address(lender0)), 100000e6);

        vm.startPrank(borrower0);
        WETH.approve(address(WETHUSDCPool), 1e18);
        WETHUSDCPool.addCollateral(1e18);
        console.log(
            "Borrower collateral value (USDC): %s",
            WETHUSDCPool.userCollateralValue(address(borrower0))
        );
        console.log(
            "Available USDC to borrow: %s",
            (WETHUSDCPool.userCollateralValue(address(borrower0)) * 75) / 100
        );

        WETHUSDCPool.borrow(20e6);
        console.log("borrower0 borrows: %s", 20e6);
        vm.stopPrank();
        assertEq(WETHUSDCPool.userCollateralAmount(address(borrower0)), 1e18);
        assertEq(WETHUSDCPool.isSolvent(address(borrower0)), true);
        assertEq(WETHUSDCPool.userBorrowShare(borrower0), 20010000);
        assertEq(
            USDC.balanceOf(borrower0) +
                ((USDC.balanceOf(borrower0) * BORROW_OPENING_FEE) /
                    BORROW_OPENING_FEE_PRECISION),
            WETHUSDCPool.totalAmountBorrowed(borrower0)
        );
    }

    function testBorrow2() public {
        deployBase();

        vm.startPrank(lender0);
        USDC.mint(address(lender0), 100000e6);
        USDC.approve(address(WETHUSDCPool), 100000e6);
        WETHUSDCPool.deposit(100000e6, address(lender0));
        vm.stopPrank();
        assertEq(WETHUSDCPool.balanceOf(address(lender0)), 100000e6);

        vm.startPrank(borrower0);
        WETH.approve(address(WETHUSDCPool), 1e18);
        WETHUSDCPool.addCollateral(1e18);
        console.log(
            "Borrower collateral value (USDC): %s",
            WETHUSDCPool.userCollateralValue(address(borrower0))
        );
        console.log(
            "Available USDC to borrow: %s",
            (WETHUSDCPool.userCollateralValue(address(borrower0)) * 75) / 100
        );
        WETHUSDCPool.borrow(10e6);
        console.log("borrower0 borrows: %s", 10e6);
        vm.stopPrank();
        assertEq(WETHUSDCPool.userCollateralAmount(address(borrower0)), 1e18);
        assertEq(WETHUSDCPool.isSolvent(address(borrower0)), true);
        // assertEq(WETHUSDCPool.userBorrowShare(borrower0), 20010000);

        vm.startPrank(borrower1);
        WETH.approve(address(WETHUSDCPool), 1e18);
        WETHUSDCPool.addCollateral(1e18);
        console.log(
            "Borrower collateral value (USDC): %s",
            WETHUSDCPool.userCollateralValue(address(borrower0))
        );
        console.log(
            "Available USDC to borrow: %s",
            (WETHUSDCPool.userCollateralValue(address(borrower0)) * 75) / 100
        );
        WETHUSDCPool.borrow(100e6);
        vm.stopPrank();
        assertEq(WETHUSDCPool.userCollateralAmount(address(borrower0)), 1e18);
        assertEq(WETHUSDCPool.isSolvent(address(borrower0)), true);
        assertEq(WETHUSDCPool.totalAmountBorrowed(borrower0), 10005000);
        assertEq(WETHUSDCPool.totalAmountBorrowed(borrower1), 100050000);
        // assertEq(WETHUSDCPool.userBorrowShare(borrower0), 20010000);
    }

    function testBorrowWei() public {
        deployBase();

        vm.startPrank(lender0);
        USDC.mint(address(lender0), 100000e6);
        USDC.approve(address(WETHUSDCPool), 100000e6);
        WETHUSDCPool.deposit(100000e6, address(lender0));
        vm.stopPrank();
        assertEq(WETHUSDCPool.balanceOf(address(lender0)), 100000e6);

        vm.startPrank(borrower0);
        WETH.approve(address(WETHUSDCPool), 1e18);
        WETHUSDCPool.addCollateral(1e18);

        WETHUSDCPool.borrow(1);
        vm.stopPrank();
        assertEq(WETHUSDCPool.userCollateralAmount(address(borrower0)), 1e18);
        assertEq(WETHUSDCPool.isSolvent(address(borrower0)), true);
        assertGt(WETHUSDCPool.userBorrowShare(borrower0), 0);
    }

    function testInterestRate() public {
        deployBase();

        vm.startPrank(lender0);
        USDC.mint(address(lender0), 100000e6);
        USDC.approve(address(WETHUSDCPool), 100000e6);
        WETHUSDCPool.deposit(1400e6, address(lender0));
        vm.stopPrank();
        assertEq(WETHUSDCPool.balanceOf(address(lender0)), 1400e6);

        vm.startPrank(borrower0);
        WETH.approve(address(WETHUSDCPool), 1e18);
        WETHUSDCPool.addCollateral(1e18);
        console.log(
            "Borrower collateral value (USDC): %s",
            WETHUSDCPool.userCollateralValue(address(borrower0))
        );
        console.log(
            "Available USDC to borrow: %s",
            (WETHUSDCPool.userCollateralValue(address(borrower0)) * 75) / 100
        );

        WETHUSDCPool.borrow(1000e6);
        console.log("borrower0 borrows: %s", 1000e6);
        vm.stopPrank();
        assertEq(WETHUSDCPool.userCollateralAmount(address(borrower0)), 1e18);
        assertEq(WETHUSDCPool.isSolvent(address(borrower0)), true);
        assertEq(WETHUSDCPool.userBorrowShare(borrower0), 1000500000);

        vm.warp(block.timestamp + 31536000);
        WETHUSDCPool.accrue();
        assertLt(WETHUSDCPool.totalAmountBorrowed(borrower0), 1011e6);
        assertGe(WETHUSDCPool.totalAmountBorrowed(borrower0), 1000e6);
        assertEq(WETHUSDCPool.userBorrowShare(borrower0), 1000500000);

        console.log(WETHUSDCPool.getInterestPerSecond());
        console.log(
            "borrower0 borrows + interest: ",
            WETHUSDCPool.totalAmountBorrowed(borrower0)
        );
    }

    function testInsolventBorrow() public {
        deployBase();

        vm.startPrank(lender0);
        USDC.mint(address(lender0), 100000e6);
        USDC.approve(address(WETHUSDCPool), 100000e6);
        WETHUSDCPool.deposit(100000e6, address(lender0));
        vm.stopPrank();
        assertEq(WETHUSDCPool.balanceOf(address(lender0)), 100000e6);

        vm.startPrank(borrower0);
        WETH.approve(address(WETHUSDCPool), 1e18);
        WETHUSDCPool.addCollateral(1e18);
        console.log(
            "Borrower collateral value (USDC): %s",
            WETHUSDCPool.userCollateralValue(address(borrower0))
        );
        console.log(
            "Available USDC to borrow: %s",
            (WETHUSDCPool.userCollateralValue(address(borrower0)) * 75) / 100
        );

        vm.expectRevert("NenoLend: user insolvent");
        WETHUSDCPool.borrow(2000e6);
        console.log("borrower0 borrows: %s", 2000e6);
        WETHUSDCPool.removeCollateral(1e18);
        vm.stopPrank();
    }

    function testBorrowAndWithdrawAllCollateral() public {
        deployBase();

        vm.startPrank(lender0);
        USDC.mint(address(lender0), 100000e6);
        USDC.approve(address(WETHUSDCPool), 100000e6);
        WETHUSDCPool.deposit(100000e6, address(lender0));
        vm.stopPrank();
        assertEq(WETHUSDCPool.balanceOf(address(lender0)), 100000e6);

        vm.startPrank(borrower0);
        WETH.approve(address(WETHUSDCPool), 1e18);
        WETHUSDCPool.addCollateral(1e18);
        console.log(
            "Borrower collateral value (USDC): %s",
            WETHUSDCPool.userCollateralValue(address(borrower0))
        );
        console.log(
            "Available USDC to borrow: %s",
            (WETHUSDCPool.userCollateralValue(address(borrower0)) * 75000) /
                100000
        );
        WETHUSDCPool.borrow(1000e6);
        console.log("borrower0 borrows: %s", 1000e6);
        vm.expectRevert("NenoLend: user insolvent");
        WETHUSDCPool.removeCollateral(1e18);
        vm.stopPrank();
    }

    function testBorrowNoCollateral() public {
        deployBase();

        vm.startPrank(lender0);
        USDC.mint(address(lender0), 100000e6);
        USDC.approve(address(WETHUSDCPool), 100000e6);
        WETHUSDCPool.deposit(100000e6, address(lender0));
        vm.stopPrank();
        assertEq(WETHUSDCPool.balanceOf(address(lender0)), 100000e6);

        vm.startPrank(borrower0);
        console.log(
            "Borrower collateral value (USDC): %s",
            WETHUSDCPool.userCollateralValue(address(borrower0))
        );
        console.log(
            "Available USDC to borrow: %s",
            (WETHUSDCPool.userCollateralValue(address(borrower0)) * 75000) /
                100000
        );
        vm.expectRevert("NenoLend: user insolvent");

        WETHUSDCPool.borrow(1000e6);
        console.log("borrower0 borrows: %s", 1000e6);
        vm.stopPrank();
    }

    function testWithdrawAllAssetWhenBorrowed(uint256 amount) public {
        deployBase();
        amount = bound(amount, 1000e6, MAX_DEPOSIT_SIZE);

        vm.startPrank(lender0);
        USDC.mint(address(lender0), amount);
        USDC.approve(address(WETHUSDCPool), amount);
        WETHUSDCPool.deposit(amount, address(lender0));
        vm.stopPrank();
        assertEq(WETHUSDCPool.balanceOf(address(lender0)), amount);

        vm.startPrank(borrower0);
        WETH.approve(address(WETHUSDCPool), 1e18);
        WETHUSDCPool.addCollateral(1e18);
        console.log(
            "Borrower collateral value (USDC): %s",
            WETHUSDCPool.userCollateralValue(address(borrower0))
        );
        console.log(
            "Available USDC to borrow: %s",
            (WETHUSDCPool.userCollateralValue(address(borrower0)) * 75000) /
                100000
        );
        WETHUSDCPool.borrow(1000e6);
        console.log("borrower0 borrows: %s", 1000e6);
        vm.stopPrank();

        vm.startPrank(lender0);
        vm.expectRevert(stdError.arithmeticError);
        WETHUSDCPool.withdraw(amount, address(lender0), address(lender0));
        vm.stopPrank();
    }

    function testMultipleBorrowMidEntry() public {
        deployBase();

        vm.startPrank(lender0);
        USDC.mint(address(lender0), 100000e6);
        USDC.approve(address(WETHUSDCPool), 100000e6);
        WETHUSDCPool.deposit(100000e6, address(lender0));
        vm.stopPrank();
        assertEq(WETHUSDCPool.balanceOf(address(lender0)), 100000e6);

        vm.startPrank(borrower0);
        USDC.mint(address(borrower0), 100000e6);
        WETH.approve(address(WETHUSDCPool), 1e18);
        WETHUSDCPool.addCollateral(1e18);
        WETHUSDCPool.borrow(100e6);
        vm.stopPrank();

        assertGt(WETHUSDCPool.totalAmountBorrowed(address(borrower0)), 100e6);
        assertEq(WETHUSDCPool.userCollateralAmount(address(borrower0)), 1e18);
        assertGt(USDC.balanceOf(address(borrower0)), 100000e6);
        assertEq(WETHUSDCPool.userBorrowShare(borrower0), 100050000);

        vm.warp(block.timestamp + 10518975);
        WETHUSDCPool.accrue();

        vm.startPrank(borrower1);
        USDC.mint(address(borrower1), 100000e6);

        WETH.approve(address(WETHUSDCPool), 2e18);
        WETHUSDCPool.addCollateral(2e18);
        WETHUSDCPool.borrow(150e6);
        vm.stopPrank();

        console.log(
            "BORROWER0 SHARE: ",
            WETHUSDCPool.userBorrowShare(borrower0)
        );
        console.log(
            "BORROWER1 SHARE: ",
            WETHUSDCPool.userBorrowShare(borrower1)
        );
        console.log("TOTAL BORROW SHARE: ", WETHUSDCPool.totalBorrowShares());
        console.log(
            "BORROWER0 BORROWS: ",
            WETHUSDCPool.totalAmountBorrowed(borrower0)
        );
        console.log(
            "BORROWER1 BORROWS: ",
            WETHUSDCPool.totalAmountBorrowed(borrower1)
        );
        console.log("TOTAL BORROW: ", WETHUSDCPool.totalBorrow());

        assertGe(WETHUSDCPool.totalAmountBorrowed(address(borrower1)), 150e6);
        assertLt(WETHUSDCPool.userBorrowShare(borrower1), 150e6);
    }

    function testMultipleBorrowAndRepayDepositWithdraw() public {
        deployBase();
        uint256 lender0USDCBalanceBefore = USDC.balanceOf(address(lender0));

        vm.startPrank(lender0);
        USDC.mint(address(lender0), 100000e6);
        USDC.approve(address(WETHUSDCPool), 100000e6);
        WETHUSDCPool.deposit(100000e6, address(lender0));
        vm.stopPrank();
        assertEq(WETHUSDCPool.balanceOf(address(lender0)), 100000e6);
        console.log(
            "lender0 balance before: %s",
            WETHUSDCPool.convertToAssets(WETHUSDCPool.balanceOf(lender0))
        );
        console.log("total asset:", WETHUSDCPool.totalAsset());
        console.log("total borrow:", WETHUSDCPool.totalBorrow());
        console.log("total assets:", WETHUSDCPool.totalAssets());

        uint256 lender1BalanceBefore = WETHUSDCPool.convertToAssets(
            WETHUSDCPool.balanceOf(lender0)
        );
        uint256 startingTotalAssets = WETHUSDCPool.totalAssets();

        vm.startPrank(borrower0);
        USDC.mint(address(borrower0), 100000e6);

        WETH.approve(address(WETHUSDCPool), 1e18);
        WETHUSDCPool.addCollateral(1e18);
        WETHUSDCPool.borrow(100e6);
        vm.stopPrank();
        console.log(
            "borrower0 collateral value (USDC): %s",
            WETHUSDCPool.userCollateralValue(address(borrower0))
        );
        console.log(
            "B1 Available USDC to borrow: %s",
            (WETHUSDCPool.userCollateralValue(address(borrower0)) * 75) / 100
        );

        assertEq(WETHUSDCPool.userCollateralAmount(address(borrower0)), 1e18);
        assertGt(USDC.balanceOf(address(borrower0)), 100000e6);

        vm.startPrank(borrower1);
        USDC.mint(address(borrower1), 100000e6);

        WETH.approve(address(WETHUSDCPool), 2e18);
        WETHUSDCPool.addCollateral(2e18);
        WETHUSDCPool.borrow(60e6);
        vm.stopPrank();
        console.log(
            "borrower1 collateral value (USDC): %s",
            WETHUSDCPool.userCollateralValue(address(borrower1))
        );
        console.log(
            "B2 Available USDC to borrow: %s",
            (WETHUSDCPool.userCollateralValue(address(borrower1)) * 75) / 100
        );
        console.log("total asset:", WETHUSDCPool.totalAsset());
        console.log("total borrow:", WETHUSDCPool.totalBorrow());
        console.log("total assets:", WETHUSDCPool.totalAssets());

        assertEq(WETHUSDCPool.userCollateralAmount(address(borrower1)), 2e18);
        assertGt(USDC.balanceOf(address(borrower1)), 100000e6);

        assertGt(WETHUSDCPool.totalAmountBorrowed(address(borrower0)), 100e6);
        assertGt(WETHUSDCPool.totalAmountBorrowed(address(borrower1)), 60e6);

        vm.warp(block.timestamp + 10518975);
        WETHUSDCPool.accrue();
        vm.warp(block.timestamp + 10518975);
        WETHUSDCPool.accrue();
        vm.warp(block.timestamp + 10518975);
        WETHUSDCPool.accrue();

        assertGt(WETHUSDCPool.totalAmountBorrowed(address(borrower0)), 100e6);
        assertGt(WETHUSDCPool.totalAmountBorrowed(address(borrower1)), 60e6);
        assertGt(
            WETHUSDCPool.convertToAssets(
                WETHUSDCPool.balanceOf(address(lender0))
            ),
            WETHUSDCPool.balanceOf(address(lender0))
        );

        console.log(
            "borrower0 borrow amount after 1 yr: %s",
            WETHUSDCPool.totalAmountBorrowed(address(borrower0))
        );
        console.log(
            "borrower1 borrow amount after 1 yr: %s",
            WETHUSDCPool.totalAmountBorrowed(address(borrower1))
        );
        // console.log("protocol fee (USDC): %s", WETHUSDCPool.convertToAssets(WETHUSDCPool.balanceOf(address(this))));
        console.log("total asset after 1 yr:", WETHUSDCPool.totalAsset());
        console.log("total borrow after 1 yr:", WETHUSDCPool.totalBorrow());
        console.log("total assets after 1 yr:", WETHUSDCPool.totalAssets());

        vm.startPrank(borrower0);
        USDC.approve(address(WETHUSDCPool), 100551207);
        WETHUSDCPool.repay(100551207);
        vm.stopPrank();

        vm.startPrank(borrower1);
        USDC.approve(address(WETHUSDCPool), 60330724);
        WETHUSDCPool.repay(60330724);
        vm.stopPrank();
        assertLt(WETHUSDCPool.totalAmountBorrowed(address(borrower0)), 500e6);
        assertLt(WETHUSDCPool.totalAmountBorrowed(address(borrower1)), 250e6);
        assertGt(WETHUSDCPool.totalAssets(), startingTotalAssets);
        console.log(
            "lender0 balance after: %s",
            WETHUSDCPool.convertToAssets(WETHUSDCPool.balanceOf(lender0))
        );
        vm.startPrank(borrower0);
        USDC.approve(address(WETHUSDCPool), 1);
        WETHUSDCPool.repay(1);
        vm.stopPrank();

        //check if lender asset increases after repayment
        assertGt(
            WETHUSDCPool.convertToAssets(WETHUSDCPool.balanceOf(lender0)),
            lender1BalanceBefore
        );

        console.log(
            "B1 borrow amt after paid: ",
            WETHUSDCPool.totalAmountBorrowed(address(borrower0))
        );
        console.log(
            "B2 borrow amt after paid: ",
            WETHUSDCPool.totalAmountBorrowed(address(borrower1))
        );

        console.log("total asset after repay:", WETHUSDCPool.totalAsset());
        console.log("total borrow after repay:", WETHUSDCPool.totalBorrow());
        console.log("total assets after repay:", WETHUSDCPool.totalAssets());

        vm.startPrank(lender0);
        console.log(
            "L1 maxwithdraw: ",
            WETHUSDCPool.maxWithdraw(address(lender0))
        );
        WETHUSDCPool.withdraw(
            WETHUSDCPool.maxWithdraw(address(lender0)),
            address(lender0),
            address(lender0)
        );

        // WETHUSDCPool.removeAsset(100000721545);
        vm.stopPrank();

        console.log(
            "owner max withdraw: ",
            WETHUSDCPool.maxWithdraw(address(this))
        );
        WETHUSDCPool.withdraw(
            WETHUSDCPool.maxWithdraw(address(this)),
            address(this),
            address(this)
        );
        console.log(
            "B1 borrowed amt: ",
            WETHUSDCPool.totalAmountBorrowed(address(borrower0))
        );
        console.log(
            "B2 borrowed amt: ",
            WETHUSDCPool.totalAmountBorrowed(address(borrower1))
        );

        console.log("total asset final:", WETHUSDCPool.totalAsset());
        console.log("pool USDC bal: ", USDC.balanceOf(address(WETHUSDCPool)));
        console.log("total borrow final:", WETHUSDCPool.totalBorrow());
        console.log("total assets final:", WETHUSDCPool.totalAssets());

        // check if lender asset increases after withdrawal
        assertGt(USDC.balanceOf(address(lender0)), lender0USDCBalanceBefore);
        assertEq(WETHUSDCPool.totalAssets(), 0);
        assertEq(WETHUSDCPool.totalBorrow(), 0);
        assertEq(WETHUSDCPool.totalAsset(), 0);

        vm.warp(block.timestamp + 60);
        WETHUSDCPool.accrue();
        console.log("PROTOCOL REVENUE:", USDC.balanceOf(address(feeVault)));
    }

    function testDepositAccrue() public {
        deployBase();
        vm.startPrank(lender0);
        USDC.mint(address(lender0), 100000e6);
        USDC.approve(address(WETHUSDCPool), 1500e6);
        WETHUSDCPool.deposit(1500e6, address(lender0));
        vm.stopPrank();

        assertEq(WETHUSDCPool.balanceOf(address(lender0)), 1500e6);
        console.log(
            "lender0 balance before: %s",
            WETHUSDCPool.convertToAssets(WETHUSDCPool.balanceOf(lender0))
        );

        vm.startPrank(borrower0);
        USDC.mint(address(borrower0), 100000e6);
        WETH.approve(address(WETHUSDCPool), 2e18);
        WETHUSDCPool.addCollateral(2e18);
        console.log(
            "Borrower col val: %s",
            WETHUSDCPool.userCollateralValue(address(borrower0))
        );
        WETHUSDCPool.borrow(1010e6);
        vm.stopPrank();
        console.log(
            "total amt borrowed: %s",
            WETHUSDCPool.totalAmountBorrowed(address(borrower0))
        );

        vm.warp(block.timestamp + 10518975);

        vm.startPrank(lender1);
        USDC.approve(address(WETHUSDCPool), 500e6);
        WETHUSDCPool.deposit(500e6, address(lender1));
        vm.stopPrank();
        console.log(
            "lender1 balance: ",
            WETHUSDCPool.convertToAssets(WETHUSDCPool.balanceOf(lender1))
        );
        assertLt(WETHUSDCPool.balanceOf(address(lender1)), 500e6);
        assertLt(
            WETHUSDCPool.convertToAssets(WETHUSDCPool.balanceOf(lender1)),
            500e6
        );
    }

    function testMultipleLendersStartingShares() public {
        deployBase();
        vm.startPrank(lender0);
        USDC.mint(address(lender0), 100000e6);
        USDC.approve(address(WETHUSDCPool), 1000e6);
        WETHUSDCPool.deposit(1000e6, address(lender0));
        vm.stopPrank();
        assertEq(WETHUSDCPool.balanceOf(address(lender0)), 1000e6);
        console.log(
            "lender0 balance before: %s",
            WETHUSDCPool.convertToAssets(WETHUSDCPool.balanceOf(lender0))
        );

        vm.startPrank(lender1);
        USDC.approve(address(WETHUSDCPool), 500e6);
        WETHUSDCPool.deposit(500e6, address(lender1));
        vm.stopPrank();
        assertEq(WETHUSDCPool.balanceOf(address(lender1)), 500e6);
        console.log(
            "lender1 balance before: %s",
            WETHUSDCPool.convertToAssets(WETHUSDCPool.balanceOf(lender1))
        );
        uint256 lender0USDCBalanceBefore = USDC.balanceOf(address(lender0));
        uint256 lender1USDCBalanceBefore = USDC.balanceOf(address(lender1));

        vm.startPrank(borrower0);
        USDC.mint(address(borrower0), 100000e6);

        WETH.approve(address(WETHUSDCPool), 2e18);
        WETHUSDCPool.addCollateral(2e18);
        console.log(
            "Borrower col val: %s",
            WETHUSDCPool.userCollateralValue(address(borrower0))
        );
        WETHUSDCPool.borrow(1010e6);
        vm.stopPrank();
        console.log(
            "total amt borrowed: %s",
            WETHUSDCPool.totalAmountBorrowed(address(borrower0))
        );

        vm.warp(block.timestamp + 10518975);
        WETHUSDCPool.accrue();
        vm.warp(block.timestamp + 10518975);
        WETHUSDCPool.accrue();
        vm.warp(block.timestamp + 10518975);
        WETHUSDCPool.accrue();

        console.log(
            "borrower0 borrow amount after 1 yr: %s",
            WETHUSDCPool.totalAmountBorrowed(address(borrower0))
        );

        vm.startPrank(borrower0);
        USDC.approve(address(WETHUSDCPool), 1000000e6);
        WETHUSDCPool.repay(
            WETHUSDCPool.totalAmountBorrowed(address(borrower0))
        );
        vm.stopPrank();

        console.log(
            "lender0 balance after: %s",
            WETHUSDCPool.convertToAssets(WETHUSDCPool.balanceOf(lender0))
        );
        console.log(
            "lender1 balance after: %s",
            WETHUSDCPool.convertToAssets(WETHUSDCPool.balanceOf(lender1))
        );
        console.log(
            "protocol fee (USDC): %s",
            WETHUSDCPool.convertToAssets(WETHUSDCPool.balanceOf(address(this)))
        );

        vm.startPrank(lender0);
        // WETHUSDCPool.removeAsset(WETHUSDCPool.convertToAssets(WETHUSDCPool.balanceOf(lender0)));
        WETHUSDCPool.withdraw(
            WETHUSDCPool.maxWithdraw(address(lender0)),
            address(lender0),
            address(lender0)
        );
        vm.stopPrank();
        vm.startPrank(lender1);
        // WETHUSDCPool.removeAsset(WETHUSDCPool.convertToAssets(WETHUSDCPool.balanceOf(lender1)));
        WETHUSDCPool.withdraw(
            WETHUSDCPool.maxWithdraw(address(lender1)),
            address(lender1),
            address(lender1)
        );
        vm.stopPrank();
        console.log("PROTOCOL REVENUE:", USDC.balanceOf(address(feeVault)));

        assertGt(USDC.balanceOf(address(lender0)), lender0USDCBalanceBefore);
        assertGt(USDC.balanceOf(address(lender1)), lender1USDCBalanceBefore);
    }

    function testMultipleLendersMidEntryShares() public {
        deployBase();

        uint256 lender1USDCBalanceBefore = USDC.balanceOf(address(lender0));
        uint256 lender2USDCBalanceBefore = USDC.balanceOf(address(lender0));

        vm.startPrank(lender0);
        USDC.approve(address(WETHUSDCPool), 1200e6);
        WETHUSDCPool.deposit(1200e6, address(lender0));
        vm.stopPrank();
        assertEq(WETHUSDCPool.balanceOf(address(lender0)), 1200e6);
        console.log(
            "lender0 balance before: %s",
            WETHUSDCPool.convertToAssets(WETHUSDCPool.balanceOf(lender0))
        );

        vm.startPrank(borrower0);
        USDC.mint(address(borrower0), 1000000e6);
        WETH.approve(address(WETHUSDCPool), 2e18);
        WETHUSDCPool.addCollateral(2e18);
        console.log(
            "Borrower col val: %s",
            WETHUSDCPool.userCollateralValue(address(borrower0))
        );
        WETHUSDCPool.borrow(800e6);
        vm.stopPrank();
        console.log(
            "total amt borrowed: %s",
            WETHUSDCPool.totalAmountBorrowed(address(borrower0))
        );

        // vm.warp(block.timestamp+10518975);
        // WETHUSDCPool.accrue();
        vm.warp(block.timestamp + 10518975);
        WETHUSDCPool.accrue();
        vm.warp(block.timestamp + 10518975);
        WETHUSDCPool.accrue();

        vm.warp(block.timestamp + 10518975);
        WETHUSDCPool.accrue();

        console.log(
            "lender0 pool share after accrue: %s",
            WETHUSDCPool.balanceOf(address(lender0))
        );
        console.log(
            "lender0 balance after accrue: %s",
            WETHUSDCPool.convertToAssets(WETHUSDCPool.balanceOf(lender0))
        );
        console.log(
            "lender1 preview deposit(amount to shares): %s",
            WETHUSDCPool.previewDeposit(2)
        );
        console.log(
            "lender1 preview withdraw(amount to shares): %s",
            WETHUSDCPool.previewWithdraw(1e6)
        );
        console.log(
            "slippage: %s",
            WETHUSDCPool.previewWithdraw(1e6) - WETHUSDCPool.previewDeposit(1e6)
        );
        console.log(
            "depositAmt, totalSupply(), totalAssets(), :",
            WETHUSDCPool.totalSupply(),
            WETHUSDCPool.totalAssets()
        );

        vm.startPrank(lender1);
        USDC.approve(address(WETHUSDCPool), 500e6);
        WETHUSDCPool.deposit(500e6, address(lender1));
        vm.stopPrank();
        console.log(
            "lender0 pool share after lender1 deposits: %s",
            WETHUSDCPool.balanceOf(address(lender0))
        );
        console.log(
            "lender0 balance after lender1 deposits: %s",
            WETHUSDCPool.convertToAssets(WETHUSDCPool.balanceOf(lender0))
        );

        console.log(
            "lender1 pool share: %s",
            WETHUSDCPool.balanceOf(address(lender1))
        );
        assertLt(
            WETHUSDCPool.balanceOf(address(lender1)),
            WETHUSDCPool.convertToAssets(WETHUSDCPool.balanceOf(lender1))
        );
        console.log(
            "lender1 balance before (rounding error): %s",
            WETHUSDCPool.convertToAssets(WETHUSDCPool.balanceOf(lender1))
        );
        // console.log("lender1 balance before (rounding error2): %s", WETHUSDCPool.previewWithdraw(499999999));

        vm.warp(block.timestamp + 60);
        WETHUSDCPool.accrue();
        // console.log("lender1 balance after 1 min: %s", WETHUSDCPool.convertToAssets(WETHUSDCPool.balanceOf(lender1)));

        // console.log("borrower0 borrow amount after 1 yr: %s", WETHUSDCPool.totalAmountBorrowed(address(borrower0)));

        vm.startPrank(borrower0);
        USDC.approve(address(WETHUSDCPool), 1000000e6);
        WETHUSDCPool.repay(
            WETHUSDCPool.totalAmountBorrowed(address(borrower0))
        );
        vm.stopPrank();

        console.log(
            "lender0 balance after 1 min: %s",
            WETHUSDCPool.maxWithdraw(address(lender0))
        );
        // WETHUSDCPool.convertToAssets(WETHUSDCPool.balanceOf(lender0)));
        console.log(
            "lender1 balance after 1 min: %s",
            WETHUSDCPool.maxWithdraw(address(lender1))
        );
        // WETHUSDCPool.convertToAssets(WETHUSDCPool.balanceOf(lender1)));

        vm.startPrank(lender0);
        WETHUSDCPool.withdraw(
            WETHUSDCPool.maxWithdraw(address(lender0)),
            address(lender0),
            address(lender0)
        );
        vm.stopPrank();
        vm.startPrank(lender1);
        WETHUSDCPool.withdraw(
            WETHUSDCPool.maxWithdraw(address(lender1)),
            address(lender1),
            address(lender1)
        );
        vm.stopPrank();
        console.log("PROTOCOL REVENUE:", USDC.balanceOf(address(feeVault)));

        assertGt(USDC.balanceOf(address(lender0)), lender1USDCBalanceBefore);
        assertGt(USDC.balanceOf(address(lender1)), lender2USDCBalanceBefore);
    }

    function testInterestRateInsolvency() public {
        deployBase();
        vm.startPrank(lender0);
        USDC.mint(address(lender0), 100000e6);
        USDC.approve(address(WETHUSDCPool), 2000e6);
        WETHUSDCPool.deposit(1200e6, address(lender0));
        vm.stopPrank();
        // assertEq(WETHUSDCPool.balanceOf(address(lender0)), 4000e6);

        vm.startPrank(borrower0);
        WETH.approve(address(WETHUSDCPool), 1e18);
        WETHUSDCPool.addCollateral(1e18);
        console.log(
            "Borrower col val: %s",
            WETHUSDCPool.userCollateralValue(address(borrower0))
        );
        WETHUSDCPool.borrow(1000e6);
        vm.stopPrank();
        console.log(
            "total amt borrowed: %s",
            WETHUSDCPool.totalAmountBorrowed(address(borrower0))
        );

        assertEq(WETHUSDCPool.isSolvent(borrower0), true);

        vm.warp(block.timestamp + 10518975);
        WETHUSDCPool.accrue();
        console.log(
            "interest per sec: %s",
            WETHUSDCPool.getInterestPerSecond()
        );

        vm.warp(block.timestamp + 10518975);
        WETHUSDCPool.accrue();
        console.log(
            "interest per sec: %s",
            WETHUSDCPool.getInterestPerSecond()
        );

        vm.warp(block.timestamp + 10518975);
        WETHUSDCPool.accrue();
        console.log(
            "total amt borrowed: %s",
            WETHUSDCPool.totalAmountBorrowed(address(borrower0))
        );
        console.log(
            "interest per sec: %s",
            WETHUSDCPool.getInterestPerSecond()
        );

        vm.warp(block.timestamp + 10);
        WETHUSDCPool.accrue();
        console.log(
            "total amt borrowed 10 secs: %s",
            WETHUSDCPool.totalAmountBorrowed(address(borrower0))
        );
        console.log(
            "interest per sec: %s",
            WETHUSDCPool.getInterestPerSecond()
        );
        console.log("PROTOCOL REVENUE:", USDC.balanceOf(address(feeVault)));

        assertEq(WETHUSDCPool.isSolvent(borrower0), false);
        assertGt(USDC.balanceOf(address(feeVault)), 0);
    }

    function testLiquidateAllBorrow() public {
        deployBase();

        vm.startPrank(lender0);
        USDC.mint(address(lender0), 100000e6);
        uint256 lender1USDCBalanceBefore = USDC.balanceOf(address(lender0));
        USDC.approve(address(WETHUSDCPool), 2000e6);
        WETHUSDCPool.deposit(1210e6, address(lender0));
        vm.stopPrank();
        assertEq(WETHUSDCPool.balanceOf(address(lender0)), 1210e6);
        console.log(
            "lender0 balance before: %s",
            WETHUSDCPool.convertToAssets(WETHUSDCPool.balanceOf(lender0))
        );

        vm.startPrank(borrower0);
        WETH.approve(address(WETHUSDCPool), 1e18);
        WETHUSDCPool.addCollateral(1e18);
        WETHUSDCPool.borrow(1005e6);
        vm.stopPrank();
        assertEq(WETHUSDCPool.isSolvent(borrower0), true);
        console.log("START BORROW");
        console.log(
            "user collateral amt: %s",
            WETHUSDCPool.userCollateralAmount(address(borrower0))
        );
        console.log(
            "user col val: %s",
            WETHUSDCPool.userCollateralValue(address(borrower0))
        );
        console.log(
            "user max borrow: %s",
            (WETHUSDCPool.userCollateralValue(address(borrower0)) * 75) / 100
        );
        console.log(
            "user borrow: %s",
            WETHUSDCPool.totalAmountBorrowed(address(borrower0))
        );

        vm.warp(block.timestamp + 10518975);
        WETHUSDCPool.accrue();
        vm.warp(block.timestamp + 10518975);
        WETHUSDCPool.accrue();
        vm.warp(block.timestamp + 10518975);
        WETHUSDCPool.accrue();

        // uint256 colvalbefore = WETHUSDCPool.userCollateralValue(address(borrower0));
        // uint256 colamtbefore = WETHUSDCPool.userCollateralAmount(address(borrower0));
        console.log("INSOLVENT");
        console.log(
            "user collateral amt: %s",
            WETHUSDCPool.userCollateralAmount(address(borrower0))
        );
        console.log(
            "user col val: %s",
            WETHUSDCPool.userCollateralValue(address(borrower0))
        );
        console.log(
            "user max borrow: %s",
            (WETHUSDCPool.userCollateralValue(address(borrower0)) * 75) / 100
        );
        console.log(
            "user borrow: %s",
            WETHUSDCPool.totalAmountBorrowed(address(borrower0))
        );

        uint256 reduction = (WETHUSDCPool.totalAmountBorrowed(
            address(borrower0)
        ) * (10 ** WETH.decimals())) / WETHUSDCPool.exchangeRate(); //1e26-1e8 = 1e18
        console.log("collateral avail for liquidation: %s", reduction);

        // WETHUSDCPool.updateExchangeRate();
        assertEq(WETHUSDCPool.isSolvent(borrower0), false);

        vm.startPrank(liquidator0);
        USDC.approve(address(WETHUSDCPool), 1650791396);
        bool liquidated = WETHUSDCPool.liquidate(borrower0, 1650791396);
        vm.stopPrank();
        assertEq(liquidated, true);

        // uint256 colvalafter = WETHUSDCPool.userCollateralValue(address(borrower0));
        // uint256 diff = colvalbefore - colvalafter;
        // console.log(diff);

        console.log("LIQUIDATED");
        console.log(
            "user collateral amt: %s",
            WETHUSDCPool.userCollateralAmount(address(borrower0))
        );
        console.log(
            "user col val: %s",
            WETHUSDCPool.userCollateralValue(address(borrower0))
        );
        console.log(
            "user max borrow: %s",
            (WETHUSDCPool.userCollateralValue(address(borrower0)) * 75) / 100
        );
        console.log(
            "user borrow: %s",
            WETHUSDCPool.totalAmountBorrowed(address(borrower0))
        );

        console.log("liquidator WETH balance: %s", WETH.balanceOf(liquidator0));
        console.log(
            "liquidator WETH value: %s",
            (WETH.balanceOf(liquidator0) *
                (WETHUSDCPool.exchangeRate() * 1e10)) / 1e28
        );

        assertEq(
            WETH.balanceOf(liquidator0),
            reduction + ((reduction * 10000) / 1e5)
        ); //check if the liquidator 6% bonus goes to the liquidator
        assertEq(WETHUSDCPool.isSolvent(borrower0), true);
        assertEq(WETHUSDCPool.totalBorrow(), 0);
        assertEq(WETHUSDCPool.totalAmountBorrowed(borrower0), 0);

        console.log(
            "lender0 balance after: %s",
            WETHUSDCPool.convertToAssets(WETHUSDCPool.balanceOf(lender0))
        );
        console.log(WETHUSDCPool.balanceOf(address(lender0)));

        vm.startPrank(lender0);
        // WETHUSDCPool.redeem(1210000000, address(lender0), address(lender0));
        WETHUSDCPool.withdraw(
            WETHUSDCPool.maxWithdraw(address(lender0)),
            address(lender0),
            address(lender0)
        );
        // WETHUSDCPool.removeAsset(WETHUSDCPool.convertToAssets(WETHUSDCPool.balanceOf(lender0)));
        vm.stopPrank();
        // check if lender asset increases after liquidation and withdrawal
        console.log("PROTOCOL REVENUE:", USDC.balanceOf(address(feeVault)));

        assertGt(USDC.balanceOf(address(lender0)), lender1USDCBalanceBefore);
    }

    function testLiquidateSomeBorrow() public {
        deployBase();

        vm.startPrank(lender0);
        USDC.mint(address(lender0), 100000e6);
        uint256 lender1USDCBalanceBefore = USDC.balanceOf(address(lender0));
        USDC.approve(address(WETHUSDCPool), 2000e6);
        WETHUSDCPool.deposit(1210e6, address(lender0));
        vm.stopPrank();
        assertLt(USDC.balanceOf(address(lender0)), lender1USDCBalanceBefore);

        assertEq(WETHUSDCPool.balanceOf(address(lender0)), 1210e6);
        console.log(
            "lender0 balance before: %s",
            WETHUSDCPool.convertToAssets(WETHUSDCPool.balanceOf(lender0))
        );

        vm.startPrank(borrower0);
        WETH.approve(address(WETHUSDCPool), 1e18);
        WETHUSDCPool.addCollateral(1e18);
        WETHUSDCPool.borrow(1005e6);
        vm.stopPrank();
        assertEq(WETHUSDCPool.isSolvent(borrower0), true);
        console.log("START BORROW");
        console.log(
            "user collateral amt: %s",
            WETHUSDCPool.userCollateralAmount(address(borrower0))
        );
        console.log(
            "user col val: %s",
            WETHUSDCPool.userCollateralValue(address(borrower0))
        );
        console.log(
            "user max borrow: %s",
            (WETHUSDCPool.userCollateralValue(address(borrower0)) * 75) / 100
        );
        console.log(
            "user borrow: %s",
            WETHUSDCPool.totalAmountBorrowed(address(borrower0))
        );

        vm.warp(block.timestamp + 10518975);
        WETHUSDCPool.accrue();
        vm.warp(block.timestamp + 10518975);
        WETHUSDCPool.accrue();
        vm.warp(block.timestamp + 10518975);
        WETHUSDCPool.accrue();

        // uint256 colvalbefore = WETHUSDCPool.userCollateralValue(address(borrower0));
        // uint256 colamtbefore = WETHUSDCPool.userCollateralAmount(address(borrower0));
        console.log("INSOLVENT");
        console.log(
            "user collateral amt: %s",
            WETHUSDCPool.userCollateralAmount(address(borrower0))
        );
        console.log(
            "user col val: %s",
            WETHUSDCPool.userCollateralValue(address(borrower0))
        );
        console.log(
            "user max borrow: %s",
            (WETHUSDCPool.userCollateralValue(address(borrower0)) * 75) / 100
        );
        console.log(
            "user borrow: %s",
            WETHUSDCPool.totalAmountBorrowed(address(borrower0))
        );

        uint256 reduction = (WETHUSDCPool.totalAmountBorrowed(
            address(borrower0)
        ) * (10 ** WETH.decimals())) / WETHUSDCPool.exchangeRate(); //1e24-1e6 = 1e18
        console.log("collateral avail for liquidation: %s", reduction);

        // WETHUSDCPool.updateExchangeRate();
        assertEq(WETHUSDCPool.isSolvent(borrower0), false);

        vm.startPrank(liquidator0);
        uint borrowed = WETHUSDCPool.totalAmountBorrowed(borrower0);
        USDC.approve(address(WETHUSDCPool), 1560791396);
        bool liquidated = WETHUSDCPool.liquidate(borrower0, 1560791396);
        vm.stopPrank();
        assertEq(liquidated, true);

        // uint256 colvalafter = WETHUSDCPool.userCollateralValue(address(borrower0));
        // uint256 diff = colvalbefore - colvalafter;
        // console.log(diff);

        console.log("LIQUIDATED");
        console.log(
            "user collateral amt: %s",
            WETHUSDCPool.userCollateralAmount(address(borrower0))
        );
        console.log(
            "user col val: %s",
            WETHUSDCPool.userCollateralValue(address(borrower0))
        );
        console.log(
            "user max borrow: %s",
            (WETHUSDCPool.userCollateralValue(address(borrower0)) * 75) / 100
        );
        console.log(
            "user borrow: %s",
            WETHUSDCPool.totalAmountBorrowed(address(borrower0))
        );

        console.log("liquidator WETH balance: %s", WETH.balanceOf(liquidator0));
        console.log(
            "liquidator WETH value: %s",
            (WETH.balanceOf(liquidator0) *
                (WETHUSDCPool.exchangeRate() * 1e10)) / 1e30
        );

        // assertEq(WETH.balanceOf(liquidator0), reduction+(reduction*10000/1e5));//check if the liquidator 6% bonus goes to the liquidator
        assertEq(WETHUSDCPool.isSolvent(borrower0), true);
        assertEq(
            WETHUSDCPool.totalAmountBorrowed(borrower0),
            borrowed - 1560791396
        );
        console.log(
            "lender0 balance after: %s",
            WETHUSDCPool.convertToAssets(WETHUSDCPool.balanceOf(lender0))
        );
        console.log(WETHUSDCPool.balanceOf(address(lender0)));

        console.log("PROTOCOL REVENUE:", USDC.balanceOf(address(feeVault)));
    }

    function testLiquidateSomeBorrowFuzz(uint amount) public {
        deployBase();
        amount = bound(amount, 0, 1000e6);

        vm.startPrank(lender0);
        USDC.mint(address(lender0), 100000e6);
        uint256 lender1USDCBalanceBefore = USDC.balanceOf(address(lender0));
        USDC.approve(address(WETHUSDCPool), 2000e6);
        WETHUSDCPool.deposit(1210e6, address(lender0));
        vm.stopPrank();
        assertLt(USDC.balanceOf(address(lender0)), lender1USDCBalanceBefore);

        assertEq(WETHUSDCPool.balanceOf(address(lender0)), 1210e6);
        console.log(
            "lender0 balance before: %s",
            WETHUSDCPool.convertToAssets(WETHUSDCPool.balanceOf(lender0))
        );

        vm.startPrank(borrower0);
        WETH.approve(address(WETHUSDCPool), 1e18);
        WETHUSDCPool.addCollateral(1e18);
        WETHUSDCPool.borrow(1005e6);
        vm.stopPrank();
        assertEq(WETHUSDCPool.isSolvent(borrower0), true);
        console.log("START BORROW");
        console.log(
            "user collateral amt: %s",
            WETHUSDCPool.userCollateralAmount(address(borrower0))
        );
        console.log(
            "user col val: %s",
            WETHUSDCPool.userCollateralValue(address(borrower0))
        );
        console.log(
            "user max borrow: %s",
            (WETHUSDCPool.userCollateralValue(address(borrower0)) * 75) / 100
        );
        console.log(
            "user borrow: %s",
            WETHUSDCPool.totalAmountBorrowed(address(borrower0))
        );

        vm.warp(block.timestamp + 10518975);
        WETHUSDCPool.accrue();
        vm.warp(block.timestamp + 10518975);
        WETHUSDCPool.accrue();
        vm.warp(block.timestamp + 10518975);
        WETHUSDCPool.accrue();

        // uint256 colvalbefore = WETHUSDCPool.userCollateralValue(address(borrower0));
        // uint256 colamtbefore = WETHUSDCPool.userCollateralAmount(address(borrower0));
        console.log("INSOLVENT");
        console.log(
            "user collateral amt: %s",
            WETHUSDCPool.userCollateralAmount(address(borrower0))
        );
        console.log(
            "user col val: %s",
            WETHUSDCPool.userCollateralValue(address(borrower0))
        );
        console.log(
            "user max borrow: %s",
            (WETHUSDCPool.userCollateralValue(address(borrower0)) * 75) / 100
        );
        console.log(
            "user borrow: %s",
            WETHUSDCPool.totalAmountBorrowed(address(borrower0))
        );

        uint256 reduction = (WETHUSDCPool.totalAmountBorrowed(
            address(borrower0)
        ) * (10 ** WETH.decimals())) / WETHUSDCPool.exchangeRate(); //1e24-1e6 = 1e18
        console.log("collateral avail for liquidation: %s", reduction);

        // WETHUSDCPool.updateExchangeRate();
        assertEq(WETHUSDCPool.isSolvent(borrower0), false);

        vm.startPrank(liquidator0);
        uint borrowed = WETHUSDCPool.totalAmountBorrowed(borrower0);
        USDC.approve(address(WETHUSDCPool), amount);
        bool liquidated = WETHUSDCPool.liquidate(borrower0, amount);
        vm.stopPrank();
        assertEq(liquidated, true);
    }

    function testSelfLiquidate() public {
        deployBase();

        vm.startPrank(lender0);
        USDC.mint(address(lender0), 100000e6);
        uint256 lender1USDCBalanceBefore = USDC.balanceOf(address(lender0));
        USDC.approve(address(WETHUSDCPool), 2000e6);
        WETHUSDCPool.deposit(1210e6, address(lender0));
        vm.stopPrank();
        assertLt(USDC.balanceOf(address(lender0)), lender1USDCBalanceBefore);

        assertEq(WETHUSDCPool.balanceOf(address(lender0)), 1210e6);
        console.log(
            "lender0 balance before: %s",
            WETHUSDCPool.convertToAssets(WETHUSDCPool.balanceOf(lender0))
        );

        vm.startPrank(borrower0);
        WETH.approve(address(WETHUSDCPool), 1e18);
        WETHUSDCPool.addCollateral(1e18);
        WETHUSDCPool.borrow(1005e6);
        vm.stopPrank();
        assertEq(WETHUSDCPool.isSolvent(borrower0), true);
        console.log("START BORROW");
        console.log(
            "user collateral amt: %s",
            WETHUSDCPool.userCollateralAmount(address(borrower0))
        );
        console.log(
            "user col val: %s",
            WETHUSDCPool.userCollateralValue(address(borrower0))
        );
        console.log(
            "user max borrow: %s",
            (WETHUSDCPool.userCollateralValue(address(borrower0)) * 75) / 100
        );
        console.log(
            "user borrow: %s",
            WETHUSDCPool.totalAmountBorrowed(address(borrower0))
        );

        vm.warp(block.timestamp + 10518975);
        WETHUSDCPool.accrue();
        vm.warp(block.timestamp + 10518975);
        WETHUSDCPool.accrue();
        vm.warp(block.timestamp + 10518975);
        WETHUSDCPool.accrue();

        // uint256 colvalbefore = WETHUSDCPool.userCollateralValue(address(borrower0));
        // uint256 colamtbefore = WETHUSDCPool.userCollateralAmount(address(borrower0));
        console.log("INSOLVENT");
        console.log(
            "user collateral amt: %s",
            WETHUSDCPool.userCollateralAmount(address(borrower0))
        );
        console.log(
            "user col val: %s",
            WETHUSDCPool.userCollateralValue(address(borrower0))
        );
        console.log(
            "user max borrow: %s",
            (WETHUSDCPool.userCollateralValue(address(borrower0)) * 75) / 100
        );
        console.log(
            "user borrow: %s",
            WETHUSDCPool.totalAmountBorrowed(address(borrower0))
        );

        uint256 reduction = (WETHUSDCPool.totalAmountBorrowed(
            address(borrower0)
        ) * (10 ** WETH.decimals())) / WETHUSDCPool.exchangeRate(); //1e24-1e6 = 1e18
        console.log("collateral avail for liquidation: %s", reduction);

        // WETHUSDCPool.updateExchangeRate();
        assertEq(WETHUSDCPool.isSolvent(borrower0), false);

        vm.startPrank(borrower0);
        USDC.mint(address(borrower0), 100000e6);
        USDC.approve(address(WETHUSDCPool), 1650791396);
        bool liquidated = WETHUSDCPool.liquidate(borrower0, 1650791396);
        vm.stopPrank();
        assertEq(liquidated, true);

        // uint256 colvalafter = WETHUSDCPool.userCollateralValue(address(borrower0));
        // uint256 diff = colvalbefore - colvalafter;
        // console.log(diff);

        console.log("LIQUIDATED");
        console.log(
            "user collateral amt: %s",
            WETHUSDCPool.userCollateralAmount(address(borrower0))
        );
        console.log(
            "user col val: %s",
            WETHUSDCPool.userCollateralValue(address(borrower0))
        );
        console.log(
            "user max borrow: %s",
            (WETHUSDCPool.userCollateralValue(address(borrower0)) * 75) / 100
        );
        console.log(
            "user borrow: %s",
            WETHUSDCPool.totalAmountBorrowed(address(borrower0))
        );

        console.log("liquidator WETH balance: %s", WETH.balanceOf(borrower0));
        console.log(
            "liquidator WETH value: %s",
            (WETH.balanceOf(borrower0) * (WETHUSDCPool.exchangeRate() * 1e10)) /
                1e30
        );

        assertGt(
            WETH.balanceOf(borrower0),
            reduction + ((reduction * 10000) / 1e5)
        ); //check if the liquidator 6% bonus goes to the liquidator
        assertEq(WETHUSDCPool.isSolvent(borrower0), true);
        assertEq(WETHUSDCPool.totalBorrow(), 0);
        console.log(
            "lender0 balance after: %s",
            WETHUSDCPool.convertToAssets(WETHUSDCPool.balanceOf(lender0))
        );
        console.log(WETHUSDCPool.balanceOf(address(lender0)));

        console.log("PROTOCOL REVENUE:", USDC.balanceOf(address(feeVault)));
        console.log(WETHUSDCPool.exchangeRate());
    }

    function testLiquidateSolvent() public {
        deployBase();
        // uint256 lender1USDCBalanceBefore = USDC.balanceOf(address(lender0));

        vm.startPrank(lender0);
        USDC.mint(address(lender0), 100000e6);
        USDC.approve(address(WETHUSDCPool), 2000e6);
        WETHUSDCPool.deposit(1208e6, address(lender0));
        vm.stopPrank();
        assertEq(WETHUSDCPool.balanceOf(address(lender0)), 1208e6);
        console.log(
            "lender0 balance before: %s",
            WETHUSDCPool.convertToAssets(WETHUSDCPool.balanceOf(lender0))
        );

        vm.startPrank(borrower0);
        WETH.approve(address(WETHUSDCPool), 1e18);
        WETHUSDCPool.addCollateral(1e18);
        WETHUSDCPool.borrow(1005e6);
        vm.stopPrank();

        vm.startPrank(liquidator0);
        USDC.approve(address(WETHUSDCPool), 1005e6);
        bool liquidated = WETHUSDCPool.liquidate(borrower0, 1005e6);
        vm.stopPrank();
        assertEq(WETH.balanceOf(address(liquidator0)), 0);
        assertEq(liquidated, false);
    }

    function testBorrowAll() public {
        deployBase();

        vm.startPrank(lender0);
        USDC.mint(address(lender0), 10000e6);
        USDC.approve(address(WETHUSDCPool), 1000e6);
        WETHUSDCPool.deposit(1000e6, address(lender0));
        vm.stopPrank();
        assertEq(WETHUSDCPool.balanceOf(address(lender0)), 1000e6);
        console.log(
            "lender0 balance before: %s",
            WETHUSDCPool.convertToAssets(WETHUSDCPool.balanceOf(lender0))
        );

        vm.startPrank(borrower0);
        WETH.approve(address(WETHUSDCPool), 1e18);
        WETHUSDCPool.addCollateral(1e18);
        WETHUSDCPool.borrow(1000e6);
        vm.stopPrank();
        console.log("ASSET:", WETHUSDCPool.totalAsset());
        console.log("BORROW:", WETHUSDCPool.totalBorrow());
        console.log(
            "UTILIZATION: ",
            (WETHUSDCPool.totalBorrow() * 1e18) / WETHUSDCPool.totalAssets()
        );
        console.log(WETHUSDCPool.getInterestPerSecond() / 317097920, "%");

        vm.warp(block.timestamp + 1 days);
        console.log("TOTAL ASSET:", WETHUSDCPool.totalAsset());
        WETHUSDCPool.accrue();
        console.log(WETHUSDCPool.getInterestPerSecond() / 317097920, "%");
        assertEq(USDC.balanceOf(address(feeVault)), 0);

        vm.warp(block.timestamp + 8 hours);
        WETHUSDCPool.accrue();
        console.log(WETHUSDCPool.getInterestPerSecond() / 317097920, "%");
        vm.warp(block.timestamp + 8 hours);
        WETHUSDCPool.accrue();
        console.log(WETHUSDCPool.getInterestPerSecond() / 317097920, "%");

        vm.startPrank(lender0);
        USDC.approve(address(WETHUSDCPool), 1000e6);
        WETHUSDCPool.deposit(1000e6, address(lender0));
        vm.stopPrank();

        console.log(
            "UTILIZATION: ",
            (WETHUSDCPool.totalBorrow() * 1e18) / WETHUSDCPool.totalAssets()
        );

        vm.warp(block.timestamp + 8 hours);
        WETHUSDCPool.accrue();
        console.log(WETHUSDCPool.getInterestPerSecond() / 317097920, "%");
        vm.warp(block.timestamp + 8 hours);
        WETHUSDCPool.accrue();
        console.log(WETHUSDCPool.getInterestPerSecond() / 317097920, "%");
        vm.warp(block.timestamp + 8 hours);
        WETHUSDCPool.accrue();
        console.log(WETHUSDCPool.getInterestPerSecond() / 317097920, "%");
        vm.warp(block.timestamp + 8 hours);
        WETHUSDCPool.accrue();
        console.log(WETHUSDCPool.getInterestPerSecond() / 317097920, "%");
        vm.warp(block.timestamp + 8 hours);
        WETHUSDCPool.accrue();
        console.log(WETHUSDCPool.getInterestPerSecond() / 317097920, "%");
        vm.warp(block.timestamp + 14 days);
        WETHUSDCPool.accrue();
        console.log(WETHUSDCPool.getInterestPerSecond() / 317097920, "%");

        console.log("ASSET:", WETHUSDCPool.totalAsset());
        console.log("BORROW:", WETHUSDCPool.totalBorrow());
        console.log(
            "UTILIZATION: ",
            (WETHUSDCPool.totalBorrow() * 1e18) / WETHUSDCPool.totalAssets()
        );

        console.log(WETHUSDCPool.totalAmountBorrowed(address(borrower0)));
        console.log(WETHUSDCPool.getInterestPerSecond() / 317097920, "%");
        console.log("PROTOCOL REVENUE:", USDC.balanceOf(address(feeVault)));
    }

    function testChangeFeeTo() public {
        deployBase();
        mediumRiskMasterContract.setFeeTo(address(this));
        vm.startPrank(lender0);
        USDC.mint(address(lender0), 10000e6);
        USDC.approve(address(WETHUSDCPool), 1000e6);
        WETHUSDCPool.deposit(1000e6, address(lender0));
        vm.stopPrank();

        vm.startPrank(borrower0);
        WETH.approve(address(WETHUSDCPool), 1e18);
        WETHUSDCPool.addCollateral(1e18);
        WETHUSDCPool.borrow(850e6);
        vm.stopPrank();

        vm.warp(block.timestamp + 8 hours);
        WETHUSDCPool.accrue();
        assertGt(USDC.balanceOf(address(this)), 0);
        assertEq(USDC.balanceOf(address(feeVault)), 0);
        console.log("owner bal:", USDC.balanceOf(address(this)));
        console.log("fee vault bal:", USDC.balanceOf(address(feeVault)));

        mediumRiskMasterContract.setFeeTo(address(feeVault));

        vm.warp(block.timestamp + 8 hours);
        WETHUSDCPool.accrue();
        console.log("fee vault bal:", USDC.balanceOf(address(feeVault)));
        assertGt(USDC.balanceOf(address(feeVault)), 0);

        vm.expectRevert("NenoLend: feeTo is zero address");
        mediumRiskMasterContract.setFeeTo(address(0x0));
    }

    function testDepositDonate() public {
        deployBase();
        vm.startPrank(lender0);
        USDC.mint(address(lender0), 10000e6);
        uint balBefore = USDC.balanceOf(lender0);
        USDC.approve(address(WETHUSDCPool), 1000e6);
        WETHUSDCPool.deposit(1000e6, address(lender0));
        vm.stopPrank();

        vm.startPrank(lender1);
        USDC.mint(address(lender1), 10000e6);
        USDC.approve(address(WETHUSDCPool), 1000e6);
        WETHUSDCPool.deposit(1000e6, address(lender0));
        vm.stopPrank();

        assertGt(WETHUSDCPool.balanceOf(lender0), 1000e6);
        assertEq(WETHUSDCPool.balanceOf(lender0), 2000e6);

        vm.startPrank(lender0);
        WETHUSDCPool.withdraw(2000e6, address(lender0), address(lender0));
        vm.stopPrank();
        assertGt(USDC.balanceOf(lender0), balBefore);
    }

    function testTransfer() public {
        deployBase();
        vm.startPrank(lender0);
        USDC.mint(address(lender0), 10000e6);
        uint balBefore = USDC.balanceOf(lender0);
        USDC.approve(address(WETHUSDCPool), 1000e6);
        WETHUSDCPool.deposit(1000e6, address(lender0));
        WETHUSDCPool.transfer(lender1, 1000e6);
        vm.stopPrank();

        assertEq(WETHUSDCPool.balanceOf(lender0), 0);
    }

    function testTransferFrom() public {
        deployBase();
        vm.startPrank(lender0);
        USDC.mint(address(lender0), 10000e6);
        uint balBefore = USDC.balanceOf(lender0);
        USDC.approve(address(WETHUSDCPool), 1000e6);
        WETHUSDCPool.deposit(1000e6, address(lender0));
        WETHUSDCPool.approve(address(lender1), 1000e6);
        vm.stopPrank();

        vm.startPrank(lender1);
        WETHUSDCPool.transferFrom(lender0, lender1, 1000e6);
        vm.stopPrank();

        assertEq(WETHUSDCPool.balanceOf(lender0), 0);
    }
}
