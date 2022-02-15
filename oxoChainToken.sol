// SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;

import "./ERC20.sol";
import "./ERC20Burnable.sol";
import "./Pausable.sol";
import "./Ownable.sol";
import "./DateTimeLibrary.sol";

/// @custom:security-contact info@oxochain.com
contract OXOChainToken is ERC20, ERC20Burnable, Pausable, Ownable {
    using BokkyPooBahsDateTimeLibrary for uint256;

    address public constant _GNOSIS_SAFE_WALLET =
        0x3edF93dc2e32fD796c108118f73fa2ae585C66B6;

    uint256 public _transferableByFoundation;
    uint256 public _totalSales;
    uint256 public _totalTranferredToFoundation;

    bool public _unlockAll = false;
    // bool public _canBeDeposited = true;

    struct Deposit {
        address user;
        address payToken;
        uint256 amount;
        uint256 timestamp;
    }

    Deposit[] public _allDeposits;

    address[] public allUsers;

    mapping(address => uint256) public _userIndex;

    struct UserInfo {
        address user;
        bool buyBackGuarantee;
        uint256 totalCoinsFromSales;
        //uint256 privateSalesUnlockTime;
        //uint256 PublicSalesUnlockTime;
    }

    //mapping(uint256 => UserInfo) public _userInfoByIndex;
    mapping(address => UserInfo) public _userInfoByAddress;

    uint256 public _totalDeposits;

    mapping(address => uint256) public _totalOfUserDeposits;

    mapping(address => mapping(address => uint256))
        public _totalOfUserDepositsPerPayToken;

    mapping(address => uint256) public _totalOfPayTokenDeposits;

    mapping(address => bool) public acceptedPayTokens;

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
        uint256 orderTime;
        SalesType salesType;
        uint8 round;
        uint256 coinPrice;
        uint256 totalCoin;
        uint256 totalUSD;
        bool canBuyBack;
        uint256 unlockTime;
    }

    struct UserPurchaseSummary {
        address user;
        Purchase[] user_sales;
    }

    mapping(address => uint256) public _userUsdBalance;

    mapping(address => Purchase[]) _UserPurchases;

    mapping(address => Deposit[]) _UserDeposits;

    mapping(address => mapping(SalesType => mapping(uint256 => uint256)))
        public _userPurchasedCoinsPerRound;

    event DepositUSD(address, uint256, address);

    /** CONSTRUCTOR */

    constructor() ERC20("OXO Chain - Wrapped", "wOXO") {
        _initPayTokens();
    }

    /** **************************** */
    function Fake_PurchaseFromSales(
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
        require(_totalOfUserDeposits[user] != 0, "You did not deposit");

        require(totalUSD > 0, "Funny, you dont have balance for purchases!");

        require(
            _userUsdBalance[user] >= totalUSD,
            "Hoop, you dont have that USD!"
        );

        uint256 blockTimeStamp = GetBlockTimeStamp();
        uint256 requestedCoins = 0;
        uint256 coinPrice = 0;
        uint256 unlockTime = 0;
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
            requestedCoins = ((totalUSD * 1e2) / p.price) * 1e16;
            totalUSD = (requestedCoins * p.price) / 1e18;
            // is there enough OXOs?
            require(
                p.totalCoins - p.totalSales >= requestedCoins,
                "You request more coins than buyable"
            );

            // check user's purchases for min/max limits
            require(
                p.min <=
                    _userPurchasedCoinsPerRound[user][salesType][round] +
                        requestedCoins &&
                    p.max >=
                    _userPurchasedCoinsPerRound[user][salesType][round] +
                        requestedCoins,
                "Houston, There are minimum and maximum purchase limits"
            );

            // update privateSales Round purchased OXOs
            privateSales[round].totalSales =
                privateSales[round].totalSales +
                requestedCoins;

            coinPrice = p.price;
            unlockTime = p.unlockTime;

            //  Private Sales Unlock Time
            // if (_userInfoByAddress[user].privateSalesUnlockTime < unlockTime) {
            //     _userInfoByAddress[user].privateSalesUnlockTime = unlockTime;
            // }

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
            requestedCoins = ((totalUSD * 1e2) / p.price) * 1e16;
            totalUSD = (requestedCoins * p.price) / 1e18;

            // is there enough OXOs?
            require(
                p.totalCoins - p.totalSales >= requestedCoins,
                "You request more coins than buyable"
            );

            // check user's purchases for min/max limits
            require(
                p.min <=
                    _userPurchasedCoinsPerRound[user][salesType][round] +
                        requestedCoins &&
                    p.max >=
                    _userPurchasedCoinsPerRound[user][salesType][round] +
                        requestedCoins,
                "Houston, There are minimum and maximum purchase limits"
            );

            // update privateSales Round purchased OXOs
            publicSales[round].totalSales =
                publicSales[round].totalSales +
                requestedCoins;

            coinPrice = p.price;
            unlockTime = p.unlockTime;
            // if (_userInfoByAddress[user].publicSalesUnlockTime < unlockTime) {
            //     _userInfoByAddress[user].publicSalesUnlockTime = unlockTime;
            // }

            _transferableByFoundation += (totalUSD * 200000) / 1000000;
        }

        /// New Purchase Record
        _UserPurchases[user].push(
            Purchase({
                user: user,
                orderTime: blockTimeStamp,
                salesType: salesType,
                round: round,
                coinPrice: coinPrice,
                totalCoin: requestedCoins,
                totalUSD: totalUSD,
                canBuyBack: true,
                unlockTime: unlockTime
            })
        );

        _totalSales += totalUSD;

        _userInfoByAddress[user].totalCoinsFromSales =
            _userInfoByAddress[user].totalCoinsFromSales +
            requestedCoins;

        // UserBalance change
        _userUsdBalance[user] = _userUsdBalance[user] - totalUSD;

        // Update user's OXOs count for round
        _userPurchasedCoinsPerRound[user][salesType][round] =
            _userPurchasedCoinsPerRound[user][salesType][round] +
            requestedCoins;

        // Mint Tokens
        _mint(user, requestedCoins, false);

        return true;
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

        //for (uint256 i = 0; i < u.user_sales.length; i++) {}

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
            acceptedPayTokens[_payTokens[i].contractAddress] = true;
            payTokenIndex[_payTokens[i].contractAddress] = i;
        }
    }

    function _getRealBlockTime() public view returns (uint256) {
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

    uint256 FakeTimeStamp = 0;

    function Fake_BlockTimeStamp(uint256 _fakeTimeStamp)
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

        // token unlocking can begin 90 days after public sales start
        if (Round20EndTime - publicSales[0].saleStartTime < 120 days) {
            Round20EndTime = publicSales[0].saleStartTime + 120 days;
        }

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
        uint256 downCoins
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
        if (downCoins == 0) downCoins = 200_000;

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
            uint256 _totalCoins = (round1Coins - ((i - 1) * downCoins)) * 1e18;
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

    function _setRoundEndTime(uint8 _round, uint256 _endTime)
        public
        onlyOwner
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

        _setUnlockTimes();

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
        _mint(to, amount, true);
    }

    function balanceOf(address who) public view override returns (uint256) {
        uint256 lockedBalance = _lockedBalance(who);
        return super.balanceOf(who) - lockedBalance;
    }

    function allBalanceOf(address who) public view returns (uint256) {
        return super.balanceOf(who);
    }

    /** Calculate */
    function _lockedBalance(address _who) internal view returns (uint256) {
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

        /// All coins locked for everyone
        if (privateSales[0].unlockTime + 1 days > blockTimeStamp) {
            return _userInfoByAddress[_who].totalCoinsFromSales;
        }

        /// All coins can transferable, There is no lock for user
        // if (
        //     _userInfoByIndex[uIndex].privateSalesUnlockTime < blockTimeStamp &&
        //     publicSales[20].unlockTime + 21 days < blockTimeStamp
        // ) {
        //     return 0;
        // }

        // Check all purchase history
        Purchase[] memory x = _UserPurchases[_who];
        uint256 LockedCoins = 0;
        for (uint256 i = 0; i < x.length; i++) {
            // if coins from Private Sales & unlock time has not pass
            if (
                x[i].salesType == SalesType.PRIVATE &&
                //x[i].unlockTime > blockTimeStamp
                privateSales[x[i].round].unlockTime > blockTimeStamp
            ) {
                LockedCoins += x[i].totalCoin;
            }

            // if coins from Public sales & unlock time has not pass
            if (
                x[i].salesType == SalesType.PUBLIC &&
                publicSales[x[i].round].unlockTime > blockTimeStamp
            ) {
                LockedCoins += x[i].totalCoin;
            }

            // if coins purchase from Public sales - vesting period

            // unlocktime: 1663891220 (+21 days: 1663891220) - Timestamp: 1664082300
            //  unlocktime < timestamp <= +21 days
            // 1663891220 < 1664082300 <= 1663891220 ?? true
            // pastTime = 1664082300 - 1663891220  = 191080
            // pastDays = (191080 - ( 191080 % 86400)) / 86400 = (191080 - 18280) / 86400 = 172800 / 86400 =  2 days
            // LockedCoins = (100000 * (20-2)) / 20 =  90000
            // UnlockedCoins = 100000-90000 = 10000
            if (
                x[i].salesType == SalesType.PUBLIC &&
                (publicSales[x[i].round].unlockTime > blockTimeStamp &&
                    publicSales[x[i].round].unlockTime + 21 days <=
                    blockTimeStamp)
            ) {
                uint256 pastTime = blockTimeStamp -
                    publicSales[x[i].round].unlockTime;
                uint256 pastDays = (pastTime - (pastTime % 1 days)) / 1 days;
                if (pastDays <= 1 && pastDays >= 20) {
                    LockedCoins += (x[i].totalCoin * (20 - pastDays)) / 20;
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

        ERC20 erc20Token = ERC20(address(_tokenAddress));
        require(
            erc20Token.decimals() == 18,
            "Only 18 decimals stable USD tokens accepted"
        );

        uint256 ptIndex = payTokenIndex[_tokenAddress];
        if (ptIndex == 0) {
            acceptedPayTokens[_tokenAddress] = true;
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

        if (publicSales[20].unlockTime + 90 days < GetBlockTimeStamp()) {
            _transferableByFoundation =
                _totalSales -
                _totalTranferredToFoundation;
        }

        uint256 transferable = _transferableByFoundation -
            _totalTranferredToFoundation;
        if (tokenBalance < transferable) transferable = tokenBalance;
        erc20Token.transfer(_GNOSIS_SAFE_WALLET, transferable);
        _totalTranferredToFoundation += transferable;
    }

    function TransferCoinsToGnosis(uint256 _amount) external onlyOwner {
        uint256 _balance = address(this).balance;
        if (_balance >= _amount) {
            payable(_GNOSIS_SAFE_WALLET).transfer(_amount);
        }
    }

    function unlockEveryone() external onlyOwner {
        _unlockAll = true;
    }

    /** *************** */
    function Fake_DepositMoney(
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
            acceptedPayTokens[_tokenAddress],
            "We do not accept this ERC20 token!"
        );

        ERC20 erc20Token = ERC20(address(_tokenAddress));

        // Firstly checking user approve result
        require(
            erc20Token.allowance(msg.sender, address(this)) >= _amount,
            "Houston, You do not approve this amount for transfer to us"
        );
        // Check user's payToken balance
        uint256 tokenBalance = erc20Token.balanceOf(msg.sender);

        require(tokenBalance >= _amount, "You can not deposit");

        // get/create user record
        _getUserIndex(msg.sender);

        // Transfer payToken to US
        erc20Token.transferFrom(msg.sender, address(this), _amount);

        _DepositUSD(msg.sender, _amount, _tokenAddress);
    }

    function _DepositUSD(
        address _user,
        uint256 _amount,
        address _tokenAddress
    ) internal {
        //uint256 uIndex = _getUserIndex(_user);
        // add amount to User USD Balance in SC
        _totalDeposits += _amount; // Total Deposits
        _totalOfPayTokenDeposits[_tokenAddress] += _amount; // Total PayToken Deposits by Type

        _totalOfUserDeposits[_user] += _amount; // The total of all deposits of the user
        _totalOfUserDepositsPerPayToken[_user][_tokenAddress] += _amount; // User's PayToken Deposits by Type
        _userUsdBalance[_user] += _amount;

        _UserDeposits[_user].push(
            Deposit({
                user: _user,
                payToken: _tokenAddress,
                amount: _amount,
                timestamp: GetBlockTimeStamp()
            })
        );

        _allDeposits.push(
            Deposit({
                user: _user,
                payToken: _tokenAddress,
                amount: _amount,
                timestamp: GetBlockTimeStamp()
            })
        );

        emit DepositUSD(msg.sender, _amount, _tokenAddress);
    }

    function _getUserIndex(address _user) internal returns (uint256) {
        uint256 uIndex = _userIndex[_user];
        if (uIndex == 0) {
            allUsers.push(_user);
            uIndex = allUsers.length;
            _userIndex[_user] = uIndex;
            _userInfoByAddress[_user].user = _user;
            _userInfoByAddress[_user].buyBackGuarantee = true;
        }
        return uIndex;
    }
}
