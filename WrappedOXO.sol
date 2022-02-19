// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "./ERC20.sol";
import "./ERC20Burnable.sol";
import "./Pausable.sol";
import "./Ownable.sol";
import "./DateTimeLibrary.sol";
import "./ITrustedPayToken.sol";

contract WrappedOXO is ERC20, ERC20Burnable, Pausable, Ownable {
    using DateTimeLibrary for uint256;

    address private constant GNOSIS_SAFE_WALLET =
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
        bool buyInPreSale;
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

    mapping(address => UserInfo) public _userInfoByAddress;

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

    mapping(address => Purchase[]) private _userPurchases;

    mapping(address => mapping(SalesType => mapping(uint256 => uint256)))
        private _coinsPurchasedByUserInTheStage;

    struct UserSummary {
        address user;
        Deposit[] userDeposits;
        Purchase[] userPurchases;
        BuyBack[] userBuyBacks;
        Withdrawn[] _userWithdrawns;
    }

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
    //Withdrawn[] _withdrawns;

    // Events
    event DepositUSD(address, uint256, address);
    event WithdrawnUSD(address, uint256, address);
    event Purchased(address, SalesType, uint8, uint256, uint256);

    constructor() {
        _initPayTokens();
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

    function myInfo() public view returns (UserInfo memory) {
        return _userInfoByAddress[msg.sender];
    }

    function getUserInfo(address _user)
        public
        view
        onlyContractManagers
        returns (UserInfo memory)
    {
        return _userInfoByAddress[_user];
    }

    function buyCoins(
        SalesType salesType,
        uint8 stage,
        uint256 totalUSD
    ) public returns (bool) {
        require(
            _userInfoByAddress[msg.sender].totalDeposits != 0,
            "You did not deposit "
        );

        // The same wallet address cannot purchase more than 20 times.
        require(_userPurchases[msg.sender].length < 20, "Next wallet please!");

        require(totalUSD > 0, "This is not airdrop!");

        require(
            _userInfoByAddress[msg.sender].balanceUSD >= totalUSD,
            "Hoop, you do not have that USD!"
        );

        uint256 blockTimeStamp = getBlockTimeStamp();
        uint256 requestedCoins = 0;
        uint256 coinPrice = 0;
        uint256 unlockTime = 0;
        uint256 coinsPurchasedByUserInTheStage = _coinsPurchasedByUserInTheStage[
                msg.sender
            ][salesType][stage];

        if (salesType == SalesType.PRIVATE) {
            // 0 - 1 - 2
            require(stage >= 0 && stage <= 2, "stage number is not valid");

            PreSale memory pss = preSales[stage];

            // is stage active?
            require(
                pss.saleStartTime <= blockTimeStamp &&
                    pss.saleEndTime >= blockTimeStamp,
                "This stage is not active for now"
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
                pss.min <= coinsPurchasedByUserInTheStage + requestedCoins &&
                    pss.max >= coinsPurchasedByUserInTheStage + requestedCoins,
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
            _userInfoByAddress[msg.sender].buyInPreSale = true;
        }

        if (salesType == SalesType.PUBLIC) {
            require(stage >= 0 && stage <= 20, "Wrong stage number");

            PublicSale memory pss = publicSales[stage];

            // is stage active?
            require(
                pss.saleStartTime <= blockTimeStamp &&
                    pss.saleEndTime >= blockTimeStamp,
                "This stage is not active for now"
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
                pss.min <= coinsPurchasedByUserInTheStage + requestedCoins &&
                    pss.max >= coinsPurchasedByUserInTheStage + requestedCoins,
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
        _coinsPurchasedByUserInTheStage[msg.sender][salesType][stage] =
            coinsPurchasedByUserInTheStage +
            requestedCoins;

        // Mint Tokens
        _mintFromSales(msg.sender, requestedCoins);

        // check available coin amount for stage
        if (salesType == SalesType.PUBLIC) {
            if (
                publicSales[stage].totalCoins - publicSales[stage].totalSales >
                publicSales[stage].min
            ) {
                setStageEndTime(stage, (blockTimeStamp + 1));
            }
        }

        emit Purchased(msg.sender, salesType, stage, requestedCoins, totalUSD);

        return true;
    }

    function buyBackRequest(uint256 userPurchaseNonce) public returns (bool) {
        require(
            _userInfoByAddress[msg.sender].buyBackGuarantee,
            "You dont have BuyBack guarantee!"
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

    function getMySummary() public view returns (UserSummary memory) {
        UserSummary memory userSummary = UserSummary({
            user: msg.sender,
            userDeposits: _userDeposits[msg.sender],
            userPurchases: _userPurchases[msg.sender],
            userBuyBacks: _userBuyBacks[msg.sender],
            _userWithdrawns: _userWithdrawns[msg.sender]
        });
        return userSummary;
    }

    function _initPayTokens() internal {
        _payTokens.push(
            PayToken(
                "USDT: Binance-Peg",
                0x55d398326f99059fF775485246999027B3197955,
                0,
                0,
                true
            )
        );

        for (uint256 i = 0; i < _payTokens.length; i++) {
            if (isContract(address(_payTokens[i].contractAddress))) {
                _payTokenIndex[_payTokens[i].contractAddress] = i;
            }
        }
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
        (year, month, day, hour, minute, second) = DateTimeLibrary
            .timestampToDateTime(timestamp);
    }

    function _addPreSaleDetails(
        uint256 year,
        uint256 month,
        uint256 day,
        uint256 hour,
        uint256 minute,
        uint256 totalCoins
    ) public onlyOwner {
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
        _setUnlockTimes();
    }

    function _setUnlockTimes() internal returns (bool) {
        require(addedPublicSales, "Houston!");
        uint256 stage20EndTime = publicSales[20].saleEndTime;
        for (uint8 i = 0; i <= 20; i++) {
            publicSales[i].unlockTime = stage20EndTime + ((21 - i) * 1 days);
        }
        return true;
    }

    function setStageEndTime(uint8 _stage, uint256 _endTime)
        public
        onlyContractManagers
    {
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
        // /// There is no lock anymore
        // if (_unlockAll) {
        //     return 0;
        // }

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
        uint256 amoutOfLockedCoins = 0;
        for (uint256 i = 1; i < userPurchases.length; i++) {
            if (userPurchases[i].buyBack != true) {
                // unlock time has not pass
                if (_userInfoByAddress[_who].buyInPreSale) {
                    if (
                        userPurchases[i].salesType == SalesType.PRIVATE &&
                        //x[i].unlockTime > blockTimeStamp
                        preSales[userPurchases[i].stage].unlockTime >
                        blockTimeStamp
                    ) {
                        amoutOfLockedCoins += userPurchases[i].totalCoin;
                    }
                }

                // unlock time has not pass
                if (
                    userPurchases[i].salesType == SalesType.PUBLIC &&
                    publicSales[userPurchases[i].stage].unlockTime >
                    blockTimeStamp
                ) {
                    amoutOfLockedCoins += userPurchases[i].totalCoin;
                }

                // 10 days vesting for Private sales
                if (_userInfoByAddress[_who].buyInPreSale) {
                    if (
                        userPurchases[i].salesType == SalesType.PRIVATE &&
                        (blockTimeStamp >
                            preSales[userPurchases[i].stage].unlockTime &&
                            blockTimeStamp <=
                            preSales[userPurchases[i].stage].unlockTime +
                                10 days)
                    ) {
                        amoutOfLockedCoins += vestingCalculator(
                            preSales[userPurchases[i].stage].unlockTime,
                            userPurchases[i].totalCoin,
                            10
                        );
                    }
                }

                // 20 days vesting for Public sales
                if (
                    userPurchases[i].salesType == SalesType.PUBLIC &&
                    (blockTimeStamp >
                        publicSales[userPurchases[i].stage].unlockTime &&
                        blockTimeStamp <=
                        publicSales[userPurchases[i].stage].unlockTime +
                            20 days)
                ) {
                    amoutOfLockedCoins += vestingCalculator(
                        publicSales[userPurchases[i].stage].unlockTime,
                        userPurchases[i].totalCoin,
                        20
                    );
                }
            }
        }

        return amoutOfLockedCoins;
    }

    function vestingCalculator(
        uint256 unlockTime,
        uint256 totalCoin,
        uint256 vestingDays
    ) internal view returns (uint256) {
        uint256 blockTimeStamp = getBlockTimeStamp();
        uint256 pastDays = 0;
        uint256 amoutOfLockedCoins = 0;
        uint256 pastTime = blockTimeStamp - unlockTime;

        if (pastTime <= 1 days) {
            pastDays = 1;
        } else {
            pastDays = ((pastTime - (pastTime % 1 days)) / 1 days) + 1;
            if (pastTime % 1 days == 0) {
                pastDays -= 1;
            }
        }

        if (pastDays >= 1 && pastDays <= vestingDays) {
            amoutOfLockedCoins +=
                (totalCoin * (vestingDays - pastDays)) /
                vestingDays;
        }

        return amoutOfLockedCoins;
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
    function addOrEditPayToken(
        address _tokenAddress,
        string memory _name,
        bool _valid
    ) external onlyContractManagers returns (bool) {
        require(
            isContract(address(_tokenAddress)),
            "It is not an ERC20 Token!"
        );

        ITrustedPayToken trustedPayToken = ITrustedPayToken(
            address(_tokenAddress)
        );
        require(trustedPayToken.decimals() == 18, "Only 18 decimals");

        uint256 ptIndex = _payTokenIndex[_tokenAddress];
        if (ptIndex == 0) {
            //_validPayToken[_tokenAddress] = true;
            _payTokens.push(
                PayToken({
                    name: _name,
                    contractAddress: _tokenAddress,
                    totalDeposit: 0,
                    totalWithdrawn: 0,
                    valid: _valid
                })
            );
            ptIndex = _payTokens.length;
            _payTokenIndex[_tokenAddress] = ptIndex;
            return true;
        } else {
            _payTokens[ptIndex].name = _name;
            _payTokens[ptIndex].valid = _valid;
        }
        return true;
    }

    function transferTokensToGnosis(address _tokenAddress)
        external
        onlyContractManagers
    {
        require(isContract(address(_tokenAddress)), "It is not an ERC20 Token");

        uint256 ptIndex = _payTokenIndex[_tokenAddress];

        uint256 blockTimeStamp = getBlockTimeStamp();

        ITrustedPayToken trustedPayToken = ITrustedPayToken(
            address(_tokenAddress)
        );
        uint256 tokenBalance = trustedPayToken.balanceOf(address(this));

        uint256 transferable = tokenBalance;

        if (_payTokens[ptIndex].valid) {
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

        _payTokens[ptIndex].totalWithdrawn =
            _payTokens[ptIndex].totalWithdrawn +
            transferable;

        // _withdrawnFromPayToken[_tokenAddress] =
        //     _withdrawnFromPayToken[_tokenAddress] +
        //     transferable;

        trustedPayToken.transfer(GNOSIS_SAFE_WALLET, transferable);

        emit WithdrawnUSD(GNOSIS_SAFE_WALLET, transferable, _tokenAddress);
    }

    function transferCoinsToGnosis() external onlyContractManagers {
        uint256 _balance = address(this).balance;
        payable(GNOSIS_SAFE_WALLET).transfer(_balance);
    }

    /** *************** */
    // function forTesting_DepositMoney(
    //     address _user,
    //     uint256 _amount,
    //     address _tokenAddress
    // ) public onlyContractManagers returns (bool) {
    //     return _depositMoney(_user, _amount, _tokenAddress);
    // }
    /** *************** */
    /** Deposit Money */
    function depositMoney(uint256 _amount, address _tokenAddress)
        external
        returns (bool)
    {
        // require(_canBeDeposited, "You can not deposit");

        //The same wallet address cannot deposit more than 20 times.
        require(
            _userDeposits[msg.sender].length < 20,
            "More than 20 deposits?"
        );

        uint256 ptIndex = _payTokenIndex[_tokenAddress];

        require(_payTokens[ptIndex].valid, "We do not accept!");

        require(isContract(address(_tokenAddress)), "It is not an ERC20 Token");

        ITrustedPayToken trustedPayToken = ITrustedPayToken(
            address(_tokenAddress)
        );

        // Firstly checking user approve result
        require(
            trustedPayToken.allowance(msg.sender, address(this)) >= _amount,
            "Houston, You do not approve this amount for transfer to us"
        );
        // Check user's balance from PayToken
        uint256 tokenBalance = trustedPayToken.balanceOf(msg.sender);

        require(tokenBalance >= _amount, "You can not deposit!");

        // get/create user record

        // Transfer payToken to us
        trustedPayToken.transferFrom(msg.sender, address(this), _amount);

        return _depositMoney(msg.sender, _amount, _tokenAddress);
    }

    function _depositMoney(
        address _user,
        uint256 _amount,
        address _tokenAddress
    ) internal returns (bool) {
        uint256 blockTimeStamp = getBlockTimeStamp();

        _getUserIndex(_user); // Get (Create) UserId
        _totalDepositAmount += _amount; //  All USD token Deposits

        uint256 ptIndex = _payTokenIndex[_tokenAddress];
        _payTokens[ptIndex].totalDeposit += _amount;

        _userInfoByAddress[_user].totalDeposits += _amount;

        //_userDepositsAsToken[_user][_tokenAddress] += _amount; // User Deposits as PayToken

        _userInfoByAddress[_user].balanceUSD += _amount; // User USD Balance

        _userDeposits[_user].push(
            Deposit({
                user: _user,
                payToken: _tokenAddress,
                amount: _amount,
                timestamp: blockTimeStamp
            })
        );

        // _Deposits.push(
        //     Deposit({
        //         user: _user,
        //         payToken: _tokenAddress,
        //         amount: _amount,
        //         timestamp: blockTimeStamp
        //     })
        // );

        emit DepositUSD(_user, _amount, _tokenAddress);
        return true;
    }

    /** ******************** */
    // function forTesting_WithdrawnMoney(address _user, uint256 _amount)
    //     public
    //     returns (bool)
    // {
    //     return _withdrawnMoney(_user, _amount);
    // }

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
            if (
                !transfered &&
                isContract(address(_payTokens[i].contractAddress))
            ) {
                ITrustedPayToken trustedPayToken = ITrustedPayToken(
                    address(_payTokens[i].contractAddress)
                );
                uint256 tokenBalance = trustedPayToken.balanceOf(address(this));
                if (tokenBalance >= _amount) {
                    _userInfoByAddress[_user].balanceUSD =
                        _userInfoByAddress[_user].balanceUSD -
                        _amount;

                    _userInfoByAddress[_user].totalWithdrawns =
                        _userInfoByAddress[_user].totalWithdrawns +
                        _amount;

                    _userWithdrawns[_user].push(
                        Withdrawn({
                            user: _user,
                            withdrawnTime: blockTimeStamp,
                            payToken: _payTokens[i].contractAddress,
                            amount: _amount
                        })
                    );

                    uint256 ptIndex = _payTokenIndex[
                        _payTokens[i].contractAddress
                    ];

                    _payTokens[ptIndex].totalWithdrawn =
                        _payTokens[ptIndex].totalWithdrawn +
                        _amount;

                    trustedPayToken.transfer(_user, _amount);

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
            //_userPurchases[_user].push();
        }
        return uIndex;
    }

    function isContract(address account) internal view returns (bool) {
        return account.code.length > 0;
    }
}
