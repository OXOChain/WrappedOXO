// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "./ERC20.sol";
import "./ERC20Burnable.sol";
import "./Pausable.sol";
import "./Ownable.sol";
import "./DateTimeLibrary.sol";

/// @custom:security-contact info@oxochain.com
contract wOXO is ERC20, ERC20Burnable, Pausable, Ownable {
    using BokkyPooBahsDateTimeLibrary for uint256;

    address _GNOSIS_SAFE_WALLET = 0x3edF93dc2e32fD796c108118f73fa2ae585C66B6;
    bool _unlockAll = false;

    uint256 _transferableByFoundation;
    uint256 _totalSales;
    uint256 _totalTranferredToFoundation;

    // User Info

    struct userInfo {
        address user;
        bool buyBackGuarantee;
        uint256 totalCoinsFromSales;
        uint256 totalBuyBackCoins;
        uint256 totalBuyBackUSD;
        uint256 balanceUSD;
    }
    address[] allUsers;

    mapping(address => uint256) _userIndex;
    mapping(address => userInfo) public _userInfoByAddress;

    // Deposits

    struct Deposit {
        address user;
        address payToken;
        uint256 amount;
        uint256 timestamp;
    }

    Deposit[] _Deposits;
    mapping(address => Deposit[]) _depositsByUser;

    // Total Deposit Amount
    uint256 _totalDepositAmount;
    // User Deposits
    mapping(address => uint256) _userDeposits;
    // User Deposits as PayToken
    mapping(address => mapping(address => uint256)) _userDepositsAsToken;
    // Deposits as PayToken
    mapping(address => uint256) _depositsAsPayToken;
    // Withdrawn from PayToken
    mapping(address => uint256) _withdrawnFromPayToken;

    mapping(address => bool) _validPayToken;
    mapping(address => uint256) _payTokenIndex;

    // PayTokens

    struct payToken {
        string name;
        address contractAddress;
    }
    payToken[] public _payTokens;

    // Sales Information

    struct PrivateSale {
        uint256 price;
        uint256 totalCoins;
        uint256 min;
        uint256 max;
        uint256 saleStartTime;
        uint256 saleEndTime;
        uint256 unlockTime;
        uint256 totalSales;
    }

    PrivateSale[] public privateSales;

    struct PublicSale {
        uint256 price;
        uint256 totalCoins;
        uint256 min;
        uint256 max;
        uint256 saleStartTime;
        uint256 saleEndTime;
        uint256 unlockTime;
        uint256 totalSales;
    }

    PublicSale[] public publicSales;

    bool AddedPrivateSales;
    bool AddedPublicSales;

    enum SalesType {
        PRIVATE,
        PUBLIC
    }

    // Purchases

    struct Purchase {
        address user;
        uint256 userPurchaseNonce;
        uint256 orderTime;
        uint256 orderBlock;
        SalesType salesType;
        uint8 stage;
        uint256 coinPrice;
        uint256 totalCoin;
        uint256 totalUSD;
        bool buyBack;
        uint256 unlockTime;
    }

    mapping(address => Purchase[]) public _userPurchases;
    mapping(address => mapping(SalesType => mapping(uint256 => uint256)))
        public _coinsPurchasedByUserInTheStage;

    struct UserPurchaseSummary {
        address user;
        Purchase[] userPurchases;
    }

    // Buy Back Records

    struct BuyBackLog {
        address user;
        uint256 buyBackTime;
        uint256 orderTime;
        SalesType salesType;
        uint8 stage;
        uint256 totalCoin;
        uint256 totalUSD;
    }

    mapping(address => BuyBackLog[]) _userBuyBacks;

    // Withdrawns

    struct Withdrawn {
        address user;
        uint256 withdrawnTime;
        address payToken;
        uint256 amount;
    }

    mapping(address => Withdrawn[]) _userWithdrawns;
    Withdrawn[] _withdrawns;

    // Events

    event DepositUSD(address, uint256, address);
    event WithdrawnUSD(address, uint256, address);
    event Purchased(address, SalesType, uint8, uint256, uint256);

    /** CONSTRUCTOR */

    constructor() ERC20("Wrapped OXO", "wOXO") {
        _initPayTokens();
    }

    /** **************************** */
    function forTesting_purchaseFromSales(
        address user,
        SalesType salesType,
        uint8 stage,
        uint256 totalUSD
    ) public onlyOwner returns (bool) {
        return _purchaseFromSales(user, salesType, stage, totalUSD);
    }

    /** **************************** */

    function purchaseFromSales(
        SalesType salesType,
        uint8 stage,
        uint256 totalUSD
    ) public returns (bool) {
        return _purchaseFromSales(msg.sender, salesType, stage, totalUSD);
    }

    function _purchaseFromSales(
        address user,
        SalesType salesType,
        uint8 stage,
        uint256 totalUSD
    ) internal returns (bool) {
        //uint256 uIndex = _userIndex[user];

        require(_userDeposits[user] != 0, "You did not deposit yet");

        require(totalUSD > 0, "This is not airdrop!");

        require(
            _userInfoByAddress[user].balanceUSD >= totalUSD,
            "Hoop, you do not have that USD!"
        );

        uint256 blockTimeStamp = getBlockTimeStamp();
        uint256 requestedCoins = 0;
        uint256 coinPrice = 0;
        uint256 unlockTime = 0;
        uint256 CoinsPurchasedByUserInTheStage = _coinsPurchasedByUserInTheStage[
                user
            ][salesType][stage];

        if (salesType == SalesType.PRIVATE) {
            // 0 - 1 - 2
            require(stage >= 0 && stage <= 2, "stage number is not valid");

            PrivateSale memory p = privateSales[stage];

            // is stage active?
            require(
                p.saleStartTime <= blockTimeStamp &&
                    p.saleEndTime >= blockTimeStamp,
                "This stage is not active for now"
            );

            // calculate OXOs for that USD
            // requestedCoins = ((totalUSD * 1e4) / p.price) * 1e14;
            requestedCoins = ((totalUSD) / p.price) * 1e18;

            totalUSD = (requestedCoins * p.price) / 1e18;
            // is there enough OXOs?
            require(
                p.totalCoins - p.totalSales >= requestedCoins,
                "You request more coins than buyable"
            );

            // check user's purchases for min/max limits
            require(
                p.min <= CoinsPurchasedByUserInTheStage + requestedCoins &&
                    p.max >= CoinsPurchasedByUserInTheStage + requestedCoins,
                "Houston, There are minimum and maximum purchase limits"
            );

            // update privateSales Stage purchased OXOs
            privateSales[stage].totalSales =
                privateSales[stage].totalSales +
                requestedCoins;

            coinPrice = p.price;
            unlockTime = p.unlockTime;

            _transferableByFoundation += totalUSD;
        }

        if (salesType == SalesType.PUBLIC) {
            require(stage >= 0 && stage <= 20, "Wrong stage number");

            PublicSale memory p = publicSales[stage];

            // is stage active?
            require(
                p.saleStartTime <= blockTimeStamp &&
                    p.saleEndTime >= blockTimeStamp,
                "This stage is not active for now"
            );

            // calculate OXOs for that USD
            //requestedCoins = ((totalUSD * 1e2) / p.price) * 1e16;
            requestedCoins = ((totalUSD) / p.price) * 1e18;
            totalUSD = (requestedCoins * p.price) / 1e18;

            // is there enough OXOs?
            require(
                p.totalCoins - p.totalSales >= requestedCoins,
                "You request more coins than buyable"
            );

            // check user's purchases for min/max limits
            require(
                p.min <= CoinsPurchasedByUserInTheStage + requestedCoins &&
                    p.max >= CoinsPurchasedByUserInTheStage + requestedCoins,
                "Houston, There are minimum and maximum purchase limits"
            );

            // update privateSales Stage purchased OXOs
            publicSales[stage].totalSales =
                publicSales[stage].totalSales +
                requestedCoins;

            coinPrice = p.price;
            unlockTime = p.unlockTime;

            // %80 for BuyBack - %20 Transferable
            _transferableByFoundation += (totalUSD * 20) / 100;
        }

        // Get User Purchases Count
        uint256 userPurchaseCount = _userPurchases[user].length + 1;

        /// New Purchase Record
        _userPurchases[user].push(
            Purchase({
                user: user,
                userPurchaseNonce: userPurchaseCount,
                orderTime: blockTimeStamp,
                orderBlock: block.number,
                salesType: salesType,
                stage: stage,
                coinPrice: coinPrice,
                totalCoin: requestedCoins,
                totalUSD: totalUSD,
                buyBack: false,
                unlockTime: unlockTime
            })
        );

        _totalSales += totalUSD;

        _userInfoByAddress[user].totalCoinsFromSales =
            _userInfoByAddress[user].totalCoinsFromSales +
            requestedCoins;

        // UserBalance change
        _userInfoByAddress[user].balanceUSD =
            _userInfoByAddress[user].balanceUSD -
            totalUSD;

        // Update user's OXOs count for stage
        _coinsPurchasedByUserInTheStage[user][salesType][stage] =
            CoinsPurchasedByUserInTheStage +
            requestedCoins;

        // Mint Tokens
        _mintFromSales(user, requestedCoins);

        // check available coin amount for stage
        if (salesType == SalesType.PUBLIC) {
            if (
                publicSales[stage].totalCoins - publicSales[stage].totalSales >
                publicSales[stage].min
            ) {
                setStageEndTime(stage, (blockTimeStamp + 1));
            }
        }

        emit Purchased(user, salesType, stage, requestedCoins, totalUSD);

        return true;
    }

    /** *********************** */
    function forTesting_requestBuyBack(address user, uint256 userPurchaseNonce)
        public
        onlyOwner
        returns (bool)
    {
        return _requestBuyBack(user, userPurchaseNonce);
    }

    /** *********************** */

    function requestBuyBack(uint256 userPurchaseNonce) public returns (bool) {
        return _requestBuyBack(msg.sender, userPurchaseNonce);
    }

    function _requestBuyBack(address user, uint256 userPurchaseNonce)
        internal
        returns (bool)
    {
        require(
            _userInfoByAddress[user].buyBackGuarantee,
            "You dont have BuyBack guarantee!"
        );

        uint256 blockTimeStamp = getBlockTimeStamp();

        require(
            publicSales[20].unlockTime + 1 days < blockTimeStamp &&
                blockTimeStamp <= publicSales[20].unlockTime + 90 days,
            "BuyBack guarantee is not possible at this time!"
        );

        if (
            _userPurchases[user][userPurchaseNonce].buyBack == false &&
            _userPurchases[user][userPurchaseNonce].userPurchaseNonce ==
            userPurchaseNonce
        ) {
            uint256 totalBuyBackCoins = _userPurchases[user][userPurchaseNonce]
                .totalCoin;

            // Calculate USD
            uint256 totalBuyBackUSD = (_userPurchases[user][userPurchaseNonce]
                .totalUSD * 80) / 100;

            // BuyBackLogs for User
            _userBuyBacks[user].push(
                BuyBackLog({
                    user: user,
                    buyBackTime: blockTimeStamp,
                    orderTime: _userPurchases[user][userPurchaseNonce]
                        .orderTime,
                    salesType: _userPurchases[user][userPurchaseNonce]
                        .salesType,
                    stage: _userPurchases[user][userPurchaseNonce].stage,
                    totalCoin: totalBuyBackCoins,
                    totalUSD: totalBuyBackUSD
                })
            );

            // Change BuyBack Status
            _userPurchases[user][userPurchaseNonce].buyBack = true;

            // USD
            _userInfoByAddress[user].totalBuyBackUSD =
                _userInfoByAddress[user].totalBuyBackUSD +
                totalBuyBackUSD;

            // Added USD to UserBalance
            _userInfoByAddress[user].balanceUSD =
                _userInfoByAddress[user].balanceUSD +
                totalBuyBackUSD;

            // Change userInfo - Remove coins from totalCoinsFromSales and add to totalBuyBackCoins
            _userInfoByAddress[user].totalCoinsFromSales =
                _userInfoByAddress[user].totalCoinsFromSales -
                totalBuyBackCoins;

            _userInfoByAddress[user].totalBuyBackCoins =
                _userInfoByAddress[user].totalBuyBackCoins +
                totalBuyBackCoins;

            // Burn Coins
            _burnForBuyBack(user, totalBuyBackCoins);
            return true;
        }
        return false;
    }

    function getUserPurchases(address _user)
        public
        view
        returns (UserPurchaseSummary memory)
    {
        UserPurchaseSummary memory ups = UserPurchaseSummary(
            _user,
            _userPurchases[_user]
        );
        return ups;
    }

    function _initPayTokens() internal {
        _payTokens.push(
            payToken(
                "USDT: Binance-Peg",
                0x55d398326f99059fF775485246999027B3197955
            )
        );

        _payTokens.push(
            payToken(
                "USDC: Binance-Peg",
                0x8AC76a51cc950d9822D68b83fE1Ad97B32Cd580d
            )
        );

        _payTokens.push(
            payToken(
                "BUSD: Binance-Peg",
                0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56
            )
        );

        _payTokens.push(
            payToken(
                "DAI: Binance-Peg",
                0x1AF3F329e8BE154074D8769D1FFa4eE058B1DBc3
            )
        );

        _payTokens.push(
            payToken(
                "TUSD: Binance-Peg",
                0x14016E85a25aeb13065688cAFB43044C2ef86784
            )
        );

        _payTokens.push(
            payToken(
                "USDP: Binance-Peg",
                0xb3c11196A4f3b1da7c23d9FB0A3dDE9c6340934F
            )
        );

        for (uint256 i = 0; i < _payTokens.length; i++) {
            _validPayToken[_payTokens[i].contractAddress] = true;
            _payTokenIndex[_payTokens[i].contractAddress] = i;
        }
    }

    function _blockTimeStamp() public view returns (uint256) {
        return block.timestamp;
    }

    uint256 testingTimeStamp = 0;

    function forTesting_BlockTimeStamp(uint256 _testingTimeStamp)
        public
        onlyOwner
        returns (bool)
    {
        testingTimeStamp = _testingTimeStamp;
        return true;
    }

    function getBlockTimeStamp() public view returns (uint256) {
        if (testingTimeStamp != 0) return testingTimeStamp;
        return block.timestamp;
    }

    function timestampFromDateTime(
        uint256 year,
        uint256 month,
        uint256 day,
        uint256 hour,
        uint256 minute,
        uint256 second
    ) public pure returns (uint256 timestamp) {
        return
            BokkyPooBahsDateTimeLibrary.timestampFromDateTime(
                year,
                month,
                day,
                hour,
                minute,
                second
            );
    }

    function timestampToDateTime(uint256 timestamp)
        public
        pure
        returns (
            uint256 year,
            uint256 month,
            uint256 day,
            uint256 hour,
            uint256 minute,
            uint256 second
        )
    {
        (year, month, day, hour, minute, second) = BokkyPooBahsDateTimeLibrary
            .timestampToDateTime(timestamp);
    }

    function _addPrivateSaleDetails(
        uint256 year,
        uint256 month,
        uint256 day,
        uint256 hour,
        uint256 minute
    ) public onlyOwner {
        require(!AddedPrivateSales, "Private sales details already added");
        uint256 _startTime = timestampFromDateTime(
            year,
            month,
            day,
            hour,
            minute,
            0
        );

        uint256 _endTime = _startTime + 30 days;

        privateSales.push(
            PrivateSale({
                price: 0.040 * 1e18,
                totalCoins: 4_800_000 * 1e18,
                min: 20_000 * 1e18,
                max: 400_000 * 1e18,
                saleStartTime: _startTime,
                saleEndTime: _endTime - 1,
                unlockTime: _endTime + 360 days,
                totalSales: 0
            })
        );
        privateSales.push(
            PrivateSale({
                price: 0.055 * 1e18,
                totalCoins: 4_800_000 * 1e18,
                min: 5_000 * 1e18,
                max: 200_000 * 1e18,
                saleStartTime: _startTime,
                saleEndTime: _endTime - 1,
                unlockTime: _endTime + 270 days,
                totalSales: 0
            })
        );
        privateSales.push(
            PrivateSale({
                price: 0.070 * 1e18,
                totalCoins: 4_800_000 * 1e18,
                min: 2_000 * 1e18,
                max: 100_000 * 1e18,
                saleStartTime: _startTime,
                saleEndTime: _endTime - 1,
                unlockTime: _endTime + 180 days,
                totalSales: 0
            })
        );
        AddedPrivateSales = true;
    }

    function _addPublicSaleDetails(
        uint256 year,
        uint256 month,
        uint256 day,
        uint256 hour,
        uint256 minute,
        uint256 stage0Coins,
        uint256 stage1Coins,
        uint256 coinReduction
    ) public onlyOwner {
        require(!AddedPublicSales, "Public sales details already added");

        uint256 _startTime = timestampFromDateTime(
            year,
            month,
            day,
            hour,
            minute,
            0
        );

        if (stage0Coins == 0) stage0Coins = 9_600_000;
        if (stage1Coins == 0) stage1Coins = 5_000_000;
        if (coinReduction == 0) coinReduction = 0;

        // stage 0
        publicSales.push(
            PublicSale({
                price: 0.10 * 1e18,
                totalCoins: stage0Coins * 1e18,
                min: 500 * 1e18,
                max: 500_000 * 1e18,
                saleStartTime: _startTime,
                saleEndTime: _startTime + 14 days - 1,
                unlockTime: 0, //_startTime + 161 days,
                totalSales: 0
            })
        );

        // stage 1-20
        for (uint256 i = 1; i <= 20; i++) {
            uint256 _totalCoins = (stage1Coins - ((i - 1) * coinReduction)) *
                1e18;
            uint256 _price = (0.13 * 1e18) + ((i - 1) * (0.02 * 1e18));

            if (i >= 5) {
                _price += (0.02 * 1e18);
            }

            if (i >= 9) {
                _price += (0.03 * 1e18);
            }

            if (i >= 13) {
                _price += (0.04 * 1e18);
            }

            if (i >= 17) {
                _price += (0.05 * 1e18);
            }

            uint256 startTime = _startTime + ((i + 1) * 7 days);

            publicSales.push(
                PublicSale({
                    price: _price,
                    totalCoins: _totalCoins,
                    min: 100 * 1e18,
                    max: 500_000 * 1e18,
                    saleStartTime: startTime,
                    saleEndTime: startTime + 7 days - 1,
                    unlockTime: 0,
                    totalSales: 0
                })
            );
        }

        AddedPublicSales = true;
        _setUnlockTimes();
    }

    function _setUnlockTimes() internal returns (bool) {
        require(AddedPublicSales, "Houston!");
        uint256 Stage20EndTime = publicSales[20].saleEndTime;
        for (uint8 i = 0; i <= 20; i++) {
            publicSales[i].unlockTime = Stage20EndTime + ((21 - i) * 1 days);
        }
        return true;
    }

    function setStageEndTime(uint8 _stage, uint256 _endTime) public onlyOwner {
        _setStageEndTime(_stage, _endTime);
    }

    function _setStageEndTime(uint8 _stage, uint256 _endTime)
        internal
        returns (bool)
    {
        require(_stage >= 0 && _stage <= 20, "Stage is not valid");
        require(
            _endTime < publicSales[_stage].saleEndTime &&
                _endTime > publicSales[_stage].saleStartTime,
            "Wrong dates!"
        );

        publicSales[_stage].saleEndTime = _endTime;
        if (_stage != 20) _setStageTime(_stage + 1);

        // Dont need to change unlock times
        //_setUnlockTimes();

        return true;
    }

    // Set stage start and end time after stage 2
    function _setStageTime(uint8 _stage) internal returns (bool) {
        require(_stage >= 1 && _stage <= 20, "Stage is not valid");

        uint256 previousStageStartTime = publicSales[_stage - 1].saleStartTime;
        uint256 previousStageEndTime = publicSales[_stage - 1].saleEndTime;

        uint256 previousStageDays = 7 days;

        if (_stage == 1) previousStageDays = 14 days;

        uint256 fixStageTime = previousStageDays -
            (previousStageEndTime - previousStageStartTime);

        fixStageTime -= 1 hours; // 1 hours break time :)

        for (uint8 i = _stage; i <= 20; i++) {
            // change start time
            publicSales[i].saleStartTime =
                publicSales[i].saleStartTime -
                fixStageTime;

            // change end time
            publicSales[i].saleEndTime =
                publicSales[i].saleEndTime -
                fixStageTime;
        }
        return true;
    }

    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }

    function unlockAll() public onlyOwner {
        _unlockAll = true;
    }

    function mint(address to, uint256 amount) public onlyOwner {
        _mint(to, amount);
    }

    function transfer(address to, uint256 amount)
        public
        override
        returns (bool)
    {
        // Check Locked Coins
        uint256 balance = balanceOf(msg.sender); //
        require(amount <= balance, "Houston, we have a problem!");
        return super.transfer(to, amount);
    }

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) public override returns (bool) {
        // Check Locked Coins
        uint256 balance = balanceOf(from); //
        require(amount <= balance, "Houston, we have a problem!");
        return super.transferFrom(from, to, amount);
    }

    function balanceOf(address who) public view override returns (uint256) {
        uint256 lockedBalance = _checkLockedCoins(who);
        uint256 visibleBalance = super.balanceOf(who) - lockedBalance;
        return visibleBalance;
    }

    function allBalanceOf(address who) public view returns (uint256) {
        return super.balanceOf(who);
    }

    /** Calculate */
    function _checkLockedCoins(address _who) internal view returns (uint256) {
        uint256 blockTimeStamp = getBlockTimeStamp();
        /// There is no lock anymore
        if (_unlockAll) {
            return 0;
        }

        // the user did not particioate in the sales.
        uint256 uIndex = _userIndex[_who];
        if (uIndex == 0) {
            return 0;
        }

        // /// All coins locked before end of Public Sales
        if (publicSales[20].unlockTime + 1 days > blockTimeStamp) {
            return _userInfoByAddress[_who].totalCoinsFromSales;
        }

        // Check all purchase history
        Purchase[] memory up = _userPurchases[_who];
        uint256 AmoutOfLockedCoins = 0;
        for (uint256 i = 1; i < up.length; i++) {
            if (up[i].buyBack != true) {
                // if coins from Private Sales & unlock time has not pass
                if (
                    up[i].salesType == SalesType.PRIVATE &&
                    //x[i].unlockTime > blockTimeStamp
                    privateSales[up[i].stage].unlockTime > blockTimeStamp
                ) {
                    AmoutOfLockedCoins += up[i].totalCoin;
                }

                // if coins from Public sales & unlock time has not pass
                if (
                    up[i].salesType == SalesType.PUBLIC &&
                    publicSales[up[i].stage].unlockTime > blockTimeStamp
                ) {
                    AmoutOfLockedCoins += up[i].totalCoin;
                }

                if (
                    up[i].salesType == SalesType.PUBLIC &&
                    (blockTimeStamp > publicSales[up[i].stage].unlockTime &&
                        blockTimeStamp <=
                        publicSales[up[i].stage].unlockTime + 20 days)
                ) {
                    uint256 pastTime = blockTimeStamp -
                        publicSales[up[i].stage].unlockTime;
                    uint256 pastDays = 0;

                    pastTime =
                        blockTimeStamp -
                        publicSales[up[i].stage].unlockTime;

                    if (pastTime <= 1 days) {
                        pastDays = 1;
                    } else {
                        pastDays =
                            ((pastTime - (pastTime % 1 days)) / 1 days) +
                            1;
                        if (pastTime % 1 days == 0) {
                            pastDays -= 1;
                        }
                    }

                    if (pastDays >= 1 && pastDays <= 20) {
                        AmoutOfLockedCoins +=
                            (up[i].totalCoin * (20 - pastDays)) /
                            20;
                    }
                }
            }
        }

        return AmoutOfLockedCoins;
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal override whenNotPaused {
        // Check for locked coins
        require(balanceOf(from) >= amount, "Your balance is not enough!");
        super._beforeTokenTransfer(from, to, amount);
    }

    /** ONLYOWNER */
    function addOrEditPayToken(address _tokenAddress, string memory _name)
        external
        onlyOwner
        returns (bool)
    {
        IERC20PayToken ERC20PayToken = IERC20PayToken(address(_tokenAddress));
        require(
            ERC20PayToken.decimals() == 18,
            "Only 18 decimals stable USD tokens accepted"
        );

        uint256 ptIndex = _payTokenIndex[_tokenAddress];
        if (ptIndex == 0) {
            _validPayToken[_tokenAddress] = true;
            _payTokens.push(
                payToken({name: _name, contractAddress: _tokenAddress})
            );
            ptIndex = _payTokens.length;
            _payTokenIndex[_tokenAddress] = ptIndex;
            return true;
        } else {
            _payTokens[ptIndex] = payToken({
                name: _name,
                contractAddress: _tokenAddress
            });
        }
        return true;
    }

    function transferTokensToGnosis(address _tokenAddress) external onlyOwner {
        uint256 blockTimeStamp = getBlockTimeStamp();

        IERC20PayToken ERC20PayToken = IERC20PayToken(address(_tokenAddress));
        uint256 tokenBalance = ERC20PayToken.balanceOf(address(this));

        uint256 transferable = tokenBalance;

        if (_validPayToken[_tokenAddress]) {
            transferable =
                _transferableByFoundation -
                _totalTranferredToFoundation;

            // After BuyBack
            if (publicSales[20].unlockTime + 90 days < blockTimeStamp) {
                transferable = tokenBalance;
            }

            if (tokenBalance < transferable) transferable = tokenBalance;
            _totalTranferredToFoundation += transferable;
        }

        _withdrawnFromPayToken[_tokenAddress] =
            _withdrawnFromPayToken[_tokenAddress] +
            transferable;

        ERC20PayToken.transfer(_GNOSIS_SAFE_WALLET, transferable);

        emit WithdrawnUSD(_GNOSIS_SAFE_WALLET, transferable, _tokenAddress);
    }

    function transferCoinsToGnosis() external onlyOwner {
        uint256 _balance = address(this).balance;
        //if (_balance >= _amount) {
        payable(_GNOSIS_SAFE_WALLET).transfer(_balance);
        //}
    }

    function unlockEveryone() external onlyOwner {
        _unlockAll = true;
    }

    /** *************** */
    function forTesting_DepositMoney(
        address _user,
        uint256 _amount,
        address _tokenAddress
    ) public onlyOwner {
        _depositMoney(_user, _amount, _tokenAddress);
    }

    /** *************** */

    /** Deposit Money */
    function depositMoney(uint256 _amount, address _tokenAddress) external {
        // require(_canBeDeposited, "You can not deposit");

        require(
            _validPayToken[_tokenAddress],
            "We do not accept this ERC20 token!"
        );

        IERC20PayToken ERC20PayToken = IERC20PayToken(address(_tokenAddress));

        // Firstly checking user approve result
        require(
            ERC20PayToken.allowance(msg.sender, address(this)) >= _amount,
            "Houston, You do not approve this amount for transfer to us"
        );
        // Check user's payToken balance
        uint256 tokenBalance = ERC20PayToken.balanceOf(msg.sender);

        require(tokenBalance >= _amount, "You can not deposit");

        // get/create user record

        // Transfer payToken to US
        ERC20PayToken.transferFrom(msg.sender, address(this), _amount);

        _depositMoney(msg.sender, _amount, _tokenAddress);
    }

    function _depositMoney(
        address _user,
        uint256 _amount,
        address _tokenAddress
    ) internal {
        uint256 blockTimeStamp = getBlockTimeStamp();

        getUserIndex(_user);
        _totalDepositAmount += _amount; //  All USD token Deposits
        _depositsAsPayToken[_tokenAddress] += _amount; // Deposits as PayToken
        _userDeposits[_user] += _amount; // User Deposits
        _userDepositsAsToken[_user][_tokenAddress] += _amount; // User Deposits as PayToken
        _userInfoByAddress[_user].balanceUSD += _amount; // User USD Balance

        _depositsByUser[_user].push(
            Deposit({
                user: _user,
                payToken: _tokenAddress,
                amount: _amount,
                timestamp: blockTimeStamp
            })
        );

        _Deposits.push(
            Deposit({
                user: _user,
                payToken: _tokenAddress,
                amount: _amount,
                timestamp: blockTimeStamp
            })
        );

        emit DepositUSD(_user, _amount, _tokenAddress);
    }

    /** ******************** */
    function forTesting_WithdrawnMoney(address _user, uint256 _amount)
        public
        returns (bool)
    {
        return _withdrawnMoney(_user, _amount);
    }

    /** ******************** */

    function withdrawnMoney(uint256 _amount) public returns (bool) {
        return _withdrawnMoney(msg.sender, _amount);
    }

    function _withdrawnMoney(address _user, uint256 _amount)
        internal
        returns (bool)
    {
        require(
            _userInfoByAddress[_user].balanceUSD >= _amount,
            "You can not Withdrawn!"
        );

        uint256 blockTimeStamp = getBlockTimeStamp();
        bool transfered = false;
        for (uint256 i = 0; i < _payTokens.length; i++) {
            if (!transfered) {
                IERC20PayToken ERC20PayToken = IERC20PayToken(
                    address(_payTokens[i].contractAddress)
                );
                uint256 tokenBalance = ERC20PayToken.balanceOf(address(this));
                if (tokenBalance >= _amount) {
                    _userInfoByAddress[_user].balanceUSD =
                        _userInfoByAddress[_user].balanceUSD -
                        _amount;
                    _userWithdrawns[_user].push(
                        Withdrawn({
                            user: _user,
                            withdrawnTime: blockTimeStamp,
                            payToken: _payTokens[i].contractAddress,
                            amount: _amount
                        })
                    );

                    _withdrawns.push(
                        Withdrawn({
                            user: _user,
                            withdrawnTime: blockTimeStamp,
                            payToken: _payTokens[i].contractAddress,
                            amount: _amount
                        })
                    );

                    _withdrawnFromPayToken[_payTokens[i].contractAddress] =
                        _withdrawnFromPayToken[_payTokens[i].contractAddress] +
                        _amount;

                    ERC20PayToken.transfer(_user, _amount);

                    transfered = true;

                    emit WithdrawnUSD(
                        _user,
                        _amount,
                        _payTokens[i].contractAddress
                    );
                    break;
                }
            }
        }

        return true;
    }

    function getUserIndex(address _user) internal returns (uint256) {
        uint256 uIndex = _userIndex[_user];
        if (uIndex == 0) {
            allUsers.push(_user);
            uIndex = allUsers.length;
            _userIndex[_user] = uIndex;
            _userInfoByAddress[_user].user = _user;
            _userInfoByAddress[_user].buyBackGuarantee = true;
            //_userPurchases[_user].push();
        }
        return uIndex;
    }
}

// Interfaces of ERC20 USD Tokens
interface IERC20PayToken {
    function totalSupply() external view returns (uint256);

    function decimals() external view returns (uint8);

    function balanceOf(address account) external view returns (uint256);

    function transfer(address to, uint256 amount) external returns (bool);

    function allowance(address owner, address spender)
        external
        view
        returns (uint256);

    function approve(address spender, uint256 amount) external returns (bool);

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) external returns (bool);
}
