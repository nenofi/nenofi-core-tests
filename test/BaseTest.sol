pragma solidity 0.8.18;

import "forge-std/Test.sol";
import "../src/mocks/MockERC20.sol";
// import "../src/mocks/MockIsolatedLending.sol";
import "../src/mocks/MockPriceFeed.sol";

import "../src/IsolatedLendingV01MediumRisk.sol";
import "../src/factories/NenoFactory.sol";
import "../src/NenoOracle.sol";
import "../src/MultiFeeDistribution.sol";
import "../src/Neno.sol";
import "../src/MasterChef.sol";

abstract contract BaseTest is Test {
    uint256 constant USDC_1 = 1e6;
    uint256 constant USDC_100K = 1e11; // 1e5 = 100K tokens with 6 decimals
    uint256 constant TOKEN_1 = 1e18;
    uint256 constant TOKEN_100K = 1e23; // 1e5 = 100K tokens with 18 decimals
    uint256 constant TOKEN_1M = 1e24; // 1e6 = 1M tokens with 18 decimals
    uint256 constant TOKEN_100M = 1e26; // 1e8 = 100M tokens with 18 decimals
    uint256 constant TOKEN_10B = 1e28; // 1e10 = 10B tokens with 18 decimals
    uint256 constant PAIR_1 = 1e9;

    MasterChef masterChef;

    MockERC20 WETH;
    MockERC20 USDC;
    MockERC20 WSTETH;
    MockERC20 USDT;
    MockERC20 NENO;

    MockPriceFeed ethFeed;
    MockPriceFeed usdcFeed;
    MockPriceFeed sequencerUpFeed;

    NenoFactory nenoFactory;
    NenoOracle wethOracle;
    NenoOracle usdcOracle;
    IsolatedLendingV01MediumRisk mediumRiskMasterContract;

    IsolatedLendingV01MediumRisk WETHUSDCPool;
    IsolatedLendingV01MediumRisk WETHUSDTPool;

    MultiFeeDistribution feeVault;
    // address feeVault = address(0x11);

    address lender0 = address(0x1);
    address lender1 = address(0x2);
    address lender2 = address(0x3);
    address[] lenders;

    address borrower0 = address(0x4);
    address borrower1 = address(0x5);
    address borrower2 = address(0x6);
    address[] borrowers;

    address liquidator0 = address(0x7);
    address nenoHolder = address(0x8);
    address nenoHolder1 = address(0x10);

    address rewarder = address(0x11);

    function initUsers() public {
        lenders = new address[](3);
        lenders[0] = address(lender0);
        lenders[1] = address(lender1);
        lenders[2] = address(lender2);

        borrowers = new address[](3);
        borrowers[0] = address(borrower0);
        borrowers[1] = address(borrower1);
        borrowers[2] = address(borrower2);
    }

    function deployTokens() public {
        USDC = new MockERC20("USDC", "USDC", 6);
        USDT = new MockERC20("USDT", "USDT", 6);
        WETH = new MockERC20("Wrapped ETH", "WETH", 18);
        WSTETH = new MockERC20("Wrapped ETH", "WETH", 18);
        NENO = new MockERC20("NENO", "NENO", 18);
    }

    function mintStables() public {
        for (uint256 i = 0; i < lenders.length; ++i) {
            USDC.mint(lenders[i], USDC_100K);
            // console.log("user", i, USDC.balanceOf(address(users[i])));
            USDT.mint(lenders[i], USDC_100K);
        }

        for (uint256 i = 0; i < borrowers.length; ++i) {
            WETH.mint(borrowers[i], TOKEN_1 * 2);
            // console.log("user", i, USDC.balanceOf(address(users[i])));
        }

        USDC.mint(liquidator0, 100_000_000e6);
        NENO.mint(nenoHolder, 100e18);
        NENO.mint(nenoHolder1, 50e18);
        WETH.mint(rewarder, 100e18);
    }

    function deployMasterChef() public {
        // masterChef = new MasterChef(NENO, address(this), 1e18, block.timestamp);
        masterChef = new MasterChef(1e18, 1000e18);
    }

    function deployOracles() public {
        sequencerUpFeed = new MockPriceFeed(8, 0);
        ethFeed = new MockPriceFeed(8, 183950000000);
        usdcFeed = new MockPriceFeed(8, 100000000);
        wethOracle = new NenoOracle(
            MockPriceFeed(ethFeed),
            MockPriceFeed(usdcFeed),
            6
        );
        usdcOracle = new NenoOracle(
            MockPriceFeed(usdcFeed),
            MockPriceFeed(ethFeed),
            18
        );
    }

    function deployMultiFeeDistribution() public {
        feeVault = new MultiFeeDistribution(address(NENO));
        feeVault.addReward(address(USDC));
    }

    function deployFactory() public {
        nenoFactory = new NenoFactory();
    }

    function deployIsolatedLending() public {
        nenoFactory = new NenoFactory();
        mediumRiskMasterContract = new IsolatedLendingV01MediumRisk(
            address(feeVault),
            address(sequencerUpFeed)
        );
        mediumRiskMasterContract.setFeeTo(address(feeVault));
        // console.log(mediumRiskMasterContract.feeTo());
        // mediumRiskMasterContract = new IsolatedLendingV01MediumRisk(address(USDC), "USDC vault", "usdc/xxx");
        WETHUSDCPool = IsolatedLendingV01MediumRisk(
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
    }

    function deployIsolatedLendings() public {
        nenoFactory = new NenoFactory();
        mediumRiskMasterContract = new IsolatedLendingV01MediumRisk(
            address(feeVault),
            address(sequencerUpFeed)
        );
        mediumRiskMasterContract.setFeeTo(address(feeVault));
        WETHUSDCPool = IsolatedLendingV01MediumRisk(
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

        WETHUSDTPool = IsolatedLendingV01MediumRisk(
            nenoFactory.deploy(
                address(mediumRiskMasterContract),
                abi.encode(
                    address(wethOracle),
                    address(WETH),
                    address(USDT),
                    "NenoLend MediumRisk: Wrapped ETH/Tether USD-Chainlink",
                    "nlmr-WETH/USDT-LINK"
                ),
                true
            )
        );
    }

    function depositAssetToLendings() public {
        for (uint256 i = 0; i < lenders.length; i++) {
            vm.startPrank(address(lenders[i]));
            USDC.approve(
                address(WETHUSDCPool),
                USDC.balanceOf(address(lenders[i]))
            );
            WETHUSDCPool.deposit(
                USDC.balanceOf(address(lenders[i])),
                address(lenders[i])
            );
            vm.stopPrank();
        }

        for (uint256 i = 0; i < lenders.length; i++) {
            vm.startPrank(address(lenders[i]));
            USDT.approve(
                address(WETHUSDTPool),
                USDT.balanceOf(address(lenders[i]))
            );
            WETHUSDTPool.deposit(
                USDT.balanceOf(address(lenders[i])),
                address(lenders[i])
            );
            vm.stopPrank();
        }
    }

    function depositAssetToLending() public {
        for (uint256 i = 0; i < lenders.length; i++) {
            vm.startPrank(address(lenders[i]));
            USDC.approve(
                address(WETHUSDCPool),
                USDC.balanceOf(address(lenders[i]))
            );
            WETHUSDCPool.deposit(
                USDC.balanceOf(address(lenders[i])),
                address(lenders[i])
            );
            // WETHUSDCPool.deposit(USDC.balanceOf(address(lenders[i])), address(lenders[i]));
            // console.log("deposit successful");
            // console.log("user", i, USDC.balanceOf(address(users[i])));
            vm.stopPrank();
        }
    }

    function depositSomeAssetsToLending() public {
        for (uint256 i = 0; i < lenders.length; i++) {
            vm.startPrank(address(lenders[i]));
            USDC.approve(
                address(WETHUSDCPool),
                USDC.balanceOf(address(lenders[i]))
            );
            WETHUSDCPool.deposit(120e6, address(lenders[i]));
            // WETHUSDCPool.deposit(USDC.balanceOf(address(lenders[i])), address(lenders[i]));
            // console.log("deposit successful");
            // console.log("user", i, USDC.balanceOf(address(users[i])));
            vm.stopPrank();
        }
    }

    function depositCollateralToPool() public {
        for (uint256 i = 0; i < borrowers.length; i++) {
            vm.startPrank(address(borrowers[i]));
            WETH.approve(
                address(WETHUSDCPool),
                WETH.balanceOf(address(borrowers[i]))
            );
            WETHUSDCPool.addCollateral(WETH.balanceOf(address(borrowers[i])));
            // WETHUSDCPool.deposit(USDC.balanceOf(address(lenders[i])), address(lenders[i]));
            // console.log("deposit successful");
            // console.log("user", i, USDC.balanceOf(address(users[i])));
            vm.stopPrank();
        }
    }

    function borrowAssetFromPool() public {
        for (uint256 i = 0; i < borrowers.length; i++) {
            vm.startPrank(address(borrowers[i]));
            WETHUSDCPool.borrow(100e6);
            // WETHUSDCPool.deposit(USDC.balanceOf(address(lenders[i])), address(lenders[i]));
            // console.log("deposit successful");
            // console.log("user", i, USDC.balanceOf(address(users[i])));
            vm.stopPrank();
        }
    }
}
