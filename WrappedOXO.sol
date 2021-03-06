// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;
import "./ERC20.sol";
import "./ERC20Burnable.sol";
import "./Pausable.sol";
import "./Ownable.sol";
import "./ITrustedPayToken.sol";

contract WrappedOXO is ERC20, ERC20Burnable, Pausable, Ownable {
    uint256 public _version = 4;

    address private SAFE_WALLET = 0x3edF93dc2e32fD796c108118f73fa2ae585C66B6;

    uint256 private _transferableByFoundation;
    uint256 public buyBackFund;
    uint256 private _totalTranferredToFoundation;

    mapping(address => bool) private contractManagers;

    struct TransferChain {
        address user;
        uint256 chainId;
        uint256 amount;
        uint256 nonce;
    }

    TransferChain[] public TransferToChain;
    uint256 public TransferToChainLatest = 0;

    // User Info
    struct UserInfo {
        address user;
        bool buyBackGuarantee;
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
    uint256 private _totalDepositedUSD;

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

    constructor() {
        //_initPayTokens();
        _payTokens.push();
        TransferToChain.push();
        contractManagers[msg.sender] = true;
    }

    modifier onlyContractManagers() {
        require(contractManagers[msg.sender], "?");
        _;
    }

    function setManager(address managerAddress, bool status)
        public
        onlyOwner
        returns (bool)
    {
        require(managerAddress != msg.sender, "??");
        contractManagers[managerAddress] = status;
        return true;
    }

    function setPayToken(
        address tokenAddress,
        string memory name,
        bool valid
    ) external onlyContractManagers returns (bool) {
        require(_isContract(address(tokenAddress)), "!!!");

        ITrustedPayToken trustedPayToken = ITrustedPayToken(
            address(tokenAddress)
        );
        require(trustedPayToken.decimals() == 18, "1e18");

        uint256 ptIndex = _payTokenIndex[tokenAddress];
        if (ptIndex == 0) {
            _payTokens.push(PayToken(name, tokenAddress, 0, 0, valid));
            _payTokenIndex[tokenAddress] = _payTokens.length - 1;
        } else {
            _payTokens[ptIndex].name = name;
            _payTokens[ptIndex].valid = valid;
        }
        return true;
    }

    function getPayTokens() public view returns (PayToken[] memory) {
        return _payTokens;
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

        ActiveStageSummary memory ass = ActiveStageSummary(
            getBlockTimeStamp(),
            _preSale,
            _publicSale,
            _totalCoinsInSale,
            _totalSalesInSale
        );

        return ass;
    }

    function setPreSaleDetails(uint256 _startTime) public onlyOwner {
        require(preSales.length == 0, "Already");

        uint256 _endTime = _startTime + 30 days;
        //if (totalCoins == 0) totalCoins = 4_800_000;
        uint256 totalCoins = 4_800_000;

        preSales.push(
            PreSale(
                0.040 * 1e18,
                totalCoins * 1e18,
                20_000 * 1e18,
                400_000 * 1e18,
                _startTime,
                _endTime - 1,
                _endTime + 360 days,
                0
            )
        );

        preSales.push(
            PreSale(
                0.055 * 1e18,
                totalCoins * 1e18,
                5_000 * 1e18,
                200_000 * 1e18,
                _startTime,
                _endTime - 1,
                _endTime + 270 days,
                0
            )
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
    }

    function setPublicSaleDetails(uint256 _startTime) public onlyOwner {
        require(publicSales.length == 0, "Already");

        uint256 stage0Coins = 9_600_000;
        uint256 stage1Coins = 5_000_000;

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
            uint256 _totalCoins = stage1Coins * 1e18; //_totalCoins = (stage1Coins - ((i - 1) * coinReduction)) *  1e18;
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
                PublicSale(
                    _price,
                    _totalCoins,
                    100 * 1e18,
                    500_000 * 1e18,
                    startTime,
                    startTime + 7 days - 1,
                    0,
                    0
                )
            );
        }

        uint256 stage20EndTime = publicSales[20].saleEndTime;
        for (uint8 i = 0; i <= 20; i++) {
            publicSales[i].unlockTime = stage20EndTime + ((21 - i) * 1 days);
        }
    }

    function setEndTimeOfStage(uint8 stage, uint256 endTime)
        public
        onlyContractManagers
    {
        _setEndTimeOfStage(stage, endTime);
    }

    function _setEndTimeOfStage(uint8 _stage, uint256 _endTime) internal {
        require(0 <= _stage && _stage <= 20, "invalid");
        require(
            publicSales[_stage].saleEndTime < _endTime &&
                _endTime > publicSales[_stage].saleStartTime,
            "Wrong!"
        );
        publicSales[_stage].saleEndTime = _endTime;
        if (_stage != 20) _setStageTime(_stage + 1);
    }

    // Set stage start and end time after stage 2
    function _setStageTime(uint8 _stage) internal {
        require(_stage >= 1 && _stage <= 20, "invalid");

        uint256 previousStageStartTime = publicSales[_stage - 1].saleStartTime;
        uint256 previousStageEndTime = publicSales[_stage - 1].saleEndTime;

        uint256 previousStageDays = 7 days;
        if (_stage == 1) previousStageDays = 14 days;

        uint256 fixStageTime = previousStageDays -
            (previousStageEndTime - previousStageStartTime);

        fixStageTime -= 1 minutes; // 1 minutes break time :)

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
    }

    function depositMoney(uint256 amount, address tokenAddress) external {
        require(_userDeposits[msg.sender].length < 20, "20");
        uint256 blockTimeStamp = getBlockTimeStamp();
        require(blockTimeStamp < publicSales[20].saleEndTime, "??");
        uint256 ptIndex = _payTokenIndex[tokenAddress];
        require(_payTokens[ptIndex].valid, "Dont accept!");

        ITrustedPayToken trustedPayToken = ITrustedPayToken(
            address(tokenAddress)
        );

        require(
            trustedPayToken.allowance(msg.sender, address(this)) >= amount,
            "Allowance!"
        );

        uint256 tokenBalance = trustedPayToken.balanceOf(msg.sender);

        require(tokenBalance >= amount, "no money!");

        trustedPayToken.transferFrom(msg.sender, address(this), amount);

        _getUserIndex(msg.sender); // Get (or Create) UserId

        _totalDepositedUSD += amount; //  All USD token Deposits

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
    }

    function buyCoins(
        SalesType salesType,
        uint8 stage,
        uint256 totalUSD
    ) public {
        require(_userInfoByAddress[msg.sender].totalDeposits != 0, "Deposit");
        require(_userPurchases[msg.sender].length < 20, "20");
        require(totalUSD > 1 * 1e18, "Airdrop?");
        require(
            _userInfoByAddress[msg.sender].balanceUSD >= totalUSD,
            "Balance!"
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
            require(0 <= stage && stage <= 2, "wrong");

            PreSale memory pss = preSales[stage];

            // is stage active?
            require(
                pss.saleStartTime <= blockTimeStamp &&
                    blockTimeStamp <= pss.saleEndTime,
                "not active"
            );

            // calculate OXOs for that USD
            // requestedCoins = ((totalUSD * 1e4) / p.price) * 1e14;
            requestedCoins = ((totalUSD) / pss.price) * 1e18;

            totalUSD = (requestedCoins * pss.price) / 1e18;
            // is there enough OXOs?
            require(
                pss.totalCoins - pss.totalSales >= requestedCoins,
                "Not enough"
            );

            // check user's purchases for min/max limits
            require(
                pss.min <= purchasedAtThisStage + requestedCoins &&
                    pss.max >= purchasedAtThisStage + requestedCoins,
                "limits"
            );

            // update preSales Stage purchased OXOs
            preSales[stage].totalSales += requestedCoins;

            coinPrice = pss.price;
            unlockTime = pss.unlockTime;

            _transferableByFoundation += totalUSD;
            buyBackFund += (totalUSD * 80) / 100;
        }

        if (salesType == SalesType.PUBLIC) {
            require(0 <= stage && stage <= 20, "Wrong");

            PublicSale memory pss = publicSales[stage];

            // is stage active?
            require(
                pss.saleStartTime <= blockTimeStamp &&
                    blockTimeStamp <= pss.saleEndTime,
                "not active"
            );

            // calculate OXOs for that USD
            //requestedCoins = ((totalUSD * 1e2) / p.price) * 1e16;
            requestedCoins = ((totalUSD) / pss.price) * 1e18;
            totalUSD = (requestedCoins * pss.price) / 1e18;

            // is there enough OXOs?
            require(
                pss.totalCoins - pss.totalSales >= requestedCoins,
                "Not enough"
            );

            // check user's purchases for min/max limits
            require(
                pss.min <= purchasedAtThisStage + requestedCoins &&
                    purchasedAtThisStage + requestedCoins <= pss.max,
                "limits"
            );

            // update preSales Stage purchased OXOs
            publicSales[stage].totalSales += requestedCoins;

            coinPrice = pss.price;
            unlockTime = pss.unlockTime;

            // %80 for BuyBack - %20 Transferable
            _transferableByFoundation += (totalUSD * 20) / 100;
            buyBackFund += (totalUSD * 80) / 100;
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

        //_totalSales += totalUSD;

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

        //emit Purchased(msg.sender, salesType, stage, requestedCoins, totalUSD);

        //return true;
    }

    function requestBuyBack(uint256 userPurchaseNonce) public {
        require(
            _userInfoByAddress[msg.sender].buyBackGuarantee,
            "can not BuyBack!"
        );

        uint256 blockTimeStamp = getBlockTimeStamp();

        require(
            publicSales[20].unlockTime <= blockTimeStamp &&
                blockTimeStamp <= publicSales[20].unlockTime + 90 days,
            "wrong dates!"
        );

        require(
            !_userPurchases[msg.sender][userPurchaseNonce].buyBack &&
                _userPurchases[msg.sender][userPurchaseNonce].totalUSD > 0,
            "???"
        );

        uint256 totalBuyBackCoins = _userPurchases[msg.sender][
            userPurchaseNonce
        ].totalCoin;

        // Calculate USD
        uint256 totalBuyBackUSD = (_userPurchases[msg.sender][userPurchaseNonce]
            .totalUSD * 80) / 100;

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

        _userPurchases[msg.sender][userPurchaseNonce].buyBack = true;

        _userInfoByAddress[msg.sender].totalBuyBackUSD += totalBuyBackUSD;

        _userInfoByAddress[msg.sender].balanceUSD += totalBuyBackUSD;

        _userInfoByAddress[msg.sender].totalCoinsFromSales -= totalBuyBackCoins;

        _userInfoByAddress[msg.sender].totalBuyBackCoins += totalBuyBackCoins;

        _burnForBuyBack(msg.sender, totalBuyBackCoins);
    }

    function withdrawnMoney() public returns (bool) {
        uint256 amount = _userInfoByAddress[msg.sender].balanceUSD;
        require(amount > 0, "can not Withdrawn!");

        uint256 blockTimeStamp = getBlockTimeStamp();
        bool transfered = false;
        for (uint256 i = 1; i < _payTokens.length; i++) {
            if (!transfered && _payTokens[i].valid) {
                ITrustedPayToken trustedPayToken = ITrustedPayToken(
                    address(_payTokens[i].contractAddress)
                );
                uint256 tokenBalance = trustedPayToken.balanceOf(address(this));
                if (tokenBalance >= amount) {
                    _userInfoByAddress[msg.sender].balanceUSD -= amount;

                    _userInfoByAddress[msg.sender].totalWithdrawns += amount;

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

                    _payTokens[ptIndex].totalWithdrawn += amount;

                    trustedPayToken.transfer(msg.sender, amount);

                    transfered = true;

                    break;
                }
            }
        }
        return transfered;
    }

    function getUserSummary(address user)
        public
        view
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

    // function forTesting_BlockTimeStamp(uint256 _testingTimeStamp)
    //     public
    //     onlyContractManagers
    // {
    //     testingTimeStamp = _testingTimeStamp;
    // }

    function getBlockTimeStamp() public view returns (uint256) {
        if (testingTimeStamp != 0) return testingTimeStamp;
        return block.timestamp;
    }

    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }

    function transferToChain(uint256 chainId, uint256 amount) public {
        uint256 balance = balanceOf(msg.sender);
        require(amount <= balance, "Houston!");
        _burn(msg.sender, amount);
        uint256 nonce = TransferToChain.length;
        TransferToChain.push(
            TransferChain({
                user: msg.sender,
                chainId: chainId,
                amount: amount,
                nonce: nonce
            })
        );
        TransferToChainLatest = nonce;
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
        require(amount <= balanceOf(msg.sender), "Houston!");
        _cancelBuyBackGuarantee();
        return super.transfer(to, amount);
    }

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) public override returns (bool) {
        // Check Locked Coins
        require(amount <= balanceOf(from), "Houston!");
        _cancelBuyBackGuarantee();
        return super.transferFrom(from, to, amount);
    }

    function _beforeTokenTransfer(
        address _from,
        address _to,
        uint256 _amount
    ) internal override whenNotPaused {
        require(balanceOf(_from) >= _amount, "balance is not enough!");
        super._beforeTokenTransfer(_from, _to, _amount);
    }

    function _cancelBuyBackGuarantee() internal {
        if (_userInfoByAddress[msg.sender].buyBackGuarantee) {
            _userInfoByAddress[msg.sender].buyBackGuarantee = false;

            if (
                publicSales[20].unlockTime < getBlockTimeStamp() &&
                getBlockTimeStamp() <= publicSales[20].unlockTime + 90 days
            ) {
                Purchase[] memory up = _userPurchases[msg.sender];
                for (uint256 i = 0; i < up.length; i++) {
                    if (up[i].salesType == SalesType.PUBLIC && !up[i].buyBack) {
                        _transferableByFoundation +=
                            (up[i].totalUSD * 80) /
                            100;
                        buyBackFund -= (up[i].totalUSD * 80) / 100;
                    }
                }
            }
        }
    }

    function balanceOf(address who) public view override returns (uint256) {
        return
            super.balanceOf(who) - _checkLockedCoins(who, getBlockTimeStamp());
    }

    function balanceOfAt(address who, uint256 blockTimeStamp)
        public
        view
        returns (uint256)
    {
        return super.balanceOf(who) - _checkLockedCoins(who, blockTimeStamp);
    }

    /** Calculate */
    function _checkLockedCoins(address _who, uint256 blockTimeStamp)
        internal
        view
        returns (uint256)
    {
        uint256 uIndex = _userIndex[_who];
        if (uIndex == 0) {
            return 0;
        }

        // /// All coins free
        if (preSales[0].unlockTime + 10 days < blockTimeStamp) {
            return 0;
        }

        // /// All coins locked before end of Public Sales
        if (blockTimeStamp <= publicSales[20].unlockTime) {
            return _userInfoByAddress[_who].totalCoinsFromSales;
        }

        // Check user purchases history
        Purchase[] memory userPurchases = _userPurchases[_who];
        uint256 lockedCoins = 0;
        for (uint256 i = 0; i < userPurchases.length; i++) {
            if (!userPurchases[i].buyBack) {
                // unlock time has not pass
                if (
                    userPurchases[i].salesType == SalesType.PRESALE &&
                    blockTimeStamp < preSales[userPurchases[i].stage].unlockTime
                ) {
                    lockedCoins += userPurchases[i].totalCoin;
                }

                // unlock time has not pass
                if (
                    userPurchases[i].salesType == SalesType.PUBLIC &&
                    blockTimeStamp <
                    publicSales[userPurchases[i].stage].unlockTime
                ) {
                    lockedCoins += userPurchases[i].totalCoin;
                }

                // 10 days vesting for PreSale
                if (
                    userPurchases[i].salesType == SalesType.PRESALE &&
                    (preSales[userPurchases[i].stage].unlockTime <
                        blockTimeStamp &&
                        blockTimeStamp <
                        preSales[userPurchases[i].stage].unlockTime + 10 days)
                ) {
                    lockedCoins += _vestingCalculator(
                        preSales[userPurchases[i].stage].unlockTime,
                        userPurchases[i].totalCoin,
                        10,
                        blockTimeStamp
                    );
                }

                // 25 days vesting for PublicSale
                if (
                    userPurchases[i].salesType == SalesType.PUBLIC &&
                    (publicSales[userPurchases[i].stage].unlockTime <
                        blockTimeStamp &&
                        blockTimeStamp <
                        publicSales[userPurchases[i].stage].unlockTime +
                            25 days)
                ) {
                    lockedCoins += _vestingCalculator(
                        publicSales[userPurchases[i].stage].unlockTime,
                        userPurchases[i].totalCoin,
                        25,
                        blockTimeStamp
                    );
                }
            }
        }

        return lockedCoins;
    }

    function _vestingCalculator(
        uint256 _unlockTime,
        uint256 _totalCoin,
        uint256 _vestingDays,
        uint256 blockTimeStamp
    ) internal pure returns (uint256) {
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

    function changeSafeWallet(address walletAddress) public onlyOwner {
        SAFE_WALLET = walletAddress;
    }

    function transferTokensToSafeWallet(address tokenAddress)
        external
        onlyContractManagers
    {
        require(_isContract(address(tokenAddress)), "Houston!");

        uint256 blockTimeStamp = getBlockTimeStamp();

        ITrustedPayToken trustedPayToken = ITrustedPayToken(
            address(tokenAddress)
        );

        uint256 tokenBalance = trustedPayToken.balanceOf(address(this));

        uint256 transferable = tokenBalance;
        uint256 ptIndex = _payTokenIndex[tokenAddress];

        if (_payTokens[ptIndex].valid) {
            transferable =
                _transferableByFoundation -
                _totalTranferredToFoundation;

            if (publicSales[20].unlockTime + 90 days < blockTimeStamp) {
                transferable = tokenBalance;
            }

            if (tokenBalance < transferable) transferable = tokenBalance;
            _totalTranferredToFoundation += transferable;

            _payTokens[ptIndex].totalWithdrawn =
                _payTokens[ptIndex].totalWithdrawn +
                transferable;
        }

        trustedPayToken.transfer(SAFE_WALLET, transferable);
    }

    function transferCoinsToSafeWallet() external onlyContractManagers {
        payable(SAFE_WALLET).transfer(address(this).balance);
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
}
