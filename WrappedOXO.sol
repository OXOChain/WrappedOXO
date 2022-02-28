// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;
import "./ERC20.sol";
import "./ERC20Burnable.sol";
import "./Pausable.sol";
import "./Ownable.sol";
import "./DateTimeLibrary.sol";
import "./ITrustedPayToken.sol";

contract WrappedOXO is ERC20, ERC20Burnable, Pausable, Ownable {
    struct TransferOxo {
        address user;
        uint256 amount;
        uint256 nonce;
    }

    TransferOxo[] public TransferToOxoChain;
    uint256 public TransferToOxoChainLatest = 0;

    using DateTimeLibrary for uint256;
    uint256 public _version = 3;
    address private constant SAFE_WALLET =
        0x3edF93dc2e32fD796c108118f73fa2ae585C66B6;

    bool private _unlockAll = false;

    uint256 private _transferableByFoundation;
    uint256 private _totalSales;
    uint256 private _totalTranferredToFoundation;

    mapping(address => bool) private contractManagers;
    // User Info

    struct UserInfo {
        address user;
        bool buyBackGuarantee;
        //bool buyInPreSale;
        uint256 totalCoinsFromSales;
        uint256 totalBuyBackCoins;
        uint256 totalBuyBackUSD;
        uint256 balanceUSD;
        uint256 totalDeposits;
        uint256 totalPurchases;
        uint256 totalWithdrawns;
    }

    address[] private allUsers;

    mapping(address => uint256) private _userIndex;

    mapping(address => UserInfo) private _userInfoByAddress;

    struct Deposit {
        address user;
        address payToken;
        uint256 amount;
        uint256 timestamp;
    }

    mapping(address => Deposit[]) private _userDeposits;

    // Total Deposit Amount
    uint256 private _totalDepositAmount;

    // PayTokens
    struct PayToken {
        string name;
        address contractAddress;
        uint256 totalDeposit;
        uint256 totalWithdrawn;
        bool valid;
    }

    PayToken[] public _payTokens;

    mapping(address => uint256) private _payTokenIndex;

    // Sales Information
    struct PreSale {
        uint256 price;
        uint256 totalCoins;
        uint256 min;
        uint256 max;
        uint256 saleStartTime;
        uint256 saleEndTime;
        uint256 unlockTime;
        uint256 totalSales;
    }

    PreSale[] public preSales;

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

    bool private addedPreSales;
    bool private addedPublicSales;

    enum SalesType {
        PRESALE,
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

    mapping(address => Purchase[]) private _userPurchases;

    mapping(address => mapping(SalesType => mapping(uint256 => uint256)))
        public _purchasedAtThisStage;

    struct UserSummary {
        address user;
        Deposit[] userDeposits;
        Purchase[] userPurchases;
        BuyBack[] userBuyBacks;
        Withdrawn[] userWithdrawns;
    }

    // struct StageSummary {
    //     SalesType salesType;
    //     uint256 stage;
    //     uint256 totalPurchasedCoins;
    //     uint256 canBuyMaxUSD;
    // }

    // StageSummary[] private stageSummaries;

    // struct StageSummariesForUser {
    //     address user;
    //     StageSummary[] stageSummaries;
    // }

    // Buy Back Records
    struct BuyBack {
        address user;
        uint256 buyBackTime;
        uint256 orderTime;
        SalesType salesType;
        uint8 stage;
        uint256 totalCoin;
        uint256 totalUSD;
    }

    mapping(address => BuyBack[]) private _userBuyBacks;

    // Withdrawns
    struct Withdrawn {
        address user;
        uint256 withdrawnTime;
        address payToken;
        uint256 amount;
    }

    mapping(address => Withdrawn[]) private _userWithdrawns;

    // Events
    event DepositUSD(address, uint256, address);
    event WithdrawnUSD(address, uint256, address);
    event Purchased(address, SalesType, uint8, uint256, uint256);

    constructor() {
        //_initPayTokens();
        _payTokens.push();
        contractManagers[msg.sender] = true;
    }

    modifier onlyContractManagers() {
        require(contractManagers[msg.sender], "You are not manager!");
        _;
    }

    function setManager(address managerAddress, bool status)
        public
        onlyOwner
        returns (bool)
    {
        require(managerAddress != msg.sender, "You can not do this!");
        contractManagers[managerAddress] = status;
        return true;
    }

    function getUserInfo(address _user, string memory _password)
        public
        view
        PassworRequired(_password)
        returns (UserInfo memory)
    {
        return _userInfoByAddress[_user];
    }

    struct ActiveStageSummary {
        uint256 timestamp;
        bool preSale;
        bool publicSale;
        uint256 totalCoins;
        uint256 totalSales;
    }

    function getActiveStageSummary()
        public
        view
        returns (ActiveStageSummary memory)
    {
        bool _preSale = false;
        bool _publicSale = false;
        uint256 _stage = 0;
        uint256 _totalCoinsInSale = 0;
        uint256 _totalSalesInSale = 0;

        if (
            preSales[0].saleStartTime <= getBlockTimeStamp() &&
            getBlockTimeStamp() <= preSales[2].saleEndTime
        ) {
            _preSale = true;
            for (uint256 i = 0; i <= 2; i++) {
                _totalCoinsInSale += preSales[i].totalCoins;
                _totalSalesInSale += preSales[i].totalSales;
            }
        }

        if (
            publicSales[0].saleStartTime <= getBlockTimeStamp() &&
            getBlockTimeStamp() <= publicSales[20].saleEndTime
        ) {
            _publicSale = true;
            for (uint256 i = 0; i <= 20; i++) {
                if (
                    publicSales[i].saleStartTime <= getBlockTimeStamp() &&
                    getBlockTimeStamp() <= publicSales[i].saleEndTime
                ) {
                    _stage = i;
                }
                _totalCoinsInSale += publicSales[i].totalCoins;
                _totalSalesInSale += publicSales[i].totalSales;
            }
        }

        ActiveStageSummary memory ass = ActiveStageSummary({
            timestamp: getBlockTimeStamp(),
            preSale: _preSale,
            publicSale: _publicSale,
            totalCoins: _totalCoinsInSale,
            totalSales: _totalSalesInSale
        });

        return ass;
    }

    // function getUserStageSummary(address user, SalesType salesType)
    //     public
    //     view
    //     returns (StageSummariesForUser memory)
    // {
    //     uint256 maxStage = 3;
    //     if (salesType == SalesType.PUBLIC) maxStage = 21;

    //     StageSummary[] memory summaries = new StageSummary[](maxStage);

    //     for (uint256 i = 0; i < maxStage; i++) {
    //         //uint256 purchasedUSD = 0;
    //         uint256 canBuyMaxUSD = 0;
    //         uint256 price = preSales[i].price;
    //         uint256 totalCoins = preSales[i].totalCoins;
    //         uint256 totalSales = preSales[i].totalSales;
    //         uint256 max = preSales[i].max;

    //         if (salesType == SalesType.PUBLIC) {
    //             price = publicSales[i].price;
    //             totalCoins = publicSales[i].totalCoins;
    //             totalSales = publicSales[i].totalSales;
    //             max = publicSales[i].max;
    //         }

    //         if (totalCoins - totalSales < max) {
    //             max = totalCoins - totalSales;
    //         }
    //         canBuyMaxUSD = ((max * price) / 1e18);

    //         if (_userInfoByAddress[user].balanceUSD <= canBuyMaxUSD) {
    //             canBuyMaxUSD = _userInfoByAddress[user].balanceUSD;
    //         }

    //         summaries[i] = StageSummary(
    //             salesType,
    //             i,
    //             _purchasedAtThisStage[user][salesType][i],
    //             canBuyMaxUSD
    //         );
    //     }

    //     StageSummariesForUser memory ss = StageSummariesForUser({
    //         user: user,
    //         stageSummaries: summaries
    //     });

    //     return ss;
    // }

    function buyCoins(
        SalesType salesType,
        uint8 stage,
        uint256 totalUSD
    ) public returns (bool) {
        require(_userInfoByAddress[msg.sender].totalDeposits != 0, "Deposit");

        // The same wallet address can not purchase more than 20 times.
        require(_userPurchases[msg.sender].length <= 20, "Next wallet please!");

        require(totalUSD > 0, "Airdrop?");

        require(
            _userInfoByAddress[msg.sender].balanceUSD >= totalUSD,
            "Balance Problem!"
        );

        uint256 blockTimeStamp = getBlockTimeStamp();
        uint256 requestedCoins = 0;
        uint256 coinPrice = 0;
        uint256 unlockTime = 0;
        uint256 purchasedAtThisStage = _purchasedAtThisStage[msg.sender][
            salesType
        ][stage];

        if (salesType == SalesType.PRESALE) {
            // 0 - 1 - 2
            require(stage >= 0 && stage <= 2, "wrong stage");

            PreSale memory pss = preSales[stage];

            // is stage active?
            require(
                pss.saleStartTime <= blockTimeStamp &&
                    pss.saleEndTime >= blockTimeStamp,
                "stage is not active"
            );

            // calculate OXOs for that USD
            // requestedCoins = ((totalUSD * 1e4) / p.price) * 1e14;
            requestedCoins = ((totalUSD) / pss.price) * 1e18;

            totalUSD = (requestedCoins * pss.price) / 1e18;
            // is there enough OXOs?
            require(
                pss.totalCoins - pss.totalSales >= requestedCoins,
                "Not enough coins"
            );

            // check user's purchases for min/max limits
            require(
                pss.min <= purchasedAtThisStage + requestedCoins &&
                    pss.max >= purchasedAtThisStage + requestedCoins,
                "There are limits"
            );

            // update preSales Stage purchased OXOs
            preSales[stage].totalSales =
                preSales[stage].totalSales +
                requestedCoins;

            coinPrice = pss.price;
            unlockTime = pss.unlockTime;

            _transferableByFoundation += totalUSD;

            // Buy in presale
            //_userInfoByAddress[msg.sender].buyInPreSale = true;
        }

        if (salesType == SalesType.PUBLIC) {
            require(stage >= 0 && stage <= 20, "Wrong stage");

            PublicSale memory pss = publicSales[stage];

            // is stage active?
            require(
                pss.saleStartTime <= blockTimeStamp &&
                    pss.saleEndTime >= blockTimeStamp,
                "stage is not active"
            );

            // calculate OXOs for that USD
            //requestedCoins = ((totalUSD * 1e2) / p.price) * 1e16;
            requestedCoins = ((totalUSD) / pss.price) * 1e18;
            totalUSD = (requestedCoins * pss.price) / 1e18;

            // is there enough OXOs?
            require(
                pss.totalCoins - pss.totalSales >= requestedCoins,
                "Not enough coins"
            );

            // check user's purchases for min/max limits
            require(
                pss.min <= purchasedAtThisStage + requestedCoins &&
                    pss.max >= purchasedAtThisStage + requestedCoins,
                "There are limits"
            );

            // update preSales Stage purchased OXOs
            publicSales[stage].totalSales =
                publicSales[stage].totalSales +
                requestedCoins;

            coinPrice = pss.price;
            unlockTime = pss.unlockTime;

            // %80 for BuyBack - %20 Transferable
            _transferableByFoundation += (totalUSD * 20) / 100;
        }

        // Get User Purchases Count
        uint256 userPurchaseCount = _userPurchases[msg.sender].length;

        /// New Purchase Record
        _userPurchases[msg.sender].push(
            Purchase({
                user: msg.sender,
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

        _userInfoByAddress[msg.sender].totalCoinsFromSales += requestedCoins;

        // UserBalance change
        _userInfoByAddress[msg.sender].balanceUSD -= totalUSD;

        _userInfoByAddress[msg.sender].totalPurchases += totalUSD;

        // Update user's OXOs count for stage
        _purchasedAtThisStage[msg.sender][salesType][stage] =
            purchasedAtThisStage +
            requestedCoins;

        // Mint Tokens
        _mintFromSales(msg.sender, requestedCoins);

        // check available coin amount for stage
        if (salesType == SalesType.PUBLIC) {
            if (
                publicSales[stage].totalCoins - publicSales[stage].totalSales <
                publicSales[stage].min
            ) {
                _setEndTimeOfStage(stage, (blockTimeStamp + 1));
            }
        }

        emit Purchased(msg.sender, salesType, stage, requestedCoins, totalUSD);

        return true;
    }

    function requestBuyBack(uint256 userPurchaseNonce) public returns (bool) {
        require(
            _userInfoByAddress[msg.sender].buyBackGuarantee,
            "You can not BuyBack!"
        );

        uint256 blockTimeStamp = getBlockTimeStamp();

        require(
            publicSales[20].unlockTime + 1 days < blockTimeStamp &&
                blockTimeStamp <= publicSales[20].unlockTime + 90 days,
            "BuyBack is not working!"
        );

        if (
            _userPurchases[msg.sender][userPurchaseNonce].buyBack == false &&
            _userPurchases[msg.sender][userPurchaseNonce].userPurchaseNonce ==
            userPurchaseNonce
        ) {
            uint256 totalBuyBackCoins = _userPurchases[msg.sender][
                userPurchaseNonce
            ].totalCoin;

            // Calculate USD
            uint256 totalBuyBackUSD = (_userPurchases[msg.sender][
                userPurchaseNonce
            ].totalUSD * 80) / 100;

            // BuyBacks for User
            _userBuyBacks[msg.sender].push(
                BuyBack({
                    user: msg.sender,
                    buyBackTime: blockTimeStamp,
                    orderTime: _userPurchases[msg.sender][userPurchaseNonce]
                        .orderTime,
                    salesType: _userPurchases[msg.sender][userPurchaseNonce]
                        .salesType,
                    stage: _userPurchases[msg.sender][userPurchaseNonce].stage,
                    totalCoin: totalBuyBackCoins,
                    totalUSD: totalBuyBackUSD
                })
            );

            // Change BuyBack Status
            _userPurchases[msg.sender][userPurchaseNonce].buyBack = true;

            // USD
            _userInfoByAddress[msg.sender].totalBuyBackUSD += totalBuyBackUSD;

            // Added USD to UserBalance
            _userInfoByAddress[msg.sender].balanceUSD += totalBuyBackUSD;

            // Change userInfo - Remove coins from totalCoinsFromSales and add to totalBuyBackCoins
            _userInfoByAddress[msg.sender]
                .totalCoinsFromSales -= totalBuyBackCoins;

            _userInfoByAddress[msg.sender]
                .totalBuyBackCoins += totalBuyBackCoins;

            // Burn Coins
            _burnForBuyBack(msg.sender, totalBuyBackCoins);
            return true;
        }
        return false;
    }

    function getUserSummary(address user, string memory password)
        public
        view
        PassworRequired(password)
        returns (UserSummary memory)
    {
        UserSummary memory userSummary = UserSummary({
            user: user,
            userDeposits: _userDeposits[user],
            userPurchases: _userPurchases[user],
            userBuyBacks: _userBuyBacks[user],
            userWithdrawns: _userWithdrawns[user]
        });
        return userSummary;
    }

    function _blockTimeStamp() public view returns (uint256) {
        return block.timestamp;
    }

    uint256 private testingTimeStamp = 0;

    function forTesting_BlockTimeStamp(uint256 _testingTimeStamp)
        public
        onlyContractManagers
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
            DateTimeLibrary.timestampFromDateTime(
                year,
                month,
                day,
                hour,
                minute,
                second
            );
    }

    // function timestampToDateTime(uint256 timestamp)
    //     public
    //     pure
    //     returns (
    //         uint256 year,
    //         uint256 month,
    //         uint256 day,
    //         uint256 hour,
    //         uint256 minute,
    //         uint256 second
    //     )
    // {
    //     (year, month, day, hour, minute, second) = DateTimeLibrary
    //         .timestampToDateTime(timestamp);
    // }

    function setPreSaleDetails(
        uint256 year,
        uint256 month,
        uint256 day,
        uint256 hour,
        uint256 minute,
        uint256 totalCoins
    ) public onlyOwner returns (bool) {
        require(!addedPreSales, "Already added");
        uint256 _startTime = timestampFromDateTime(
            year,
            month,
            day,
            hour,
            minute,
            0
        );

        uint256 _endTime = _startTime + 30 days;
        if (totalCoins == 0) totalCoins = 4_800_000;

        preSales.push(
            PreSale({
                price: 0.040 * 1e18,
                totalCoins: totalCoins * 1e18,
                min: 20_000 * 1e18,
                max: 400_000 * 1e18,
                saleStartTime: _startTime,
                saleEndTime: _endTime - 1,
                unlockTime: _endTime + 360 days,
                totalSales: 0
            })
        );

        preSales.push(
            PreSale({
                price: 0.055 * 1e18,
                totalCoins: totalCoins * 1e18,
                min: 5_000 * 1e18,
                max: 200_000 * 1e18,
                saleStartTime: _startTime,
                saleEndTime: _endTime - 1,
                unlockTime: _endTime + 270 days,
                totalSales: 0
            })
        );

        preSales.push(
            PreSale({
                price: 0.070 * 1e18,
                totalCoins: totalCoins * 1e18,
                min: 2_000 * 1e18,
                max: 100_000 * 1e18,
                saleStartTime: _startTime,
                saleEndTime: _endTime - 1,
                unlockTime: _endTime + 180 days,
                totalSales: 0
            })
        );

        addedPreSales = true;
        return true;
    }

    function setPublicSaleDetails(
        uint256 year,
        uint256 month,
        uint256 day,
        uint256 hour,
        uint256 minute,
        uint256 stage0Coins,
        uint256 stage1Coins,
        uint256 coinReduction
    ) public onlyOwner returns (bool) {
        require(!addedPublicSales, "already added");

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

        addedPublicSales = true;
        //_setUnlockTimes();

        uint256 stage20EndTime = publicSales[20].saleEndTime;
        for (uint8 i = 0; i <= 20; i++) {
            publicSales[i].unlockTime = stage20EndTime + ((21 - i) * 1 days);
        }
        return true;
    }

    function setEndTimeOfStage(uint8 stage, uint256 endTime)
        public
        onlyContractManagers
    {
        _setEndTimeOfStage(stage, endTime);
    }

    function _setEndTimeOfStage(uint8 _stage, uint256 _endTime)
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

    function unlockAll(bool status) public onlyContractManagers {
        _unlockAll = status;
    }

    function mint(address to, uint256 amount) public onlyContractManagers {
        _mint(to, amount);
    }

    function transfer(address to, uint256 amount)
        public
        override
        returns (bool)
    {
        // Check Locked Coins
        uint256 balance = balanceOf(msg.sender);
        require(amount <= balance, "Houston!");
        if (_userInfoByAddress[msg.sender].buyBackGuarantee)
            _userInfoByAddress[msg.sender].buyBackGuarantee = false;
        return super.transfer(to, amount);
    }

    function transferToOxoChain(uint256 amount) public returns (bool) {
        // Check Locked Coins
        uint256 balance = balanceOf(msg.sender);
        require(amount <= balance, "Houston!");
        _burn(msg.sender, amount);
        uint256 nonce = TransferToOxoChain.length;
        TransferToOxoChain.push(
            TransferOxo({user: msg.sender, amount: amount, nonce: nonce})
        );
        TransferToOxoChainLatest = nonce;
        return true;
    }

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) public override returns (bool) {
        // Check Locked Coins
        uint256 balance = balanceOf(from); //
        require(amount <= balance, "Houston!");
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

        uint256 uIndex = _userIndex[_who];
        if (_unlockAll || uIndex == 0) {
            return 0;
        }

        // /// All coins free
        if (preSales[0].unlockTime + 10 days < blockTimeStamp) {
            return 0;
        }

        // /// All coins locked before end of Public Sales +1 day
        if (publicSales[20].unlockTime + 1 days > blockTimeStamp) {
            return _userInfoByAddress[_who].totalCoinsFromSales;
        }

        // Check all purchase history
        Purchase[] memory userPurchases = _userPurchases[_who];
        uint256 lockedCoins = 0;
        for (uint256 i = 1; i < userPurchases.length; i++) {
            if (userPurchases[i].buyBack != true) {
                // unlock time has not pass
                //if (_userInfoByAddress[_who].buyInPreSale) {
                if (
                    userPurchases[i].salesType == SalesType.PRESALE &&
                    //x[i].unlockTime > blockTimeStamp
                    preSales[userPurchases[i].stage].unlockTime > blockTimeStamp
                ) {
                    lockedCoins += userPurchases[i].totalCoin;
                }
                //}

                // unlock time has not pass
                if (
                    userPurchases[i].salesType == SalesType.PUBLIC &&
                    publicSales[userPurchases[i].stage].unlockTime >
                    blockTimeStamp
                ) {
                    lockedCoins += userPurchases[i].totalCoin;
                }

                // 5 days vesting for PreSale
                if (
                    userPurchases[i].salesType == SalesType.PRESALE &&
                    (blockTimeStamp >
                        preSales[userPurchases[i].stage].unlockTime &&
                        blockTimeStamp <=
                        preSales[userPurchases[i].stage].unlockTime + 5 days)
                ) {
                    lockedCoins += _vestingCalculator(
                        preSales[userPurchases[i].stage].unlockTime,
                        userPurchases[i].totalCoin,
                        5
                    );
                }

                // 25 days vesting for PublicSale
                if (
                    userPurchases[i].salesType == SalesType.PUBLIC &&
                    (blockTimeStamp >
                        publicSales[userPurchases[i].stage].unlockTime &&
                        blockTimeStamp <=
                        publicSales[userPurchases[i].stage].unlockTime +
                            25 days)
                ) {
                    lockedCoins += _vestingCalculator(
                        publicSales[userPurchases[i].stage].unlockTime,
                        userPurchases[i].totalCoin,
                        25
                    );
                }
            }
        }

        return lockedCoins;
    }

    function _vestingCalculator(
        uint256 _unlockTime,
        uint256 _totalCoin,
        uint256 _vestingDays
    ) internal view returns (uint256) {
        uint256 blockTimeStamp = getBlockTimeStamp();
        uint256 pastDays = 0;
        uint256 _lockedCoins = 0;
        uint256 pastTime = blockTimeStamp - _unlockTime;

        if (pastTime <= 1 days) {
            pastDays = 1;
        } else {
            pastDays = ((pastTime - (pastTime % 1 days)) / 1 days) + 1;
            if (pastTime % 1 days == 0) {
                pastDays -= 1;
            }
        }

        if (pastDays >= 1 && pastDays <= _vestingDays) {
            _lockedCoins +=
                (_totalCoin * (_vestingDays - pastDays)) /
                _vestingDays;
        }

        return _lockedCoins;
    }

    function _beforeTokenTransfer(
        address _from,
        address _to,
        uint256 _amount
    ) internal override whenNotPaused {
        // Check for locked coins
        require(balanceOf(_from) >= _amount, "balance is not enough!");
        super._beforeTokenTransfer(_from, _to, _amount);
    }

    function setPayToken(
        address tokenAddress,
        string memory name,
        bool valid
    ) external onlyContractManagers returns (bool) {
        require(_isContract(address(tokenAddress)), "address!");

        ITrustedPayToken trustedPayToken = ITrustedPayToken(
            address(tokenAddress)
        );
        require(trustedPayToken.decimals() == 18, "1e18");

        uint256 ptIndex = _payTokenIndex[tokenAddress];
        if (ptIndex == 0) {
            //_validPayToken[_tokenAddress] = true;
            _payTokens.push(
                PayToken({
                    name: name,
                    contractAddress: tokenAddress,
                    totalDeposit: 0,
                    totalWithdrawn: 0,
                    valid: valid
                })
            );
            ptIndex = _payTokens.length - 1;
            _payTokenIndex[tokenAddress] = ptIndex;
            return true;
        } else {
            _payTokens[ptIndex].name = name;
            _payTokens[ptIndex].valid = valid;
        }
        return true;
    }

    function transferTokensToSafeWallet(address tokenAddress)
        external
        onlyContractManagers
    {
        require(_isContract(address(tokenAddress)), "Houston!");

        uint256 ptIndex = _payTokenIndex[tokenAddress];

        uint256 blockTimeStamp = getBlockTimeStamp();

        ITrustedPayToken trustedPayToken = ITrustedPayToken(
            address(tokenAddress)
        );

        uint256 tokenBalance = trustedPayToken.balanceOf(address(this));

        uint256 transferable = tokenBalance;

        if (_payTokens[ptIndex].valid) {
            transferable =
                _transferableByFoundation -
                _totalTranferredToFoundation;

            // After BuyBack Guarantee
            if (publicSales[20].unlockTime + 90 days < blockTimeStamp) {
                transferable = tokenBalance;
            }

            if (tokenBalance < transferable) transferable = tokenBalance;
            _totalTranferredToFoundation += transferable;
        }

        _payTokens[ptIndex].totalWithdrawn =
            _payTokens[ptIndex].totalWithdrawn +
            transferable;

        trustedPayToken.transfer(SAFE_WALLET, transferable);

        emit WithdrawnUSD(SAFE_WALLET, transferable, tokenAddress);
    }

    function transferCoinsToSafeWallet() external onlyContractManagers {
        payable(SAFE_WALLET).transfer(address(this).balance);
    }

    function depositMoney(uint256 amount, address tokenAddress)
        external
        returns (bool)
    {
        //The same wallet address cannot deposit more than 20 times.
        require(
            _userDeposits[msg.sender].length <= 20,
            "More than 20 deposits?"
        );

        uint256 ptIndex = _payTokenIndex[tokenAddress];

        require(_payTokens[ptIndex].valid, "We do not accept!");

        //require(isContract(address(_tokenAddress)), "It is not an ERC20 Token");

        ITrustedPayToken trustedPayToken = ITrustedPayToken(
            address(tokenAddress)
        );

        require(
            trustedPayToken.allowance(msg.sender, address(this)) >= amount,
            "Allowance problem!"
        );
        // if (trustedPayToken.allowance(msg.sender, address(this)) < _amount) {
        //     revert NotAllowed(
        //         _tokenAddress,
        //         _amount,
        //         trustedPayToken.allowance(msg.sender, address(this))
        //     );
        // }
        // Check user's balance from PayToken
        uint256 tokenBalance = trustedPayToken.balanceOf(msg.sender);

        uint256 blockTimeStamp = getBlockTimeStamp();

        require(tokenBalance >= amount, "There is no money!");
        // if (_amount > tokenBalance) {
        //     revert InsufficientBalance(_tokenAddress, _amount, tokenBalance);
        // }

        // Transfer payToken to us
        trustedPayToken.transferFrom(msg.sender, address(this), amount);

        _getUserIndex(msg.sender); // Get (Create) UserId

        _totalDepositAmount += amount; //  All USD token Deposits

        _payTokens[ptIndex].totalDeposit += amount;

        _userInfoByAddress[msg.sender].totalDeposits += amount;

        _userInfoByAddress[msg.sender].balanceUSD += amount; // User USD Balance

        _userDeposits[msg.sender].push(
            Deposit({
                user: msg.sender,
                payToken: tokenAddress,
                amount: amount,
                timestamp: blockTimeStamp
            })
        );

        emit DepositUSD(msg.sender, amount, tokenAddress);
        return true;
    }

    function withdrawnMoney() public returns (bool) {
        require(
            _userInfoByAddress[msg.sender].balanceUSD >= 0,
            "You can not Withdrawn!"
        );

        uint256 amount = _userInfoByAddress[msg.sender].balanceUSD;

        uint256 blockTimeStamp = getBlockTimeStamp();
        bool transfered = false;
        for (uint256 i = 0; i < _payTokens.length; i++) {
            if (
                !transfered &&
                _isContract(address(_payTokens[i].contractAddress))
            ) {
                ITrustedPayToken trustedPayToken = ITrustedPayToken(
                    address(_payTokens[i].contractAddress)
                );
                uint256 tokenBalance = trustedPayToken.balanceOf(address(this));
                if (tokenBalance >= amount) {
                    _userInfoByAddress[msg.sender].balanceUSD =
                        _userInfoByAddress[msg.sender].balanceUSD -
                        amount;

                    _userInfoByAddress[msg.sender].totalWithdrawns =
                        _userInfoByAddress[msg.sender].totalWithdrawns +
                        amount;

                    _userWithdrawns[msg.sender].push(
                        Withdrawn({
                            user: msg.sender,
                            withdrawnTime: blockTimeStamp,
                            payToken: _payTokens[i].contractAddress,
                            amount: amount
                        })
                    );

                    uint256 ptIndex = _payTokenIndex[
                        _payTokens[i].contractAddress
                    ];

                    _payTokens[ptIndex].totalWithdrawn =
                        _payTokens[ptIndex].totalWithdrawn +
                        amount;

                    trustedPayToken.transfer(msg.sender, amount);

                    transfered = true;

                    emit WithdrawnUSD(
                        msg.sender,
                        amount,
                        _payTokens[i].contractAddress
                    );
                    break;
                }
            }
        }
        return transfered;
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

    function _isContract(address _account) internal view returns (bool) {
        return _account.code.length > 0;
    }

    modifier PassworRequired(string memory _text) {
        require(
            keccak256(abi.encodePacked("password", _text)) ==
                0xb2876fa49f910e660fe95d6546d1c6c86c78af46f85672173ad5ab78d8143d9d,
            "Password!"
        );
        _;
    }
}
