// SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;

import "./ERC20.sol";
import "./ERC20Burnable.sol";
import "./Pausable.sol";
import "./Ownable.sol";
import "./DateTimeLibrary.sol";

/// @custom:security-contact info@oxochain.com
contract wOXO is ERC20, ERC20Burnable, Pausable, Ownable {
    using BokkyPooBahsDateTimeLibrary for uint256;

    address private constant _GNOSIS_SAFE_WALLET =
        0x3edF93dc2e32fD796c108118f73fa2ae585C66B6;

    uint256 public _transferableByFoundation;
    uint256 public _totalSales;
    uint256 public _totalTranferredToFoundation;

    bool public _unlockAll = false;

    struct Deposit {
        address user;
        address payToken;
        uint256 amount;
        uint256 timestamp;
    }

    Deposit[] public _Deposits;
    mapping(address => Deposit[]) _DepositsByUser;

    address[] public allUsers;

    mapping(address => uint256) public _userIndex;

    struct UserInfo {
        address user;
        bool buyBackGuarantee;
        uint256 totalCoinsFromSales;
        uint256 totalBuyBackCoins;
        uint256 _userBuyBackUSD;
        uint256 usdBalance;
    }

    mapping(address => UserInfo) public _userInfoByAddress;

    // Total Deposit Amount
    uint256 public _totalDepositAmount;
    // User Deposits
    mapping(address => uint256) public _UserDeposits; // _UserDeposits[address] = 100
    // User Deposits as PayToken
    mapping(address => mapping(address => uint256)) public _UserDepositsAsToken; // _UserDepositsAsToken[user][usdtoken] = 100
    // Deposits as PayToken
    mapping(address => uint256) public _DepositsAsPayToken; // _DepositsAsPayToken[token] = 10000

    mapping(address => bool) public ValidPayToken;

    mapping(address => uint256) public payTokenIndex;

    struct payToken {
        string name;
        address contractAddress;
    }

    payToken[] public _payTokens;

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

    struct Purchase {
        address user;
        uint256 userPurchaseId;
        uint256 orderTime;
        uint256 orderBlock;
        SalesType salesType;
        uint8 round;
        uint256 coinPrice;
        uint256 totalCoin;
        uint256 totalUSD;
        bool buyBack;
        uint256 unlockTime;
    }

    mapping(address => Purchase[]) public _UserPurchases;

    struct UserPurchaseSummary {
        address user;
        Purchase[] user_sales;
    }

    struct BuyBackLog {
        address user;
        uint256 buyBackTime;
        uint256 orderTime;
        SalesType salesType;
        uint8 round;
        uint256 totalCoin;
        uint256 totalUSD;
    }
    mapping(address => BuyBackLog[]) public _userBuyBacks;
    //mapping(address => uint256) public _userBuyBackCoins;
    //mapping(address => uint256) public _userBuyBackUSD;

    struct Withdraw {
        address user;
        uint256 withdrawTime;
        address payToken;
        uint256 amount;
    }

    mapping(address => Withdraw[]) public _userWithdraws;
    Withdraw[] public _Withdraws;

    //mapping(address => uint256) public _userUsdBalance;

    mapping(address => mapping(SalesType => mapping(uint256 => uint256)))
        public _CoinsPurchasedByUserInTheRound;

    event DepositUSD(address, uint256, address);

    /** CONSTRUCTOR */

    constructor() ERC20("Wrapped OXO Chain", "wOXO") {
        _initPayTokens();
    }

    /** **************************** */
    function Test_PurchaseFromSales(
        address user,
        SalesType salesType,
        uint8 round,
        uint256 totalUSD
    ) public onlyOwner returns (bool) {
        return _PurchaseFromSales(user, salesType, round, totalUSD);
    }

    /** **************************** */

    function PurchaseFromSales(
        SalesType salesType,
        uint8 round,
        uint256 totalUSD
    ) public returns (bool) {
        return _PurchaseFromSales(msg.sender, salesType, round, totalUSD);
    }

    function _PurchaseFromSales(
        address user,
        SalesType salesType,
        uint8 round,
        uint256 totalUSD
    ) internal returns (bool) {
        //uint256 uIndex = _userIndex[user];
        require(_UserDeposits[user] != 0, "You did not deposit");

        require(totalUSD > 0, "Funny, you dont have balance for purchases!");

        require(
            _userInfoByAddress[user].usdBalance >= totalUSD,
            "Hoop, you dont have that USD!"
        );

        uint256 blockTimeStamp = GetBlockTimeStamp();
        uint256 requestedCoins = 0;
        uint256 coinPrice = 0;
        uint256 unlockTime = 0;
        uint256 CoinsPurchasedByUserInTheRound = _CoinsPurchasedByUserInTheRound[
                user
            ][salesType][round];

        if (salesType == SalesType.PRIVATE) {
            // 0 - 1 - 2
            require(round >= 0 && round <= 2, "round number is not valid");

            PrivateSale memory p = privateSales[round];

            // is round active?
            require(
                p.saleStartTime <= blockTimeStamp &&
                    p.saleEndTime >= blockTimeStamp,
                "This round is not active for now"
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
                p.min <= CoinsPurchasedByUserInTheRound + requestedCoins &&
                    p.max >= CoinsPurchasedByUserInTheRound + requestedCoins,
                "Houston, There are minimum and maximum purchase limits"
            );

            // update privateSales Round purchased OXOs
            privateSales[round].totalSales =
                privateSales[round].totalSales +
                requestedCoins;

            coinPrice = p.price;
            unlockTime = p.unlockTime;

            _transferableByFoundation += totalUSD;
        }

        if (salesType == SalesType.PUBLIC) {
            require(round >= 0 && round <= 20, "Wrong round number");

            PublicSale memory p = publicSales[round];

            // is round active?
            require(
                p.saleStartTime <= blockTimeStamp &&
                    p.saleEndTime >= blockTimeStamp,
                "This round is not active for now"
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
                p.min <= CoinsPurchasedByUserInTheRound + requestedCoins &&
                    p.max >= CoinsPurchasedByUserInTheRound + requestedCoins,
                "Houston, There are minimum and maximum purchase limits"
            );

            // update privateSales Round purchased OXOs
            publicSales[round].totalSales =
                publicSales[round].totalSales +
                requestedCoins;

            coinPrice = p.price;
            unlockTime = p.unlockTime;

            // %80 for BuyBack - %20 Transferable
            _transferableByFoundation += (totalUSD * 20) / 100;
        }

        // Get User Purchases Count
        uint256 upCount = _UserPurchases[user].length;

        /// New Purchase Record
        _UserPurchases[user].push(
            Purchase({
                user: user,
                userPurchaseId: upCount,
                orderTime: blockTimeStamp,
                orderBlock: block.number,
                salesType: salesType,
                round: round,
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
        _userInfoByAddress[user].usdBalance =
            _userInfoByAddress[user].usdBalance -
            totalUSD;

        // Update user's OXOs count for round
        _CoinsPurchasedByUserInTheRound[user][salesType][round] =
            CoinsPurchasedByUserInTheRound +
            requestedCoins;

        // Mint Tokens
        _mintFromSales(user, requestedCoins);

        return true;
    }

    /** *********************** */
    function Test_RequestBuyBack(address user, uint256 userPurchaseId)
        public
        onlyOwner
        returns (bool)
    {
        return _RequestBuyBack(user, userPurchaseId);
    }

    /** *********************** */

    function RequestBuyBack(uint256 userPurchaseId) public returns (bool) {
        return _RequestBuyBack(msg.sender, userPurchaseId);
    }

    function _RequestBuyBack(address user, uint256 userPurchaseId)
        internal
        returns (bool)
    {
        require(
            _userInfoByAddress[user].buyBackGuarantee,
            "You dont have BuyBack guarantee!"
        );

        require(
            publicSales[20].unlockTime + 1 days < GetBlockTimeStamp() &&
                GetBlockTimeStamp() <= publicSales[20].unlockTime + 90 days,
            "BuyBack guarantee is not possible at this time!"
        );

        if (
            _UserPurchases[user][userPurchaseId].buyBack == false &&
            _UserPurchases[user][userPurchaseId].userPurchaseId ==
            userPurchaseId
        ) {
            uint256 totalBuyBackCoins = _UserPurchases[user][userPurchaseId]
                .totalCoin;

            // Calculate USD
            uint256 totalBuyBackUSD = (_UserPurchases[user][userPurchaseId]
                .totalUSD * 80) / 100;

            // BuyBackLogs for User
            _userBuyBacks[user].push(
                BuyBackLog({
                    user: user,
                    buyBackTime: GetBlockTimeStamp(),
                    orderTime: _UserPurchases[user][userPurchaseId].orderTime,
                    salesType: _UserPurchases[user][userPurchaseId].salesType,
                    round: _UserPurchases[user][userPurchaseId].round,
                    totalCoin: totalBuyBackCoins,
                    totalUSD: totalBuyBackUSD
                })
            );

            // Change BuyBack Status
            _UserPurchases[user][userPurchaseId].buyBack = true;

            // USD
            _userInfoByAddress[user]._userBuyBackUSD =
                _userInfoByAddress[user]._userBuyBackUSD +
                totalBuyBackUSD;

            // Added USD to UserBalance
            _userInfoByAddress[user].usdBalance =
                _userInfoByAddress[user].usdBalance +
                totalBuyBackUSD;

            // Change UserInfo - Remove coins from totalCoinsFromSales and add to totalBuyBackCoins
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

    function GetUserPurchases(address _user)
        public
        view
        returns (UserPurchaseSummary memory)
    {
        UserPurchaseSummary memory ups = UserPurchaseSummary(
            _user,
            _UserPurchases[_user]
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
            ValidPayToken[_payTokens[i].contractAddress] = true;
            payTokenIndex[_payTokens[i].contractAddress] = i;
        }
    }

    function _BlockTimeStamp() public view returns (uint256) {
        return block.timestamp;
    }

    uint256 FakeTimeStamp = 0;

    function Test_BlockTimeStamp(uint256 _fakeTimeStamp)
        public
        onlyOwner
        returns (bool)
    {
        FakeTimeStamp = _fakeTimeStamp;
        return true;
    }

    function GetBlockTimeStamp() public view returns (uint256) {
        if (FakeTimeStamp != 0) return FakeTimeStamp;
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

    function timestampToDate(uint256 timestamp)
        public
        pure
        returns (
            uint256 year,
            uint256 month,
            uint256 day
        )
    {
        (year, month, day) = BokkyPooBahsDateTimeLibrary.timestampToDate(
            timestamp
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

        privateSales.push(
            PrivateSale({
                price: 0.040 * 1e18,
                totalCoins: 4_800_000 * 1e18,
                min: 20_000 * 1e18,
                max: 500_000 * 1e18,
                saleStartTime: _startTime,
                saleEndTime: _startTime + 30 days - 1,
                unlockTime: _startTime + 30 days + 360 days,
                totalSales: 0
            })
        );
        privateSales.push(
            PrivateSale({
                price: 0.055 * 1e18,
                totalCoins: 4_800_000 * 1e18,
                min: 5_000 * 1e18,
                max: 350_000 * 1e18,
                saleStartTime: _startTime,
                saleEndTime: _startTime + 30 days - 1,
                unlockTime: _startTime + 30 days + 270 days,
                totalSales: 0
            })
        );
        privateSales.push(
            PrivateSale({
                price: 0.070 * 1e18,
                totalCoins: 4_800_000 * 1e18,
                min: 2_000 * 1e18,
                max: 400_000 * 1e18,
                saleStartTime: _startTime,
                saleEndTime: _startTime + 30 days - 1,
                unlockTime: _startTime + 30 days + 180 days,
                totalSales: 0
            })
        );
        AddedPrivateSales = true;
    }

    function _setUnlockTimes() internal returns (bool) {
        require(AddedPublicSales, "Houston!");
        uint256 Round20EndTime = publicSales[20].saleEndTime;

        // token unlocking can begin 120 days after public sales start
        // if (Round20EndTime - publicSales[0].saleStartTime < 120 days) {
        //     Round20EndTime = publicSales[0].saleStartTime + 120 days;
        // }

        for (uint8 i = 0; i <= 20; i++) {
            publicSales[i].unlockTime =
                Round20EndTime +
                1 +
                1 days +
                ((20 - i) * 1 days);
        }
        return true;
    }

    function _addPublicSaleDetails(
        uint256 year,
        uint256 month,
        uint256 day,
        uint256 hour,
        uint256 minute,
        uint256 round0Coins,
        uint256 round1Coins,
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

        if (round0Coins == 0) round0Coins = 13_600_000;
        if (round1Coins == 0) round1Coins = 7_500_000;
        if (coinReduction == 0) coinReduction = 200_000;

        publicSales.push(
            PublicSale({
                price: 0.10 * 1e18,
                totalCoins: round0Coins * 1e18,
                min: 500 * 1e18,
                max: 500_000 * 1e18,
                saleStartTime: _startTime,
                saleEndTime: _startTime + 14 days - 1,
                unlockTime: 0, //_startTime + 161 days,
                totalSales: 0
            })
        );

        for (uint256 i = 1; i <= 20; i++) {
            uint256 _totalCoins = (round1Coins - ((i - 1) * coinReduction)) *
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

            ////uint256 _price = pricesForRounds[i] * 1e16;
            // uint256 _days = 153;
            // _days = _days - ((i - 1) * 8);
            // _days = _days * 1 days;

            publicSales.push(
                PublicSale({
                    price: _price,
                    totalCoins: _totalCoins,
                    min: 100 * 1e18,
                    max: 500_000 * 1e18,
                    saleStartTime: _startTime + ((i + 1) * 7 days),
                    saleEndTime: _startTime + ((i + 1) * 7 days) + 7 days - 1,
                    unlockTime: 0,
                    totalSales: 0
                })
            );
        }

        AddedPublicSales = true;
        _setUnlockTimes();
    }

    function SetRoundEndTime(uint8 _round, uint256 _endTime) public onlyOwner {
        _setRoundEndTime(_round, _endTime);
    }

    function _setRoundEndTime(uint8 _round, uint256 _endTime)
        internal
        returns (bool)
    {
        require(_round >= 1 && _round <= 20, "Round is not valid");
        require(
            _endTime < publicSales[_round].saleEndTime &&
                _endTime > publicSales[_round].saleStartTime,
            "What are you doing?"
        );

        publicSales[_round].saleEndTime = _endTime;
        if (_round != 20) _setRoundTime(_round + 1);

        // Dont need to change unlock times :)
        //_setUnlockTimes();

        return true;
    }

    // Set round start and end time after round 2
    function _setRoundTime(uint8 _round) internal returns (bool) {
        require(_round >= 2 && _round <= 20, "Round is not valid");

        uint256 previousRoundStartTime = publicSales[_round - 1].saleStartTime;
        uint256 previousRoundEndTime = publicSales[_round - 1].saleEndTime;

        uint256 fixRoundTime = 7 days -
            (previousRoundEndTime - previousRoundStartTime);

        fixRoundTime -= 1 hours; // 1 hours break time :)

        for (uint8 i = _round; i <= 20; i++) {
            publicSales[i].saleStartTime =
                publicSales[i].saleStartTime -
                fixRoundTime;

            publicSales[i].saleEndTime =
                publicSales[i].saleEndTime -
                fixRoundTime;
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
        uint256 balance = balanceOf(msg.sender);
        require(amount <= balance, "Houston!");
        return super.transfer(to, amount);
    }

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) public override returns (bool) {
        uint256 balance = balanceOf(from);
        require(amount <= balance, "Houston!");
        return super.transferFrom(from, to, amount);
    }

    function balanceOf(address who) public view override returns (uint256) {
        uint256 lockedBalance = _lockedCoinsCheck(who);
        return super.balanceOf(who) - lockedBalance;
    }

    function allBalanceOf(address who) public view returns (uint256) {
        return super.balanceOf(who);
    }

    /** Calculate */
    function _lockedCoinsCheck(address _who) internal view returns (uint256) {
        uint256 blockTimeStamp = GetBlockTimeStamp();
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
        Purchase[] memory up = _UserPurchases[_who];
        uint256 LockedCoins = 0;
        for (uint256 i = 1; i < up.length; i++) {
            if (up[i].buyBack != true) {
                // if coins from Private Sales & unlock time has not pass
                if (
                    up[i].salesType == SalesType.PRIVATE &&
                    //x[i].unlockTime > blockTimeStamp
                    privateSales[up[i].round].unlockTime > blockTimeStamp
                ) {
                    LockedCoins += up[i].totalCoin;
                }

                // if coins from Public sales & unlock time has not pass
                if (
                    up[i].salesType == SalesType.PUBLIC &&
                    publicSales[up[i].round].unlockTime > blockTimeStamp
                ) {
                    LockedCoins += up[i].totalCoin;
                }

                if (
                    up[i].salesType == SalesType.PUBLIC &&
                    (blockTimeStamp > publicSales[up[i].round].unlockTime &&
                        blockTimeStamp <=
                        publicSales[up[i].round].unlockTime + 20 days)
                ) {
                    uint256 pastTime = blockTimeStamp -
                        publicSales[up[i].round].unlockTime;
                    uint256 pastDays = 0;

                    pastTime =
                        blockTimeStamp -
                        publicSales[up[i].round].unlockTime;

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
                        LockedCoins += (up[i].totalCoin * (20 - pastDays)) / 20;
                    }
                }
            }
        }

        return LockedCoins;
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal override whenNotPaused {
        require(balanceOf(from) >= amount, "Your balance is not enough!");
        super._beforeTokenTransfer(from, to, amount);
    }

    /** ONLYOWNER */
    function addEditPayToken(address _tokenAddress, string memory _name)
        external
        onlyOwner
        returns (bool)
    {
        //require(_decimals == 18, "Only 18 decimals stable USD tokens");

        IERC20 erc20Token = IERC20(address(_tokenAddress));
        require(
            erc20Token.decimals() == 18,
            "Only 18 decimals stable USD tokens accepted"
        );

        uint256 ptIndex = payTokenIndex[_tokenAddress];
        if (ptIndex == 0) {
            ValidPayToken[_tokenAddress] = true;
            _payTokens.push(
                payToken({name: _name, contractAddress: _tokenAddress})
            );
            ptIndex = _payTokens.length;
            payTokenIndex[_tokenAddress] = ptIndex;
            return true;
        } else {
            _payTokens[ptIndex] = payToken({
                name: _name,
                contractAddress: _tokenAddress
            });
        }
        return false;
    }

    function TransferTokensToGnosis(address _tokenAddress) external onlyOwner {
        IERC20 erc20Token = IERC20(address(_tokenAddress));
        uint256 tokenBalance = erc20Token.balanceOf(address(this));
        uint256 transferable = tokenBalance;
        if (ValidPayToken[_tokenAddress]) {
            transferable =
                _transferableByFoundation -
                _totalTranferredToFoundation;

            // After BuyBack
            if (publicSales[20].unlockTime + 90 days < GetBlockTimeStamp()) {
                transferable = tokenBalance;
            }

            if (tokenBalance < transferable) transferable = tokenBalance;
            _totalTranferredToFoundation += transferable;
        }
        erc20Token.transfer(_GNOSIS_SAFE_WALLET, transferable);
    }

    function TransferCoinsToGnosis() external onlyOwner {
        uint256 _balance = address(this).balance;
        //if (_balance >= _amount) {
        payable(_GNOSIS_SAFE_WALLET).transfer(_balance);
        //}
    }

    function unlockEveryone() external onlyOwner {
        _unlockAll = true;
    }

    /** *************** */
    function Test_DepositMoney(
        address _user,
        uint256 _amount,
        address _tokenAddress
    ) public onlyOwner {
        _DepositUSD(_user, _amount, _tokenAddress);
    }

    /** *************** */

    /** Deposit Money */
    function DepositMoney(uint256 _amount, address _tokenAddress) external {
        // require(_canBeDeposited, "You can not deposit");
        require(
            ValidPayToken[_tokenAddress],
            "We do not accept this ERC20 token!"
        );

        IERC20 erc20Token = IERC20(address(_tokenAddress));

        // Firstly checking user approve result
        require(
            erc20Token.allowance(msg.sender, address(this)) >= _amount,
            "Houston, You do not approve this amount for transfer to us"
        );
        // Check user's payToken balance
        uint256 tokenBalance = erc20Token.balanceOf(msg.sender);

        require(tokenBalance >= _amount, "You can not deposit");

        // get/create user record

        // Transfer payToken to US
        erc20Token.transferFrom(msg.sender, address(this), _amount);

        _DepositUSD(msg.sender, _amount, _tokenAddress);
    }

    function _DepositUSD(
        address _user,
        uint256 _amount,
        address _tokenAddress
    ) internal {
        _getUserIndex(_user);
        _totalDepositAmount += _amount; //  All USD token Deposits
        _DepositsAsPayToken[_tokenAddress] += _amount; // Deposits as PayToken
        _UserDeposits[_user] += _amount; // User Deposits
        _UserDepositsAsToken[_user][_tokenAddress] += _amount; // User Deposits as PayToken
        _userInfoByAddress[_user].usdBalance += _amount; // User USD Balance

        _DepositsByUser[_user].push(
            Deposit({
                user: _user,
                payToken: _tokenAddress,
                amount: _amount,
                timestamp: GetBlockTimeStamp()
            })
        );

        _Deposits.push(
            Deposit({
                user: _user,
                payToken: _tokenAddress,
                amount: _amount,
                timestamp: GetBlockTimeStamp()
            })
        );

        emit DepositUSD(msg.sender, _amount, _tokenAddress);
    }

    /** ******************** */
    function Test_WithdrawMoney(address _user, uint256 _amount)
        public
        returns (bool)
    {
        return _withdrawMoney(_user, _amount);
    }

    /** ******************** */

    function WithdrawMoney(uint256 _amount) public returns (bool) {
        return _withdrawMoney(msg.sender, _amount);
    }

    function _withdrawMoney(address _user, uint256 _amount)
        internal
        returns (bool)
    {
        require(
            _userInfoByAddress[_user].usdBalance >= _amount,
            "You can not withdraw!"
        );
        bool transfered = false;
        for (uint256 i = 0; i < _payTokens.length; i++) {
            if (!transfered) {
                IERC20 erc20Token = IERC20(
                    address(_payTokens[i].contractAddress)
                );
                uint256 tokenBalance = erc20Token.balanceOf(address(this));
                if (tokenBalance >= _amount) {
                    _userInfoByAddress[_user].usdBalance =
                        _userInfoByAddress[_user].usdBalance -
                        _amount;
                    _userWithdraws[_user].push(
                        Withdraw({
                            user: _user,
                            withdrawTime: GetBlockTimeStamp(),
                            payToken: _payTokens[i].contractAddress,
                            amount: _amount
                        })
                    );

                    _Withdraws.push(
                        Withdraw({
                            user: _user,
                            withdrawTime: GetBlockTimeStamp(),
                            payToken: _payTokens[i].contractAddress,
                            amount: _amount
                        })
                    );

                    erc20Token.transfer(_user, _amount);
                    transfered = true;
                    break;
                }
            }
        }

        return true;
    }

    function _getUserIndex(address _user) internal returns (uint256) {
        uint256 uIndex = _userIndex[_user];
        if (uIndex == 0) {
            allUsers.push(_user);
            uIndex = allUsers.length;
            _userIndex[_user] = uIndex;
            _userInfoByAddress[_user].user = _user;
            _userInfoByAddress[_user].buyBackGuarantee = true;
            _UserPurchases[_user].push();
        }
        return uIndex;
    }
}
