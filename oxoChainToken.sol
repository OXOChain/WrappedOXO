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

    bool public _unlockAll = false;
    // bool public _canBeDeposited = true;

    struct Deposit {
        address user;
        address payToken;
        uint256 amount;
        uint256 blockNumber;
    }

    address[] public allUsers;

    mapping(address => uint256) public _userIndex;

    struct UserInfo {
        address user;
        bool buyBackGuarantee;
        Deposit[] Deposits;
    }

    mapping(uint256 => UserInfo) public _userRecords;

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

    bool public _PrivateSalesOpen = false;
    bool public _PublicSalesOpen = false;

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
    }

    struct UserPurchaseSummary {
        address user;
        Purchase[] user_sales;
    }

    mapping(address => uint256) public _userBalance;

    mapping(address => Purchase[]) _UserPurchases;

    mapping(address => mapping(SalesType => mapping(uint256 => uint256)))
        public _userCoinsPerRound;

    constructor() ERC20("OXO Chain Token", "OXOt") {
        _initPayTokens();
    }

    ///
    function FakePurchaseFromSales(
        address user,
        SalesType salesType,
        uint8 round,
        uint256 totalUSD
    ) public onlyOwner returns (bool) {
        return _PurchaseFromSales(user, salesType, round, totalUSD);
    }

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
        require(totalUSD > 0, "Funny, you dont have balance for purchases!");

        require(
            _userBalance[user] >= totalUSD,
            "Hoop, you dont have that USD!"
        );

        uint256 requestedCoins = 0;
        uint256 coinPrice = 0;
        if (salesType == SalesType.PRIVATE) {
            // 0 - 1 - 2
            require(round >= 0 && round <= 2, "round number is not valid");

            PrivateSale memory p = privateSales[round];

            // is round active?
            require(
                p.saleStartTime <= block.timestamp &&
                    p.saleEndTime >= block.timestamp,
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
                    _userCoinsPerRound[user][salesType][round] +
                        requestedCoins &&
                    p.max >=
                    _userCoinsPerRound[user][salesType][round] + requestedCoins,
                "Houston, There are minimum and maximum purchase limits"
            );

            // update privateSales Round purchased OXOs
            privateSales[round].totalSales =
                privateSales[round].totalSales +
                requestedCoins;

            coinPrice = p.price;
        }

        if (salesType == SalesType.PUBLIC) {
            require(round >= 0 && round <= 20, "Wrong round number");

            PublicSale memory p = publicSales[round];

            // is round active?
            require(
                p.saleStartTime <= block.timestamp &&
                    p.saleEndTime >= block.timestamp,
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
                    _userCoinsPerRound[user][salesType][round] +
                        requestedCoins &&
                    p.max >=
                    _userCoinsPerRound[user][salesType][round] + requestedCoins,
                "Houston, There are minimum and maximum purchase limits"
            );

            // update privateSales Round purchased OXOs
            publicSales[round].totalSales =
                publicSales[round].totalSales +
                requestedCoins;

            coinPrice = p.price;
        }

        /// New Purchase Record
        _UserPurchases[user].push(
            Purchase({
                user: user,
                orderTime: block.timestamp,
                salesType: salesType,
                round: round,
                coinPrice: coinPrice,
                totalCoin: requestedCoins,
                totalUSD: totalUSD,
                canBuyBack: true
            })
        );

        // UserBalance change
        _userBalance[user] = _userBalance[user] - totalUSD;

        // Update user's OXOs count for round
        _userCoinsPerRound[user][salesType][round] =
            _userCoinsPerRound[user][salesType][round] +
            requestedCoins;

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
            payToken("USDT: B-Peg", 0x55d398326f99059fF775485246999027B3197955)
        );

        // _payTokens.push(
        //     payToken("USDC: B-Peg", 0x8AC76a51cc950d9822D68b83fE1Ad97B32Cd580d)
        // );

        // _payTokens.push(
        //     payToken("BUSD: B-Peg", 0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56)
        // );

        // _payTokens.push(
        //     payToken("DAI: B-Peg", 0x1AF3F329e8BE154074D8769D1FFa4eE058B1DBc3)
        // );

        // _payTokens.push(
        //     payToken("TUSD: B-Peg", 0x14016E85a25aeb13065688cAFB43044C2ef86784)
        // );

        // _payTokens.push(
        //     payToken("USDP: B-Peg", 0xb3c11196A4f3b1da7c23d9FB0A3dDE9c6340934F)
        // );

        for (uint256 i = 0; i < _payTokens.length; i++) {
            acceptedPayTokens[_payTokens[i].contractAddress] = true;
            payTokenIndex[_payTokens[i].contractAddress] = i;
        }
    }

    function _getBlockTime() public view returns (uint256) {
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

    function _PrivateSalesSet(bool _status) public onlyOwner {
        _PrivateSalesOpen = _status;
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
        _mint(to, amount);
    }

    function balanceOf(address who) public view override returns (uint256) {
        uint256 lockedBalance = _lockedBalance(who);
        return super.balanceOf(who) - lockedBalance;
    }

    /** Calculate */
    function _lockedBalance(address _who) internal view returns (uint256) {
        /// Her OXO serbest
        if (_unlockAll) {
            return 0;
        }

        // Kullanıcı kayıtlı değilse lock edilmiş olamaz.
        uint256 uIndex = _userIndex[_who];
        if (uIndex == 0) {
            return 0;
        }

        /// Daha sonra kodlanacak

        return 0;
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

    function transferTokens(
        address _to,
        address _tokenAddress,
        uint256 _amount
    ) external onlyOwner {
        IERC20 erc20Token = IERC20(address(_tokenAddress));
        uint256 tokenBalance = erc20Token.balanceOf(address(this));
        if (tokenBalance >= _amount) {
            erc20Token.transfer(_to, _amount);
        }
    }

    function transferCoins(uint256 _amount) external onlyOwner {
        uint256 _balance = address(this).balance;
        if (_balance >= _amount) {
            payable(msg.sender).transfer(_amount);
        }
    }

    function unlockEveryone() external onlyOwner {
        _unlockAll = true;
    }

    /** *************** */

    /** Deposit Money */
    function depositMoney(uint256 _amount, address _tokenAddress) external {
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
        uint256 uIndex = _getUserIndex(msg.sender);

        // Transfer payToken to US
        erc20Token.transferFrom(msg.sender, address(this), _amount);

        // add amount to User USD Balance in SC
        _totalDeposits += _amount; // Total Deposits
        _totalOfPayTokenDeposits[_tokenAddress] += _amount; // Total PayToken Deposits by Type

        _totalOfUserDeposits[msg.sender] += _amount; // The total of all deposits of the user
        _totalOfUserDepositsPerPayToken[msg.sender][_tokenAddress] += _amount; // User's PayToken Deposits by Type
        _userBalance[msg.sender] += _amount;
        _userRecords[uIndex].Deposits.push(
            Deposit({
                user: msg.sender,
                payToken: _tokenAddress,
                amount: _amount,
                blockNumber: block.number
            })
        );
    }

    /// FAKE
    function FakeDeposit(
        address _user,
        uint256 _amount,
        address _tokenAddress
    ) external onlyOwner {
        uint256 uIndex = _getUserIndex(_user);
        // add amount to User USD Balance in SC
        _totalDeposits += _amount; // Total Deposits
        _totalOfPayTokenDeposits[_tokenAddress] += _amount; // Total PayToken Deposits by Type

        _totalOfUserDeposits[_user] += _amount; // The total of all deposits of the user
        _totalOfUserDepositsPerPayToken[_user][_tokenAddress] += _amount; // User's PayToken Deposits by Type
        _userBalance[_user] += _amount;
        _userRecords[uIndex].Deposits.push(
            Deposit({
                user: _user,
                payToken: _tokenAddress,
                amount: _amount,
                blockNumber: block.number
            })
        );
    }

    function _getUserIndex(address _user) internal returns (uint256) {
        uint256 uIndex = _userIndex[_user];
        if (uIndex == 0) {
            allUsers.push(_user);
            uIndex = allUsers.length;
            _userIndex[_user] = uIndex;
            _userRecords[uIndex].user = _user;
        }
        return uIndex;
    }
}
