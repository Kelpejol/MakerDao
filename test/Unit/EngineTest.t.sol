// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import {Test, console} from "forge-std/Test.sol";
import {DeployEngine} from "../../script/DeployEngine.s.sol";
import {Engine} from "../../src/Engine.sol";
import {NetworkConfig} from "../../script/Config/NetworkConfig.sol";
import {Venom} from "../../src/Venom.sol";
import {Viper} from "../../src/Viper.sol";
import {TimeLock} from "../../src/TimeLock.sol";
import {Ancestor} from "../../src/Ancestor.sol";
import {WETH} from "../../src/Weth.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {MockV3Aggregator} from "../Mocks/MockV3Aggregator.sol";
import {Vm} from "forge-std/Vm.sol";
import {EarlyAdopters} from "../../src/EarlyAdopter.sol";
import {Crowdsale} from "../../src/Crowdsale.sol";

contract EngineTest is Test {
    DeployEngine deployer;
    Engine engine;
    NetworkConfig network;
    Venom venom;
    TimeLock timelock;
    Viper viper;
    Ancestor ancestor;

    address weth;
    address pricefeed;

    uint256 private constant actualLiquidationThreshold = 150e18;
    uint256 private constant actualPenaltyFee = 1 ether;
    uint256 private constant actualStabilityFee = 3e15;
    uint256 private constant totalTokenDeposited = 8000e18;

    uint256 private constant EARLYADOPTERS_MIN_AMOUNT_TO_DEPOSIT = 30e18;
    uint256 private constant EARLYADOPTERS_MAX_AMOUNT_TO_DEPOSIT = 300e18;
    uint256 private constant TOTAL_TOKEN_DEPOSITED = 8000e18;
    uint256 private constant WETH_MINT_AMOUNT = 10000e18;
    uint256 private constant INVESTOR_MAX_TOKEN_CAP = 300e18;
    address private WALLET_ADDRESS;

    uint256 private constant VOTING_DELAY = 7200;
    uint256 private constant VOTING_PERIOD = 50400;
    uint256 private constant MIN_DELAY = 7 days;

    address[] targets;
    bytes[] calldatas;
    uint256[] values;

    event CollateralDeposited(
        address indexed _from,
        address indexed collateralDeposited,
        uint256 indexed _amountToDeposit
    );

    event RewardClaimed(address indexed _beneficiary, uint256 indexed _amount);

    function setUp() external {
        deployer = new DeployEngine();
        (
            engine,
            network,
            timelock,
            venom,
            viper,
            ancestor,
            WALLET_ADDRESS
        ) = deployer.run();
        (weth, pricefeed, , , , ) = network.activeNetworkConfig();
        for (uint160 i = 1; i < 12; i++) {
            vm.startPrank(WALLET_ADDRESS);
            WETH(weth).mint(address(i), WETH_MINT_AMOUNT);

            
            vm.stopPrank();
        }
    }

    // --------------------------
    //   CONSTRUCTOR TEST
    //  ----------------------------

    function testCollateralInitializes() external {
        uint256 index = 0;

        (
            address collateralAddress,
            address collateralPriceFeed,
            uint256 liquidationThreshold,
            uint256 penaltyFee,
            uint256 stabilityFee
        ) = engine.getCollateralInfo(index);

        assertEq(collateralAddress, weth);
        assertEq(collateralPriceFeed, pricefeed);
        assertEq(liquidationThreshold, actualLiquidationThreshold);
        assertEq(penaltyFee, actualPenaltyFee);
        assertEq(stabilityFee, actualStabilityFee);
    }

    // --------------------------------
    //  EARLY ADOPTERS DEPOSIT TEST
    //   --------------------------------

    function testEarlyAdoptersDepositRevertWithInvalidAddress() external {
        address beneficiary = address(0);
        uint256 amount = 30e18;
        vm.startPrank(address(1));
        ERC20(weth).approve(address(engine), amount);
        vm.expectRevert(
            (
                abi.encodeWithSelector(
                    EarlyAdopters.EarlyAdopters__DepositNotValid.selector,
                    beneficiary,
                    EARLYADOPTERS_MAX_AMOUNT_TO_DEPOSIT,
                    EARLYADOPTERS_MIN_AMOUNT_TO_DEPOSIT,
                    block.timestamp
                )
            )
        );
        engine.deposit(beneficiary, amount);
        vm.stopPrank();
    }

    function testEarlyAdoptersDepositRevertWithInvalidAmount() external {
        address beneficiary = address(1);
        uint256 amount = 29e18;
        vm.startPrank(address(1));
        ERC20(weth).approve(address(engine), amount);
        vm.expectRevert(
            (
                abi.encodeWithSelector(
                    EarlyAdopters.EarlyAdopters__DepositNotValid.selector,
                    beneficiary,
                    EARLYADOPTERS_MAX_AMOUNT_TO_DEPOSIT,
                    EARLYADOPTERS_MIN_AMOUNT_TO_DEPOSIT,
                    block.timestamp
                )
            )
        );
        engine.deposit(beneficiary, amount);
        vm.stopPrank();
    }

    function testEarlyAdoptersDepositRevertWithInvalidTime() external {
        address beneficiary = address(1);
        uint256 amount = 30e18;
        uint256 earlyAdoptersDuration = engine.getEarlyAdoptersDuration();
        vm.warp(block.timestamp + earlyAdoptersDuration + 1);
        vm.roll(block.number + 1);
        vm.startPrank(address(1));
        ERC20(weth).approve(address(engine), amount);
        vm.expectRevert(
            (
                abi.encodeWithSelector(
                    EarlyAdopters.EarlyAdopters__DepositNotValid.selector,
                    beneficiary,
                    EARLYADOPTERS_MAX_AMOUNT_TO_DEPOSIT,
                    EARLYADOPTERS_MIN_AMOUNT_TO_DEPOSIT,
                    block.timestamp
                )
            )
        );
        engine.deposit(beneficiary, amount);
        vm.stopPrank();
    }

    function testEarlyAdoptersDepositRevertWithInvalidTotalAmountDeposited()
        external
    {
        address beneficiary = address(11);
        uint256 amount = 300e18;
        for (uint160 i = 1; i < 11; i++) {
            vm.startPrank(address(i));
            ERC20(weth).approve(address(engine), amount);
            engine.deposit(address(i), amount);
            vm.stopPrank();
        }
        vm.startPrank(beneficiary);
        ERC20(weth).approve(address(engine), amount);
        vm.expectRevert(
            (
                abi.encodeWithSelector(
                    EarlyAdopters.EarlyAdopters__DepositNotValid.selector,
                    beneficiary,
                    EARLYADOPTERS_MAX_AMOUNT_TO_DEPOSIT,
                    EARLYADOPTERS_MIN_AMOUNT_TO_DEPOSIT,
                    block.timestamp
                )
            )
        );
        engine.deposit(beneficiary, amount);
        vm.stopPrank();
    }

    function testEarlyAdoptersDepositWorksWithValidParams() external {
        address beneficiary = address(1);
        uint256 amount = 30e18;
        vm.startPrank(beneficiary);
        ERC20(weth).approve(address(engine), amount);
        engine.deposit(beneficiary, amount);
        vm.stopPrank();
    }

    modifier earlyAdoptersDeposited() {
        uint256 amount = 300e18;
        for (uint160 i = 1; i < 11; i++) {
            vm.startPrank(address(i));
            ERC20(weth).approve(address(engine), amount);
            engine.deposit(address(i), amount);
            vm.stopPrank();
        }
        _;
    }

    function testEarlyAdoptersDepositsToEngine()
        external
        earlyAdoptersDeposited
    {
        uint256 engineWethBalance = ERC20(weth).balanceOf(address(engine));
        assertEq(engineWethBalance, 3000e18);
    }

    function testEarlyAdoptersDepositedEmitsCollateralDeposited() external {
        uint256 amount = 30e18;
        vm.startPrank(address(1));
        ERC20(weth).approve(address(engine), amount);
        vm.expectEmit(true, true, true, false, address(engine));
        emit CollateralDeposited(address(1), weth, amount);
        engine.deposit(address(1), amount);
        vm.stopPrank();
    }

    // --------------------------------
    //  EARLY ADOPTERS CLAIM REWARD TEST
    //   --------------------------------

    function testAmountToClaim() external earlyAdoptersDeposited {
        address user = address(1);
        uint256 amountToClaim = engine.amountToClaim(user);
        assertEq(amountToClaim, 300e18);
    }

    function testClaimRewardRevertsWhenTimeNotReached()
        external
        earlyAdoptersDeposited
    {
        uint256 amountToClaim = engine.amountToClaim(address(1));
        bool rewardClaimed = engine.getUserClaimReward(address(1));
        uint256 balanceOfUser = ERC20(viper).balanceOf(address(1));
        uint256 amountTokenToTransfer = engine.tokenToTransfer(amountToClaim);
        bool validAmountToClaim = amountTokenToTransfer + balanceOfUser <=
            EARLYADOPTERS_MAX_AMOUNT_TO_DEPOSIT;
        vm.startPrank(address(1));
        vm.expectRevert(
            (
                abi.encodeWithSelector(
                    EarlyAdopters.EarlyAdopters__CannotValidateClaims.selector,
                    block.timestamp,
                    amountToClaim,
                    rewardClaimed,
                    validAmountToClaim
                )
            )
        );
        engine.claimReward();
        vm.stopPrank();
    }

    function testClaimRewardWorksWhenTimeReached()
        external
        earlyAdoptersDeposited
    {
        uint256 crowdSaleStartAt = engine.getCrowdSaleStartAt();
        uint256 crowdSaleduration = engine.getCrowdSaleduration();
        uint256 userViperAmountToClaim = engine.amountToClaim(address(1));
        vm.warp(block.timestamp + crowdSaleStartAt + crowdSaleduration + 1);
        vm.roll(block.number + 1);
        vm.startPrank(address(1));
        engine.claimReward();
        vm.stopPrank();
        uint256 userViperBalance = ERC20(viper).balanceOf(address(1));
        assertEq(userViperBalance, userViperAmountToClaim);
    }

    function testUserCannotClaimRewardIfNotDeposited() external {
        address beneficiary = address(1);
        uint256 amount = engine.getUserDepositBalance(beneficiary);
        bool rewardClaimed = engine.getUserClaimReward(beneficiary);
        uint256 crowdSaleStartAt = engine.getCrowdSaleStartAt();
        uint256 crowdSaleduration = engine.getCrowdSaleduration();
        uint256 amountToClaim = engine.amountToClaim(address(1));
        uint256 balanceOfUser = ERC20(viper).balanceOf(address(1));
        uint256 amountTokenToTransfer = engine.tokenToTransfer(amountToClaim);
        bool validAmountToClaim = amountTokenToTransfer + balanceOfUser <=
            EARLYADOPTERS_MAX_AMOUNT_TO_DEPOSIT;
        vm.warp(crowdSaleStartAt + crowdSaleduration + 1);
        vm.roll(block.number + 1);
        vm.startPrank(beneficiary);
        vm.expectRevert(
            abi.encodeWithSelector(
                EarlyAdopters.EarlyAdopters__CannotValidateClaims.selector,
                block.timestamp,
                amount,
                rewardClaimed,
                validAmountToClaim
            )
        );
        engine.claimReward();
        vm.stopPrank();
    }

    modifier userClaimedReward() { 
        uint256 crowdSaleStartAt = engine.getCrowdSaleStartAt();
        uint256 crowdSaleduration = engine.getCrowdSaleduration();
        vm.warp(block.timestamp + crowdSaleStartAt + crowdSaleduration + 1);
        vm.roll(block.number + 1);
       for (uint160 i = 1; i < 11; i++) {
        vm.startPrank(address(i));
        engine.claimReward();
        viper.delegate(address(i));
        vm.stopPrank();
       
       }
        _;
    }

    function testUserCannotReclaimRewardAfterInitialClaim()
        external
        earlyAdoptersDeposited
        userClaimedReward
    {
        address beneficiary = address(1);
        uint256 amount = engine.getUserDepositBalance(beneficiary);
        bool claimedReward = engine.getUserClaimReward(beneficiary);
        uint256 amountToClaim = engine.amountToClaim(beneficiary);
        uint256 balanceOfUser = ERC20(viper).balanceOf(beneficiary);
        uint256 amountTokenToTransfer = engine.tokenToTransfer(amountToClaim);
        bool validAmountToClaim = amountTokenToTransfer + balanceOfUser <=
            EARLYADOPTERS_MAX_AMOUNT_TO_DEPOSIT;
        vm.startPrank(beneficiary);
        vm.expectRevert(
            abi.encodeWithSelector(
                EarlyAdopters.EarlyAdopters__CannotValidateClaims.selector,
                block.timestamp,
                amount,
                claimedReward,
                validAmountToClaim
            )
        );
        engine.claimReward();
        vm.stopPrank();
    }

    function testUserReceiveTokenViperAfterClaimingReward()
        external
        earlyAdoptersDeposited
    {
        uint256 crowdSaleStartAt = engine.getCrowdSaleStartAt();
        uint256 crowdSaleduration = engine.getCrowdSaleduration();
        uint256 userPreviousBalance = ERC20(viper).balanceOf(address(1));
        vm.warp(block.timestamp + crowdSaleStartAt + crowdSaleduration + 1);
        vm.roll(block.number + 1);
        vm.startPrank(address(1));
        engine.claimReward();
        vm.stopPrank();
        uint256 userPresentBalance = ERC20(viper).balanceOf(address(1));
        assert(userPresentBalance > userPreviousBalance);
    }

    function testEarlyAdoptersClaimRewardEmitRewardClaimed()
        external
        earlyAdoptersDeposited
    {
        uint256 amount = engine.getUserDepositBalance(address(1));
        uint256 tokenToTransfer = engine.tokenToTransfer(amount);
        uint256 crowdSaleStartAt = engine.getCrowdSaleStartAt();
        uint256 crowdSaleduration = engine.getCrowdSaleduration();
        vm.warp(block.timestamp + crowdSaleStartAt + crowdSaleduration + 1);
        vm.roll(block.number + 1);
        vm.startPrank(address(1));
        vm.expectEmit(true, true, false, false, address(engine));
        emit RewardClaimed(address(1), tokenToTransfer);
        engine.claimReward();
        vm.stopPrank();
    }

    function testTokenToTransferFromEvent() external earlyAdoptersDeposited {
        uint256 amount = engine.getUserDepositBalance(address(1));
        uint256 tokenToTransfer = engine.tokenToTransfer(amount);
        uint256 crowdSaleStartAt = engine.getCrowdSaleStartAt();
        uint256 crowdSaleduration = engine.getCrowdSaleduration();
        vm.warp(block.timestamp + crowdSaleStartAt + crowdSaleduration + 1);
        vm.roll(block.number + 1);
        vm.startPrank(address(1));
        vm.recordLogs();
        engine.claimReward();
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 tokenAmount = entries[1].topics[2];
        assertEq(amount, uint256(tokenAmount));
    }

    function testEarlyAdoptersClaimRewardRevertWithInvalidClaimTime()
        external
        earlyAdoptersDeposited
    {
        uint256 crowdSaleStartAt = engine.getCrowdSaleStartAt();
        uint256 crowdSaleduration = engine.getCrowdSaleduration();
        vm.warp(
            block.timestamp + crowdSaleStartAt + crowdSaleduration + 10 days + 1
        );
        vm.roll(block.number + 1);
        uint256 amountToClaim = engine.amountToClaim(address(1));
        bool rewardClaimed = engine.getUserClaimReward(address(1));
        uint256 balanceOfUser = ERC20(viper).balanceOf(address(1));
        uint256 amountTokenToTransfer = engine.tokenToTransfer(amountToClaim);
        bool validAmountToClaim = amountTokenToTransfer + balanceOfUser <=
            EARLYADOPTERS_MAX_AMOUNT_TO_DEPOSIT;
        vm.startPrank(address(1));
        vm.expectRevert(
            (
                abi.encodeWithSelector(
                    EarlyAdopters.EarlyAdopters__CannotValidateClaims.selector,
                    block.timestamp,
                    amountToClaim,
                    rewardClaimed,
                    validAmountToClaim
                )
            )
        );
        engine.claimReward();
        vm.stopPrank();
    }

    // -------------------
    //  CROWDSALE TEST
    //  --------------------

    function testGetTokenAmount() external earlyAdoptersDeposited {
        uint256 _amount = 1e18;
        uint256 actualTokenAmount = engine.getTokenAmount(_amount);
        uint256 expectedTokenAmount = 3333333333333333333;
        assertEq(actualTokenAmount, expectedTokenAmount);
    }

    function testCrowdSaleCannotBuyTokenWithInvalidAddress()
        external
        earlyAdoptersDeposited
    {
        address beneficiary = address(0);
        uint256 amount = 1e18;
        uint256 tokenAmount = engine.getTokenAmount(amount);
        uint256 initialToken = engine.amountToClaim(beneficiary);
        uint256 updatedToken = initialToken + tokenAmount;
        uint256 crowdSaleStartAt = engine.getCrowdSaleStartAt();
        vm.warp(block.timestamp + crowdSaleStartAt + 1);
        vm.roll(block.number + 1);
        vm.startPrank(address(1));
        ERC20(weth).approve(address(engine), amount);
        vm.expectRevert(
            abi.encodeWithSelector(
                Crowdsale.Crowdsale__PurchaseNotValid.selector,
                beneficiary,
                amount,
                INVESTOR_MAX_TOKEN_CAP,
                updatedToken
            )
        );
        engine.buyTokens(beneficiary, amount);
        vm.stopPrank();
    }

    function testCrowdSaleCannotBuyTokenWithInvalidMinAmount()
        external
        earlyAdoptersDeposited
    {
        address beneficiary = address(13);
        uint256 amount = 2e16;
        uint256 tokenAmount = engine.getTokenAmount(amount);
        uint256 initialToken = engine.amountToClaim(beneficiary);
        uint256 updatedToken = initialToken + tokenAmount;
        uint256 crowdSaleStartAt = engine.getCrowdSaleStartAt();
        vm.warp(block.timestamp + crowdSaleStartAt + 1);
        vm.roll(block.number + 1);
        vm.startPrank(address(1));
        ERC20(weth).approve(address(engine), amount);
        vm.expectRevert(
            abi.encodeWithSelector(
                Crowdsale.Crowdsale__PurchaseNotValid.selector,
                beneficiary,
                amount,
                INVESTOR_MAX_TOKEN_CAP,
                updatedToken
            )
        );
        engine.buyTokens(beneficiary, amount);
        vm.stopPrank();
    }

    function testCrowdSaleCannotBuyTokenWithInvalidMaxAmount()
        external
        earlyAdoptersDeposited
    {
        address beneficiary = address(13);
        uint256 amount = 91e18;
        uint256 tokenAmount = engine.getTokenAmount(amount);
        uint256 initialToken = engine.amountToClaim(beneficiary);
        uint256 updatedToken = initialToken + tokenAmount;
        uint256 crowdSaleStartAt = engine.getCrowdSaleStartAt();
        vm.warp(block.timestamp + crowdSaleStartAt + 1);
        vm.roll(block.number + 1);
        vm.startPrank(address(1));
        ERC20(weth).approve(address(engine), amount);
        vm.expectRevert(
            abi.encodeWithSelector(
                Crowdsale.Crowdsale__PurchaseNotValid.selector,
                beneficiary,
                amount,
                INVESTOR_MAX_TOKEN_CAP,
                updatedToken
            )
        );
        engine.buyTokens(beneficiary, amount);
        vm.stopPrank();
    }

    function testCrowdSaleCannotBuyTokenInvalidTime()
        external
        earlyAdoptersDeposited
    {
        address beneficiary = address(13);
        uint256 amount = 90e18;
        uint256 tokenAmount = engine.getTokenAmount(amount);
        uint256 initialToken = engine.amountToClaim(beneficiary);
        uint256 updatedToken = initialToken + tokenAmount;
        uint256 crowdSaleStartAt = engine.getCrowdSaleStartAt();
        vm.startPrank(address(1));
        ERC20(weth).approve(address(engine), amount);
        vm.expectRevert(
            abi.encodeWithSelector(
                Crowdsale.Crowdsale__PurchaseNotValid.selector,
                beneficiary,
                amount,
                INVESTOR_MAX_TOKEN_CAP,
                updatedToken
            )
        );
        engine.buyTokens(beneficiary, amount);
        vm.stopPrank();
    }

    function testCrowdSaleCannotBuyTokenWhenTimePasses()
        external
        earlyAdoptersDeposited
    {
        address beneficiary = address(13);
        uint256 amount = 90e18;
        uint256 tokenAmount = engine.getTokenAmount(amount);
        uint256 initialToken = engine.amountToClaim(beneficiary);
        uint256 updatedToken = initialToken + tokenAmount;
        uint256 crowdSaleEndTime = engine.getEndTime();
        vm.warp(block.timestamp + crowdSaleEndTime + 1);
        vm.roll(block.number + 1);
        vm.startPrank(address(1));
        ERC20(weth).approve(address(engine), amount);
        vm.expectRevert(
            abi.encodeWithSelector(
                Crowdsale.Crowdsale__PurchaseNotValid.selector,
                beneficiary,
                amount,
                INVESTOR_MAX_TOKEN_CAP,
                updatedToken
            )
        );
        engine.buyTokens(beneficiary, amount);
        vm.stopPrank();
    }

    function testCrowdSaleBuyTokenWorks() external earlyAdoptersDeposited {
        address beneficiary = address(13);
        uint256 amount = 90e18;
        uint256 tokenAmount = engine.getTokenAmount(amount);
        uint256 crowdSaleStartAt = engine.getCrowdSaleStartAt();
        uint256 previousEngineWethBalance = ERC20(weth).balanceOf(
            address(engine)
        );
        uint256 previousBeneficiaryViperBalance = ERC20(viper).balanceOf(
            beneficiary
        );
        vm.warp(block.timestamp + crowdSaleStartAt + 1);
        vm.roll(block.number + 1);
        vm.startPrank(address(1));
        ERC20(weth).approve(address(engine), amount);
        engine.buyTokens(beneficiary, amount);
        vm.stopPrank();
        uint256 presentEngineWethBalance = ERC20(weth).balanceOf(
            address(engine)
        );
        uint256 presentBeneficiaryViperBalance = ERC20(viper).balanceOf(
            beneficiary
        );
        assert(presentEngineWethBalance > previousEngineWethBalance);
        assert(
            presentBeneficiaryViperBalance > previousBeneficiaryViperBalance
        );
    }

    function testCrowdSaleCannotBuyTokenForAddressWithMaxAmountToClaim()
        external
        earlyAdoptersDeposited
    {
        address beneficiary = address(2);
        uint256 amount = 90e18;
        uint256 tokenAmount = engine.getTokenAmount(amount);
        uint256 initialToken = engine.amountToClaim(beneficiary);
        uint256 updatedToken = initialToken + tokenAmount;
        uint256 crowdSaleStartAt = engine.getCrowdSaleStartAt();
        vm.warp(block.timestamp + crowdSaleStartAt + 1);
        vm.roll(block.number + 1);
        vm.startPrank(address(1));
        ERC20(weth).approve(address(engine), amount);
        vm.expectRevert(
            abi.encodeWithSelector(
                Crowdsale.Crowdsale__PurchaseNotValid.selector,
                beneficiary,
                amount,
                INVESTOR_MAX_TOKEN_CAP,
                updatedToken
            )
        );
        engine.buyTokens(beneficiary, amount);
        vm.stopPrank();
    }

    function testEarlyAdoptersCanBuyTokenFromCrowdSaleIfNotMaxAmountToClaim()
        external
    {
        uint256 amountToDeposit = 150e18;
        vm.startPrank(address(1));
        ERC20(weth).approve(address(engine), amountToDeposit);
        engine.deposit(address(1), amountToDeposit);
        vm.stopPrank();

        uint256 amount = 2.25e18;
        uint256 tokenAmount = engine.getTokenAmount(amount);
        uint256 crowdSaleStartAt = engine.getCrowdSaleStartAt();
        vm.warp(block.timestamp + crowdSaleStartAt + 1);
        vm.roll(block.number + 1);
        vm.startPrank(address(1));
        ERC20(weth).approve(address(engine), amount);
        engine.buyTokens(address(1), amount);
        vm.stopPrank();
    }

    // ---------------------------
    //   ENGINE TEST
    //   ---------------------------

    function testMintStateStartAtClose() external {
        uint256 mintState = engine.getMintState();
        assertEq(mintState, 0);
    }

    function testMintStateAndViperBalanceUpdatesWhenEarlyAdoptersClaimDurationEnds()
        external
    {
        uint256 crowdSaleStartAt = engine.getCrowdSaleStartAt();
        uint256 crowdSaleDuration = engine.getCrowdSaleduration();

        vm.warp(
            block.timestamp + crowdSaleStartAt + crowdSaleDuration + 10 days
        );
        vm.roll(block.number + 1);
        engine.performUpkeep("");
        uint256 engineViperBalance = ERC20(viper).balanceOf(address(engine));
        uint256 mintState = engine.getMintState();
        assertEq(engineViperBalance, 0);
        assertEq(mintState, 1);
    }

    function testMintRevertWhenNotOpen() external earlyAdoptersDeposited {
        vm.startPrank(address(1));
        vm.expectRevert(Engine.Engine__MintNotOpen.selector);
        engine.mint(10e18, 0);
        vm.stopPrank();
    }

    modifier mintStateChanged() {
        uint256 crowdSaleStartAt = engine.getCrowdSaleStartAt();
        uint256 crowdSaleDuration = engine.getCrowdSaleduration();

        vm.warp(
            block.timestamp + crowdSaleStartAt + crowdSaleDuration + 10 days
        );
        vm.roll(block.number + 1);
        engine.performUpkeep("");
        _;
    }

    function testMintWorksWhenOpen()
        external
        earlyAdoptersDeposited
        userClaimedReward
        mintStateChanged
    {
        vm.startPrank(address(1));
        engine.mint(10e18, 0);
        vm.stopPrank();
    }

    function testMintRevertWithZero()
        external
        earlyAdoptersDeposited
        userClaimedReward
        mintStateChanged
    {
        vm.startPrank(address(1));
        vm.expectRevert(Engine.Engine__NeedsMoreThanZero.selector);
        engine.mint(0, 0);
        vm.stopPrank();
    }

    function testMintRevertWithBadHealthFactor() external mintStateChanged {
        uint256 amount = 10e18;
        vm.startPrank(address(1));
        vm.expectRevert(
            abi.encodeWithSelector(
                Engine.Engine__BreaksHealthFactor.selector,
                amount
            )
        );
        engine.mint(amount, 0);
        vm.stopPrank();
    }

    function testMintRevertWithInvalidDebtCeiling()
        external
        earlyAdoptersDeposited
        userClaimedReward
        mintStateChanged
    {
        vm.startPrank(WALLET_ADDRESS);
        WETH(weth).mint(address(1), 150000e18);

        vm.stopPrank();
        uint256 debtCeiling = engine.getDebtCeiling();
        vm.startPrank(address(1));
        ERC20(weth).approve(address(engine), 150000e18);
        engine.depositCollateral(address(1), 150000e18, 0);
        vm.expectRevert(
            abi.encodeWithSelector(
                Engine.Engine__CannotValidateMint.selector,
                block.timestamp,
                debtCeiling
            )
        );
        engine.mint(10001e18, 0);
        vm.stopPrank();
    }

    function testMintWorks()
        external
        earlyAdoptersDeposited
        userClaimedReward
        mintStateChanged
    {
        uint256 previousUserAmountVenomMinted = ERC20(venom).balanceOf(
            address(1)
        );
        vm.startPrank(address(1));
        engine.mint(10e18, 0);
        vm.stopPrank();
        uint256 presentUserAmountVenomMinted = ERC20(venom).balanceOf(
            address(1)
        );
        address user = engine.getMinted(0);
        bool minted = engine.getUserMinted(address(1));
        uint256 userBlockMinted = engine.getUserBlockNumber(address(1));
        assertEq(user, address(1));
        assertEq(true, minted);
        assert(presentUserAmountVenomMinted > previousUserAmountVenomMinted);
        console.log(userBlockMinted);
    }

    function testDepositCollateralRevertWithZero()
        external
        earlyAdoptersDeposited
        userClaimedReward
        mintStateChanged
    {
        vm.startPrank(WALLET_ADDRESS);
        WETH(weth).mint(address(13), 150000e18);
        vm.stopPrank();
        vm.startPrank(address(13));
        ERC20(weth).approve(address(engine), 150000e18);
        vm.expectRevert(Engine.Engine__NeedsMoreThanZero.selector);
        engine.depositCollateral(address(13), 0, 0);
        vm.stopPrank();
    }

    function testDepositRevertWithInvalidIndex()
        external
        earlyAdoptersDeposited
        userClaimedReward
        mintStateChanged
    {
        vm.startPrank(WALLET_ADDRESS);
        WETH(weth).mint(address(13), 150000e18);
        vm.stopPrank();
        vm.startPrank(address(13));
        ERC20(weth).approve(address(engine), 150000e18);
        vm.expectRevert(Engine.Engine__collateralDoesNotExist.selector);
        engine.depositCollateral(address(13), 150000e18, 1);
        vm.stopPrank();
    }

    function testDepositWorks()
        external
        earlyAdoptersDeposited
        userClaimedReward
        mintStateChanged
    {
        vm.startPrank(WALLET_ADDRESS);
        WETH(weth).mint(address(13), 150000e18);
        vm.stopPrank();
        uint256 previousEngineWethBalance = ERC20(weth).balanceOf(
            address(engine)
        );
        vm.startPrank(address(13));
        ERC20(weth).approve(address(engine), 150000e18);
        engine.depositCollateral(address(13), 150000e18, 0);
        vm.stopPrank();
        uint256 presentEngineWethBalance = ERC20(weth).balanceOf(
            address(engine)
        );
        assert(presentEngineWethBalance > previousEngineWethBalance);
    }

    modifier depositedCollateral() {
        vm.startPrank(WALLET_ADDRESS);
        WETH(weth).mint(address(13), 150000e18);
        vm.stopPrank();
        vm.startPrank(address(13));
        ERC20(weth).approve(address(engine), 150000e18);
        engine.depositCollateral(address(13), 150000e18, 0);
        vm.stopPrank();
        _;
    }

    modifier mintedVenom() {
        vm.startPrank(address(1));
        engine.mint(100e18, 0);
        vm.stopPrank();
        _;
    }

    function testDepositAndMintVenom()
        external
        earlyAdoptersDeposited
        userClaimedReward
        mintStateChanged
    {
        vm.startPrank(WALLET_ADDRESS);
        WETH(weth).mint(address(13), 150000e18);
        vm.stopPrank();
        vm.startPrank(address(13));
        ERC20(weth).approve(address(engine), 150000e18);
        engine.depositCollateralAndMintVenom(address(13), 150000e18, 0, 100e18);
        vm.stopPrank();
    }

    function testRedeemCollateralRevertWithInvalidIndex()
        external
        earlyAdoptersDeposited
        userClaimedReward
        mintStateChanged
    {
        vm.startPrank(address(1));
        vm.expectRevert(Engine.Engine__collateralDoesNotExist.selector);
        engine.redeemCollateral(1, 300e18);
        vm.stopPrank();
    }

    function testRedeemCollateralRevertWithZero()
        external
        earlyAdoptersDeposited
        userClaimedReward
        mintStateChanged
    {
        vm.startPrank(address(1));
        vm.expectRevert(Engine.Engine__NeedsMoreThanZero.selector);
        engine.redeemCollateral(0, 0);
        vm.stopPrank();
    }

    function testRedeemCollateralRevertWhenNotDeposited()
        external
        earlyAdoptersDeposited
        userClaimedReward
        mintStateChanged
    {
        vm.startPrank(WALLET_ADDRESS);
        WETH(weth).mint(address(13), 150000e18);
        vm.stopPrank();
        uint256 userCollateralBalance = engine.getUserCollateralBalance(
            address(13),
            0
        );
        vm.startPrank(address(13));
        vm.expectRevert(
            abi.encodeWithSelector(
                Engine.Engine__CannotRedeemCollateral.selector,
                userCollateralBalance
            )
        );
        engine.redeemCollateral(0, 300e18);
        vm.stopPrank();
    }

    function testRedeemCollateralRevertWithInvalidAmountToRedeem()
        external
        earlyAdoptersDeposited
        userClaimedReward
        mintStateChanged
    {
        uint256 userCollateralBalance = engine.getUserCollateralBalance(
            address(1),
            0
        );
        vm.startPrank(address(1));
        vm.expectRevert(
            abi.encodeWithSelector(
                Engine.Engine__CannotRedeemCollateral.selector,
                userCollateralBalance
            )
        );
        engine.redeemCollateral(0, 301e18);
        vm.stopPrank();
    }

    function testRedeemCollateralWorks()
        external
        earlyAdoptersDeposited
        userClaimedReward
        mintStateChanged
    {
        uint256 previousUserWethBalance = ERC20(weth).balanceOf(address(1));
        vm.startPrank(address(1));
        engine.redeemCollateral(0, 300e18);
        vm.stopPrank();
        uint256 presentUserWethBalance = ERC20(weth).balanceOf(address(1));
        assert(presentUserWethBalance > previousUserWethBalance);
    }

    function testRedeemCollateralForVenomWorksWhenUserBurnsTotalMinted()
        external
        earlyAdoptersDeposited
        userClaimedReward
        mintStateChanged
        mintedVenom
    {
        uint256 userPreviousWethBalance = ERC20(weth).balanceOf(address(1));
        uint256 userPreviousVenomBalance = ERC20(venom).balanceOf(address(1));
        uint256 enginePreviousVenomBalance = ERC20(venom).balanceOf(
            address(engine)
        );
        vm.startPrank(address(1));
        ERC20(venom).approve(address(engine), 100e18);
        engine.redeemCollateralForVenom(100e18, 0);
        vm.stopPrank();
        uint256 userPresentVenomBalance = ERC20(venom).balanceOf(address(1));
        uint256 enginePresentVenomBalance = ERC20(venom).balanceOf(
            address(engine)
        );
        uint256 userMinted = engine.getAmountMinted();
        uint256 userPresentWethBalance = ERC20(weth).balanceOf(address(1));
        console.log(userMinted);
        assertEq(userMinted, 0);
        assert(userPreviousVenomBalance > userPresentVenomBalance);
        assertEq(enginePreviousVenomBalance, enginePresentVenomBalance);
        assert(userPresentWethBalance > userPreviousWethBalance);
    }

    function testRedeemCollateralForVenomWorksWhenUserDoNotBurnTotalMinted()
        external
        earlyAdoptersDeposited
        userClaimedReward
        mintStateChanged
        mintedVenom
    {
        uint256 userPreviousWethBalance = ERC20(weth).balanceOf(address(1));
        uint256 userPreviousVenomBalance = ERC20(venom).balanceOf(address(1));
        uint256 enginePreviousVenomBalance = ERC20(venom).balanceOf(
            address(engine)
        );
        vm.startPrank(address(1));
        ERC20(venom).approve(address(engine), 50e18);
        engine.redeemCollateralForVenom(50e18, 0);
        vm.stopPrank();
        uint256 userPresentVenomBalance = ERC20(venom).balanceOf(address(1));
        uint256 enginePresentVenomBalance = ERC20(venom).balanceOf(
            address(engine)
        );
        uint256 userMinted = engine.getAmountMinted();
        uint256 userPresentWethBalance = ERC20(weth).balanceOf(address(1));
        console.log(userMinted);
        assertEq(userMinted, 1);
        assert(userPreviousVenomBalance > userPresentVenomBalance);
        assertEq(enginePreviousVenomBalance, enginePresentVenomBalance);
        assert(userPresentWethBalance > userPreviousWethBalance);
    }

    function testBurnRevertWithInvalidBurnAmount()
        external
        earlyAdoptersDeposited
        userClaimedReward
        mintStateChanged
        mintedVenom
    {
        vm.startPrank(address(1));
        ERC20(venom).approve(address(engine), 101e18);
        vm.expectRevert();
        engine.burnVenom(101e18, 0);
        vm.stopPrank();
    }

    function testBurnWorksWithValidAmount()
        external
        earlyAdoptersDeposited
        userClaimedReward
        mintStateChanged
        mintedVenom
    {
        uint256 userPreviousVenomBalance = ERC20(venom).balanceOf(address(1));
        vm.startPrank(address(1));
        ERC20(venom).approve(address(engine), 90e18);
        engine.burnVenom(90e18, 0);
        vm.stopPrank();
        uint256 userPresentVenomBalance = ERC20(venom).balanceOf(address(1));
        uint256 userMinted = engine.getAmountMinted();
        bool mintStatus = engine.getUserMinted(address(1));
        assert(userPreviousVenomBalance > userPresentVenomBalance);
        assertEq(mintStatus, true);
        assertEq(userMinted, 1);
    }

    function testBurnWorksWhenUserBurnTotalAmount()
        external
        earlyAdoptersDeposited
        userClaimedReward
        mintStateChanged
        mintedVenom
    {
        uint256 userPreviousVenomBalance = ERC20(venom).balanceOf(address(1));
        vm.startPrank(address(1));
        ERC20(venom).approve(address(engine), 100e18);
        engine.burnVenom(100e18, 0);
        vm.stopPrank();
        uint256 userPresentVenomBalance = ERC20(venom).balanceOf(address(1));
        uint256 userMinted = engine.getAmountMinted();
        bool mintStatus = engine.getUserMinted(address(1));
        assert(userPreviousVenomBalance > userPresentVenomBalance);
        assertEq(mintStatus, false);
        assertEq(userMinted, 0);
    }

    function testCheckHealthFactorWorksIfNotDeposited()
        external
        earlyAdoptersDeposited
        userClaimedReward
        mintStateChanged
    {
        bool healthFactor = engine._checkHealthFactorIsGood(address(13), 1, 0);
        assert(healthFactor == false);
    }

    function testCheckHealthFactorWorksIfMintedUserChecksBelowThreshold()
        external
        earlyAdoptersDeposited
        userClaimedReward
        mintStateChanged
        mintedVenom
    {
        bool healthFactor = engine._checkHealthFactorIsGood(address(1), 1, 0);
        assert(healthFactor == true);
    }

    function testCheckHealthFactorWorksIfMintedUserChecksAboveThreshold()
        external
        earlyAdoptersDeposited
        userClaimedReward
        mintStateChanged
        mintedVenom
    {
        bool healthFactor = engine._checkHealthFactorIsGood(
            address(1),
            3000000e18,
            0
        );
        assert(healthFactor == false);
    }


    //////////////////////////
    /// ANCESTOR TEST ///////
    ////////////////////////

    function testCannotSetupcollateralWihoutAncestors() 
       external 
        earlyAdoptersDeposited
        userClaimedReward
        mintStateChanged
        mintedVenom
    {
        vm.expectRevert();
        engine.setUpCollateral(address(1), address(1), 150e18, 1 ether, 3e15);
    }

    function testAncestorCanSetUpCollateral() 
        external  
        earlyAdoptersDeposited
        userClaimedReward
        mintStateChanged
        mintedVenom
    {
       bytes memory encodedfunctionCall = abi.encodeWithSignature("setUpCollateral(address,address,uint256,uint256,uint256)", address(1), address(1), 150e18, 1 ether, 3e15);
       targets.push(address(engine));
       values.push(0);
       calldatas.push(encodedfunctionCall);
       string memory description = "setup collateral";

       uint256 proposalId = ancestor.propose(targets, values, calldatas, description);

       vm.warp(block.timestamp + VOTING_DELAY + 1);
       vm.roll(block.number + VOTING_DELAY + 1);

       string memory reason = " to update collateral";
       uint8 voteWay = 1;
       vm.startPrank(address(1));
       ancestor.castVoteWithReason(proposalId, voteWay, reason);
       vm.warp(block.timestamp + VOTING_PERIOD + 1);
       vm.roll(block.number + VOTING_PERIOD + 1);

       bytes32 descriptionHash = keccak256(abi.encodePacked(description));
       ancestor.queue(targets, values, calldatas, descriptionHash);

       vm.warp(block.timestamp + MIN_DELAY + 1);
       vm.roll(block.number + MIN_DELAY + 1);
       ancestor.execute(targets, values, calldatas, descriptionHash);
       (
            address collateralAddress,
           ,
           ,
           ,
           
        ) = engine.getCollateralInfo(1);
        assertEq(collateralAddress, address(1));

    }
    
}
