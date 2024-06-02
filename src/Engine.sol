// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import {Venom} from "./Venom.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Auction} from "./Auction.sol";
import {DeployAuction} from "../script/DeployAuction.s.sol";
import {Viper} from "./Viper.sol";
import {EarlyAdopters} from "./EarlyAdopter.sol";
import {Crowdsale} from "./Crowdsale.sol";
import {OracleLib} from "./Libraries/OracleLib.sol";

/**
 * @title Engine
 * @author Olukayode paul
 * @notice This engine Contract is in charge of the whole stable coin system. These contract is owned by the timelock which is in control of the onlyOwner function
 * (risk parameters set by the governance)
 */

contract Engine is Ownable, EarlyAdopters, Crowdsale {
    // ERRORS
    error Engine__collateralDoesNotExist();
    error Engine__TransferFailed();
    error Engine__NeedsMoreThanZero();
    error Engine__BreaksHealthFactor(uint256 _amount);
    error Engine__CollateralAlreadyExist(address _collateralAddress);
    error Engine__CannotRedeemCollateral(uint256 _amount);
    error Engine__CannotPerformUpkeep(uint256 _time, uint256 _arrayLength);
    error Engine__MintNotOpen();
    error Engine__CannotValidateMint(uint256 _time, uint256 _debtCeiling);
    error Engine__CannotBurnVenom();
    error Engine__TransferViperFailed();

    // Type

    using OracleLib for AggregatorV3Interface;

    // EVENTS
    event CollateralDeposited(
        address indexed user,
        address indexed collateral,
        uint256 indexed amount
    );
    event Minted(address indexed user, uint256 indexed amount);
    event CollateralRedeemed(
        address indexed user,
        address indexed collateral,
        uint256 indexed amountRedeemed
    );
    event CollateralRedeemedForVenom(
        address indexed user,
        address indexed collateral,
        uint256 indexed amountRedeemed
    );
    event VenomBurnt(uint256 indexed _amount);
    event UserLiquidated(
        address indexed liquidatedUser,
        address indexed collateralToLiquidate,
        uint256 indexed amountliquidated
    );
    event CollateralSetUp(
        address _collateralAddress,
        address _collateralPriceFeed,
        uint256 _liquidationThreshold,
        uint256 _penaltyFee,
        uint256 _stabilityFee
    );
    event CollateralUpdated(
        address _collateralAddress,
        address _collateralPriceFeed,
        uint256 _liquidationThreshold,
        uint256 _penaltyFee,
        uint256 _stabilityFee
    );
    event CollateralRemoved(Collateral _collateralRemoved);
    event LiquidationThresholdUpdated(uint256 _updatedThreshold);
    event StabilityFeeUpdated(uint256 _updatedStabilityFee);
    event BlockNumberUpdated(uint256 _blocknumber);
    event LiquidationPenaltyUpdated(uint256 _liquidationPenalty);
    event DebtCeilingUpdated(uint256 _debtCeiling);
    event liquidatedUserDebtPosition();

    // ENUM
    enum Status {
        CLOSED,
        OPEN
    }

    Status public mintState;

    // STATES

    Collateral[] private s_collaterals; // The list of collaterals in which would be accessed by the index
    uint256 private s_lastTimeStamp; // The last time which perform upkeep was called
    address[] private s_minted; // The list of all addresses that minted venom from the system
    address[] public s_auctionAddresses;
    uint256 private s_blockNumber = 10;
    uint256 private s_debtCeiling = 10000e18;

    // CONSTANTS

    uint256 private constant AGGRREGATOR_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant PERCENTAGE = 100;
    uint256 private constant INTERVAL = 60; //The interval at which the oracle calls perform upkeep
    uint256 private constant AUCTION_DURATION = 3 days;
    uint256 private constant AUCTION_DISCOUNT_RATE = 1e14;
    uint256 private constant BUFFER = 5e16;
    uint256 private constant earlyAdoptersDuration = 30 days;
    uint256 private constant earlyAdoptersTotalTokenDeposited = 3000e18;
    uint256 private constant crowdSaleStartAt = 30 days;
    uint256 private constant crowdSaleduration = 60 days;
    uint256 private earlyAdoptersClaimTime =
        block.timestamp + crowdSaleStartAt + crowdSaleduration;

    // IMMUTABLES
    Venom private immutable i_venom;
    Viper private immutable i_viper;
    uint256 private immutable i_startAt;

    // STRUCTS
    /// @notice The collateral struct is used to set up the structure of all collaterals in the system
    struct Collateral {
        address collateralAddress;
        address collateralPriceFeed;
        uint256 liquidationThreshold;
        uint256 penaltyFee;
        uint256 stabilityFee;
    }

    // MAPPINGS

    mapping(address user => mapping(address collateral => uint256 amount))
        public userToCollateralDeposited; // The mapping that update the user to the amount of collateral deposited
    mapping(address user => bool minted) private userToMinted; // This maps to check if the user has a current debt position
    mapping(address user => mapping(address collateral => uint256 amountMinted))
        public userToAmountMinted; // The mapping which update the user to the amount of debt position
    mapping(address user => uint256 blockMinted) private userToBlockMinted;

    constructor(
        address _stablecoin,
        address _governanceToken,
        address _collateralAddress,
        address _collateralPriceFeed,
        uint256 _liquidationThreshold,
        uint256 _penaltyFee,
        uint256 _stabilityFee,
        uint256 _startAt
    )
        Ownable(msg.sender)
        EarlyAdopters(
            earlyAdoptersDuration,
            earlyAdoptersTotalTokenDeposited,
            _governanceToken,
            earlyAdoptersClaimTime
        )
        Crowdsale(
            _governanceToken,
            crowdSaleStartAt,
            crowdSaleduration,
            _collateralAddress
        )
    {
        i_venom = Venom(_stablecoin);
        i_viper = Viper(_governanceToken);
        _setUpInitialCollateral(
            _collateralAddress,
            _collateralPriceFeed,
            _liquidationThreshold,
            _penaltyFee,
            _stabilityFee
        );
        s_lastTimeStamp = block.timestamp;
        i_startAt = block.timestamp + _startAt + 10 days;
    }

    /////////////////////
    ///// MODIFIER  ////
    ///////////////////

    modifier validIndex(uint256 _index) {
        if (_index > s_collaterals.length - 1) {
            revert Engine__collateralDoesNotExist();
        }
        _;
    }

    modifier moreThanZero(uint256 _amount) {
        if (_amount <= 0) {
            revert Engine__NeedsMoreThanZero();
        }
        _;
    }
    modifier checkHealthFactor(
        address _user,
        uint256 _amount,
        uint256 _index
    ) {
        uint256 healthFactor = _calculateHealthFactor(_user, _amount, _index);
        uint256 healthFactorInPercentage = healthFactor * PERCENTAGE;
        if (
            healthFactorInPercentage <
            s_collaterals[_index].liquidationThreshold
        ) {
            revert Engine__BreaksHealthFactor(_amount);
        }
        _;
    }

    modifier mintingState() {
        if (mintState != Status.OPEN) {
            revert Engine__MintNotOpen();
        }
        _;
    }

    function _setUpInitialCollateral(
        address _collateralAddress,
        address _collateralPriceFeed,
        uint256 _liquidationThreshold,
        uint256 _penaltyFee,
        uint256 _stabilityFee
    ) internal {
        Collateral memory collateral = Collateral({
            collateralAddress: _collateralAddress,
            collateralPriceFeed: _collateralPriceFeed,
            liquidationThreshold: _liquidationThreshold,
            penaltyFee: _penaltyFee,
            stabilityFee: _stabilityFee
        });
        s_collaterals.push(collateral);
    }

    ////////////////////////////////////
    /// PUBLIC ONLY OWNER FUNCTIONS ///
    //////////////////////////////////

    /**
     * @notice This function only appends to the updated list
     * @param _collateralAddress The acceptable collateral address
     * @param _collateralPriceFeed The pricefeed to be used to get real time information about the collateral
     * @param _liquidationThreshold The figure to be set as liquidation threshold
     * @param _penaltyFee The figure to be set as penalty fee
     * @param _stabilityFee The figure to be set as stability fee
     */

    function setUpCollateral(
        address _collateralAddress,
        address _collateralPriceFeed,
        uint256 _liquidationThreshold,
        uint256 _penaltyFee,
        uint256 _stabilityFee
    ) public onlyOwner {
        Collateral[] memory array = s_collaterals;
        for (uint i; i < array.length; i++) {
            if (_collateralAddress == array[i].collateralAddress) {
                revert Engine__CollateralAlreadyExist(_collateralAddress);
            }
        }
        Collateral memory collateral = Collateral({
            collateralAddress: _collateralAddress,
            collateralPriceFeed: _collateralPriceFeed,
            liquidationThreshold: _liquidationThreshold,
            penaltyFee: _penaltyFee,
            stabilityFee: _stabilityFee
        });
        s_collaterals.push(collateral);
        emit CollateralSetUp(
            _collateralAddress,
            _collateralPriceFeed,
            _liquidationThreshold,
            _penaltyFee,
            _stabilityFee
        );
    }

    /**
     * @notice  This function updates parameters of the collateral in the list of the collaterals
     * @param _index The index of the collateral to be updated
     * @param _collateralAddress The new collateral address to be updated
     * @param _collateralPriceFeed This is the updated pricefeed to be used for the new collateral
     * @param _liquidationThreshold This is the figure to be updated as liquidation threshold
     * @param _penaltyFee This is the figure to be updated as penalty fee
     * @param _stabilityFee This is the figure to be updated as stability fee
     */

    function updateCollateral(
        uint256 _index,
        address _collateralAddress,
        address _collateralPriceFeed,
        uint256 _liquidationThreshold,
        uint256 _penaltyFee,
        uint256 _stabilityFee
    ) public onlyOwner validIndex(_index) {
        s_collaterals[_index].collateralAddress = _collateralAddress;
        s_collaterals[_index].collateralPriceFeed = _collateralPriceFeed;
        s_collaterals[_index].liquidationThreshold = _liquidationThreshold;
        s_collaterals[_index].penaltyFee = _penaltyFee;
        s_collaterals[_index].stabilityFee = _stabilityFee;
        emit CollateralUpdated(
            _collateralAddress,
            _collateralPriceFeed,
            _liquidationThreshold,
            _penaltyFee,
            _stabilityFee
        );
    }

    /**
     * @notice This function remove the specified index of the collateral from the list
     * @param _index The index of the collateral to be removed
     */
    function removeCollateral(
        uint256 _index
    ) public onlyOwner validIndex(_index) {
        s_collaterals[_index] = s_collaterals[s_collaterals.length - 1];
        s_collaterals.pop();
        emit CollateralRemoved(s_collaterals[_index]);
    }

    /**
     * @notice This function updates the liquidation threshold
     * @param _threshold The liquidation threshold to be updated
     */
    function updateLiquidationThreshold(
        uint256 _threshold,
        uint256 _index
    ) public onlyOwner {
        s_collaterals[_index].liquidationThreshold = _threshold;
        emit LiquidationThresholdUpdated(_threshold);
    }

    /**
     * @notice This function updates the stability fee
     * @param _stabilityFee The figure of the stability fee to be updated
     * @param _index This is the index of collateral of which stability fee is  to be updated
     */

    function updateStabilityFee(
        uint256 _stabilityFee,
        uint256 _index
    ) public onlyOwner {
        s_collaterals[_index].stabilityFee = _stabilityFee;
        emit StabilityFeeUpdated(_stabilityFee);
    }

    /**
     * @notice This function updates the block number
     * @param _blocknumber The figure of the block number to be updated
     */

    function updateBlockNumber(uint256 _blocknumber) public onlyOwner {
        s_blockNumber = _blocknumber;
        emit BlockNumberUpdated(_blocknumber);
    }

    /**
     * @notice This function updates the liquidation penalty
     * @param _liquidationPenalty The figure of the liquidation penalty to be updated
     * @param _index This is the index of the collateral of which liquidation threshold is to be updated
     */
    function updateLiquidationPenalty(
        uint256 _liquidationPenalty,
        uint256 _index
    ) public onlyOwner {
        s_collaterals[_index].penaltyFee = _liquidationPenalty;
        emit LiquidationPenaltyUpdated(_liquidationPenalty);
    }

    /**
     * @notice This function updates the debt ceiling
     * @param _debtCeiling The figure of the debt ceiling to be updated
     */
    function updateDebtCeiling(uint256 _debtCeiling) public onlyOwner {
        s_debtCeiling = _debtCeiling;
        emit DebtCeilingUpdated(_debtCeiling);
    }

    ///////////////////////
    /// PUBLIC FUNCTION ///
    //////////////////////

    /**
     * @notice This function  deposits collateral to the engine
     * @param _from  The address of the person to deposit collateral
     * @param _amount The unit of collateral to be deposited, amount must be more than zero
     * @param _index The index of the collateral to be deposited, index must be within the collateral list
     */
    function depositCollateral(
        address _from,
        uint256 _amount,
        uint256 _index
    ) public validIndex(_index) moreThanZero(_amount) {
        address collateralToDeposit = s_collaterals[_index].collateralAddress;
        userToCollateralDeposited[_from][collateralToDeposit] += _amount;
        bool success = IERC20(collateralToDeposit).transferFrom(
            _from,
            address(this),
            _amount
        );
        if (!success) {
            revert Engine__TransferFailed();
        }
        emit CollateralDeposited(_from, collateralToDeposit, _amount);
    }

    /**
     * @notice This function mint the venom stablecoin if the user has deposited and the amount to mint doesn't break health factor
     * @param _amount The amount of venom stablecoin the user is willing to mint
     * @param _index This is the index of collateral to be used in exchange of mint the venomn
     */

    function mint(
        uint256 _amount,
        uint256 _index
    )
        public
        moreThanZero(_amount)
        checkHealthFactor(msg.sender, _amount, _index)
        mintingState
    {
        _prevalidateMint(_index, _amount);
        if (!userToMinted[msg.sender]) {
            s_minted.push(msg.sender);
            userToMinted[msg.sender] = true;
            userToBlockMinted[msg.sender] = block.number;
        }
        userToAmountMinted[msg.sender][
            s_collaterals[_index].collateralAddress
        ] += _amount;
        bool success = i_venom.mint(msg.sender, _amount);
        if (!success) {
            revert Engine__TransferFailed();
        }

        emit Minted(msg.sender, _amount);
    }

    /**
     * @notice This function prevalidates the mint function
     */
    function _prevalidateMint(uint256 _index, uint256 _amount) internal view {
        uint256 initialMintAmount = userToAmountMinted[msg.sender][
            s_collaterals[_index].collateralAddress
        ];
        uint256 newAmountToMint = initialMintAmount + _amount;

        bool validMintTime = block.timestamp > i_startAt;
        bool validMaxAmountToMint = newAmountToMint <= s_debtCeiling;

        bool validMintParams = validMintTime && validMaxAmountToMint;
        if (!validMintParams) {
            revert Engine__CannotValidateMint(block.timestamp, s_debtCeiling);
        }
    }

    /**
     * @notice This function does the both depositing and minting collaterals. NOTE: there may be a way to reduce gas cost for the transaction
     * @param _from  The address of the person to deposit collateral
     * @param _amountToDeposit The unit of collateral to be deposited, amount must be more than zero
     * @param _index The index of the collateral to be deposited, index must be within the collateral list
     * @param _amountToMint The amount of venom stablecoin the user is willing to mint
     *
     */

    function depositCollateralAndMintVenom(
        address _from,
        uint256 _amountToDeposit,
        uint256 _index,
        uint256 _amountToMint
    ) external {
        depositCollateral(_from, _amountToDeposit, _index);
        mint(_amountToMint, _index);
    }

    /**
     * @notice This function redeems collateral if the user has a good health factor
     * @param _index This is the index in the array of collateral to redeem
     * @param _amountToRedeem This is the unit of the specified collateral to redeem from the system by the user
     */

    function redeemCollateral(
        uint256 _index,
        uint256 _amountToRedeem
    ) public validIndex(_index) moreThanZero(_amountToRedeem) {
        _prevalidateRedeemCollateral(_index, _amountToRedeem);
        userToCollateralDeposited[msg.sender][
            s_collaterals[_index].collateralAddress
        ] -= _amountToRedeem;

        if (userToMinted[msg.sender]) {
            checkRedeemCollateralBreaksHealthFactor(
                msg.sender,
                _amountToRedeem,
                _index
            );
        }

        bool success = IERC20(s_collaterals[_index].collateralAddress).transfer(
            msg.sender,
            _amountToRedeem
        );
        if (!success) {
            revert Engine__TransferFailed();
        }

        emit CollateralRedeemed(
            msg.sender,
            s_collaterals[_index].collateralAddress,
            _amountToRedeem
        );
    }

    function _prevalidateRedeemCollateral(
        uint256 _index,
        uint256 _amountToRedeem
    ) internal view {
        uint256 collateralBalance = userToCollateralDeposited[msg.sender][
            s_collaterals[_index].collateralAddress
        ];
        bool validDepositAmount = collateralBalance > 0;
        bool validAmountToRedeem = userToCollateralDeposited[msg.sender][
            s_collaterals[_index].collateralAddress
        ] >= _amountToRedeem;

        bool validateRedeemCollateral = validDepositAmount &&
            validAmountToRedeem;
        if (!validateRedeemCollateral) {
            revert Engine__CannotRedeemCollateral(collateralBalance);
        }
    }

    /**
     * @notice This function redeems collateral based on the amount of venom put in exchange
     * @param _amountOfVenomToBurn This is the amount of venom put in exchange for the collateral
     * @param _index  This is the index in the array of collateral to redeem
     */

    function redeemCollateralForVenom(
        uint256 _amountOfVenomToBurn,
        uint256 _index
    ) external validIndex(_index) moreThanZero(_amountOfVenomToBurn) {
        address pricefeed = s_collaterals[_index].collateralPriceFeed;
        uint256 collateralInUsd = getValueInUsd(PRECISION, pricefeed);
        uint256 collateralToTransfer = (_amountOfVenomToBurn * PRECISION) /
            collateralInUsd;

        _prevalidateRedeemCollateral(_index, _amountOfVenomToBurn);

        userToCollateralDeposited[msg.sender][
            s_collaterals[_index].collateralAddress
        ] -= collateralToTransfer;
       uint256 mintedBalance = userToAmountMinted[msg.sender][
            s_collaterals[_index].collateralAddress
        ] -= _amountOfVenomToBurn;
        if (
           mintedBalance == 0
        ) {
            address[] storage array = s_minted;
            for (uint256 i = 0; i < array.length; i++) {
                if (array[i] == msg.sender) {
                    array[i] = array[array.length - 1];
                    array.pop();
                }
            }
            userToMinted[msg.sender] = false;
        }
        bool success = IERC20(i_venom).transferFrom(
            msg.sender,
            address(this),
            _amountOfVenomToBurn
        );
        if (!success) {
            revert Engine__TransferFailed();
        }
        i_venom.burn(_amountOfVenomToBurn);

        bool successFul = IERC20(s_collaterals[_index].collateralAddress)
            .transfer(msg.sender, collateralToTransfer);
        if (!successFul) {
            revert Engine__TransferFailed();
        }

        emit CollateralRedeemedForVenom(
            msg.sender,
            s_collaterals[_index].collateralAddress,
            collateralToTransfer
        );
    }

    /**
     * @notice This function burns venom and reduce the user collateral debt position by the amount of venom burnt
     * @param _amountToBurn The amount of venom the user is willing to burn to reduce the user debt position
     * @param _index The index of collateral against venom  to  burn
     */

    function burnVenom(
        uint256 _amountToBurn,
        uint256 _index
    ) external moreThanZero(_amountToBurn) {
        if (
            _amountToBurn >
            userToAmountMinted[msg.sender][
                s_collaterals[_index].collateralAddress
            ]
        ) {
            revert Engine__CannotBurnVenom();
        }
        uint256 mintedBalance = userToAmountMinted[msg.sender][
            s_collaterals[_index].collateralAddress
        ] -= _amountToBurn;

        if (
           mintedBalance == 0
        ) {
            address[] storage array = s_minted;
            for (uint256 i = 0; i < array.length; i++) {
                if (array[i] == msg.sender) {
                    array[i] = array[array.length - 1];
                    array.pop();
                }
            }
            userToMinted[msg.sender] = false;
        }
        bool success = IERC20(i_venom).transferFrom(
            msg.sender,
            address(this),
            _amountToBurn
        );
        if (!success) {
            revert Engine__TransferFailed();
        }
        i_venom.burn(_amountToBurn);

        emit VenomBurnt(_amountToBurn);
    }

    /**
     * @notice This function returns bool checking if the user health factor
     * @param _user This is the address of the  user health factor to be checked
     * @param _amount This is the amount to be passed in to check if the user health factor would be broken
     * @param _index This is the index of the collateral to check against amount minted
     */
    function _checkHealthFactorIsGood(
        address _user,
        uint256 _amount,
        uint256 _index
    ) public view returns (bool) {
        uint256 healthFactor = _calculateHealthFactor(_user, _amount, _index) *
            PERCENTAGE;
        if (healthFactor > s_collaterals[_index].liquidationThreshold) {
            return true;
        }
        return false;
    }

    // We need to use a bot to constantly check for users at liquidation position ??????

    // /**
    //  * @notice This function would be call by a keeper. This function liquidate user with bad health factor and create an auction in collateral would be sold off
    //  */

    // function liquidateAndCreateAuction() public {
    //     address[] memory array = s_minted;
    //     Collateral[] memory collateral = s_collaterals;

    //     for (uint index; index < collateral.length; index++) {
    //         for (uint i; i < array.length; i++) {
    //             uint256 totalCollateralInUsd = _getCollateralInUsd(
    //                 array[i],
    //                 index
    //             );
    //             uint256 amountMinted = userToAmountMinted[array[i]][
    //                 collateral[index].collateralAddress
    //             ];

    //             uint256 healthFactor = ((totalCollateralInUsd * PRECISION) /
    //                 amountMinted) * PERCENTAGE;
    //             uint256 collateralDeposited = userToCollateralDeposited[
    //                 array[i]
    //             ][collateral[index].collateralAddress];

    //             if (
    //                 block.number - userToBlockMinted[array[i]] >= s_blockNumber
    //             ) {
    //                 if (amountMinted > 0) {
    //                     amountMinted +=
    //                         (amountMinted * collateral[index].stabilityFee) /
    //                         PRECISION;
    //                 }
    //             }
    //             ////////////// if collateral cannot cover up amounted minted according to black swan event ...?

    //             if (healthFactor < collateral[index].liquidationThreshold) {
    //                 uint256 startingAuctionPrice = getValueInUsd(
    //                     PRECISION,
    //                     collateral[index].collateralPriceFeed
    //                 ) +
    //                     ((getValueInUsd(
    //                         PRECISION,
    //                         collateral[index].collateralPriceFeed
    //                     ) * BUFFER) / PRECISION);
    //                 if (collateralDeposited != 0) {
    //                     address auction = new DeployAuction().run(
    //                         AUCTION_DURATION,
    //                         collateral[index].collateralAddress,
    //                         amountMinted + collateral[index].penaltyFee,
    //                         address(this),
    //                         startingAuctionPrice,
    //                         AUCTION_DISCOUNT_RATE,
    //                         address(i_venom)
    //                     );
    //                     s_auctionAddresses[i] = auction;
    //                     bool success = IERC20(
    //                         collateral[index].collateralAddress
    //                     ).transfer(auction, collateralDeposited);
    //                     if (!success) {
    //                         revert Engine__TransferFailed();
    //                     }

    //                     collateralDeposited = 0;
    //                 }

    //                 if (
    //                     block.timestamp -
    //                         Auction(s_auctionAddresses[i]).getStartingTime() >=
    //                     AUCTION_DURATION
    //                 ) {
    //                     if (
    //                         Auction(s_auctionAddresses[i])
    //                             .getCollateralAmountToLiquidate() == 0
    //                     ) {
    //                         uint256 auctionBalance = Auction(
    //                             s_auctionAddresses[i]
    //                         ).transferToEngine();
    //                         collateralDeposited = auctionBalance;
    //                         amountMinted = 0;
    //                         userToMinted[array[i]] = false;
    //                         s_minted[i] = s_minted[s_minted.length - 1];
    //                         s_auctionAddresses[i] = s_auctionAddresses[
    //                             s_auctionAddresses.length - 1
    //                         ];
    //                         s_minted.pop();
    //                         s_auctionAddresses.pop();
    //                         i_venom.burn(
    //                             amountMinted + collateral[index].penaltyFee
    //                         );
    //                     } else {
    //                         Auction(s_auctionAddresses[i]).updatePrice(); ////////////// if all collaterals to repay debt position has not be covered from auction sale
    //                     }
    //                 }
    //             }
    //         }
    //     }

    //     s_lastTimeStamp = block.timestamp;
    //     emit liquidatedUserDebtPosition();
    // }

    ///////////////////////////////////
    // AUTOMATION EXTERNAL FUNCTIONS //
    ///////////////////////////////////

    function checkUpkeep(
        bytes memory /*checkData*/
    ) public view returns (bool upkeepNeeded, bytes memory /*performData*/) {
        if (block.timestamp >= i_startAt && mintState != Status.OPEN) {
            uint256 viperBalance = IERC20(i_viper).balanceOf(address(this));
            bool remainingEarlyAdoptersBalance = viperBalance > 0;
            upkeepNeeded = remainingEarlyAdoptersBalance;
           
        }
        if (mintState == Status.OPEN) {
            bool timeHasPassed = block.timestamp - s_lastTimeStamp >= INTERVAL;
            upkeepNeeded = timeHasPassed;
        }
         return  (upkeepNeeded , "0x0");
        
    }

    function performUpkeep(bytes calldata /*performData*/) external {
        (bool upkeepNeeded, ) = checkUpkeep("");
        uint256 viperBalance = IERC20(i_viper).balanceOf(address(this));
        if (!upkeepNeeded) {
            revert Engine__CannotPerformUpkeep(
                block.timestamp,
                s_minted.length
            );
        } else if (upkeepNeeded) {
            if (mintState != Status.OPEN) {
                i_viper.burn(address(this), viperBalance);
                mintState = Status.OPEN;
            }
            // liquidateAndCreateAuction();
        }
    }

    ////////////////////////
    // INTERNAL FUNCTION //
    //////////////////////

    /**
     * @notice This function is user to calculate the health factor of the user before minting
     * @param _user The address of the person to be minted the venom stable coin
     * @param _amount The amount of the venom stable coin the user wants to mint
     * @param _index  The index of the collateral to use to obtain the health factor
     */

    function _calculateHealthFactor(
        address _user,
        uint256 _amount,
        uint256 _index
    ) internal view moreThanZero(_amount) returns (uint256) {
        uint256 collateralInUsd = _getCollateralInUsd(_user, _index);
        uint256 userAmountMinted = userToAmountMinted[_user][
            s_collaterals[_index].collateralAddress
        ];
        if (userToMinted[_user]) {
            return (collateralInUsd * PRECISION) / (userAmountMinted + _amount);
        }
        return (collateralInUsd * PRECISION) / _amount;
    }

    /**
     * @notice This function get the user total collateral in U.S Dollar
     * @param _user This is the address of the user collateral to be gotten in U.S Dollar
     * @param _index The index of the collateral to be gotten in U.S Dollar
     */
    function _getCollateralInUsd(
        address _user,
        uint256 _index
    ) internal view returns (uint256 totalCollateralInUsd) {
        Collateral[] memory collaterals = s_collaterals;

        uint256 collateralAmount = userToCollateralDeposited[_user][
            collaterals[_index].collateralAddress
        ];
        address priceFeed = collaterals[_index].collateralPriceFeed;
        uint256 userCollateralInUsd = getValueInUsd(
            collateralAmount,
            priceFeed
        );
        totalCollateralInUsd += userCollateralInUsd;
    }

    /**
     * @notice This function gets the value of any asset in U.S Dollar given the price feed and amount
     * @param _amount The amount of collateral to be gotten in U.S Dollar
     * @param _priceFeed The address of the contract that returns an asset in U.S Dollar
     */

    function getValueInUsd(
        uint256 _amount,
        address _priceFeed
    ) public view returns (uint256) {
        AggregatorV3Interface aggregatorPriceFeed = AggregatorV3Interface(
            _priceFeed
        );
        (, int256 answer, , , ) = aggregatorPriceFeed.staleCheckLatestRoundData();
        uint256 valueInUsd = (_amount *
            (uint256(answer) * AGGRREGATOR_PRECISION)) / PRECISION;
        return valueInUsd;
    }

    /**
     * @notice This function checks and revert if the health factor of the user is broken
     * @param _user The address of the user to check against his health factor
     * @param _amount The amount the user would pass in to check if it breaks the health factor
     * @param _index The index of the collateral to obtain the health factor
     */
    function checkRedeemCollateralBreaksHealthFactor(
        address _user,
        uint256 _amount,
        uint256 _index
    ) internal view {
        uint256 totalCollateralInUsdAfterRedeem = _getCollateralInUsd(
            _user,
            _index
        ) - getValueInUsd(_amount, s_collaterals[_index].collateralPriceFeed);
        uint256 userAmountMinted = userToAmountMinted[_user][
            s_collaterals[_index].collateralAddress
        ];
        uint256 healthFactorInPercentage = ((totalCollateralInUsdAfterRedeem *
            PRECISION) / userAmountMinted) * PERCENTAGE;
        if (
            healthFactorInPercentage <
            s_collaterals[_index].liquidationThreshold
        ) {
            
            revert Engine__BreaksHealthFactor(_amount);
        }
    }

    ///////////////////////
    // GETTER FUNCTIONS //
    /////////////////////

    function getCollateralLength() public view returns (uint256) {
        return s_collaterals.length;
    }

    function getCollateralInfo(
        uint256 _index
    ) public view returns (address, address, uint256, uint256, uint256) {
        Collateral memory collateral = s_collaterals[_index];
        address collateralAddress = collateral.collateralAddress;
        address collateralPriceFeed = collateral.collateralPriceFeed;
        uint256 liquidationThreshold = collateral.liquidationThreshold;
        uint256 penaltyFee = collateral.penaltyFee;
        uint256 stabilityFee = collateral.stabilityFee;

        return (
            collateralAddress,
            collateralPriceFeed,
            liquidationThreshold,
            penaltyFee,
            stabilityFee
        );
    }

    function getApprovedCollaterals()
        public
        view
        returns (Collateral[] memory)
    {
        return s_collaterals;
    }
    

    function getThreshold(uint256 _index) public view returns (uint256) {
        return s_collaterals[_index].liquidationThreshold;
    }

    function getCollateralValueInUsd(
        address _user,
        uint256 _index
    ) public view returns (uint256) {
        return _getCollateralInUsd(_user, _index);
    }

    function calculateHealthfactor(
        address _user,
        uint256 _amount,
        uint256 _index
    ) public view returns (uint256) {
        return _calculateHealthFactor(_user, _amount, _index);
    }

    function getUserCollateralBalance(
        address _user,
        uint256 _index
    ) public view returns (uint256) {
        return
            userToCollateralDeposited[_user][
                s_collaterals[_index].collateralAddress
            ];
    }

    function getUserMintedBalance(
        address _user,
        uint256 _index
    ) public view returns (uint256) {
        return
            userToAmountMinted[_user][s_collaterals[_index].collateralAddress];
    }

    function getEngineAddress()
        internal
        view
        override(EarlyAdopters, Crowdsale)
        returns (address)
    {
        return address(this);
    }

    function transferViper(
        address _beneficiary,
        uint256 _amount
    ) internal override(EarlyAdopters, Crowdsale) {
        bool success = IERC20(i_viper).transfer(_beneficiary, _amount);
        if (!success) {
            revert Engine__TransferViperFailed();
        }
    }

    function getMintState() external view returns (uint256) {
        return uint256(mintState);
    }

    function getEarlyAdoptersDuration() external pure returns (uint256) {
        return earlyAdoptersDuration;
    }

    function getEarlyAdoptersTotalTokenDeposited()
        external
        pure
        returns (uint256)
    {
        return earlyAdoptersTotalTokenDeposited;
    }

    function getCrowdSaleStartAt() external pure returns (uint256) {
        return crowdSaleStartAt;
    }

    function getCrowdSaleduration() external pure returns (uint256) {
        return crowdSaleduration;
    }

    function getDebtCeiling() external view returns (uint256) {
        return s_debtCeiling;
    }

    function getMinted(uint256 _index) external view returns (address) {
        return s_minted[_index];
    }

    function getUserMinted(address _user) external view returns (bool) {
        return userToMinted[_user];
    }

    function getUserBlockNumber(address _user) external view returns (uint256) {
        return userToBlockMinted[_user];
    }

    function getAmountMinted() external view returns (uint256) {
        return s_minted.length;
    }

    function getEngineStartAt() external view returns(uint256) {
        return i_startAt;
    }
}
