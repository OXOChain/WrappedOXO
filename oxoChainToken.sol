// SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;

import "./ERC20.sol";
import "./ERC20Burnable.sol";
import "./Pausable.sol";
import "./Ownable.sol";

/// @custom:security-contact info@oxochain.com
contract OXOChainToken is ERC20, ERC20Burnable, Pausable, Ownable {
    bool public _unlockAll = false;
    bool public _canBeDeposited = true;

    struct Deposit {
        address user;
        address payToken;
        uint256 amount;
        uint256 blockNumber;
    }

    struct TokenSale {
        uint256 saleTime; // block.timestamp
        uint256 amount; // OXOt
        uint256 price; // 0.65 * 1e18
        uint256 total; // USD
        uint256 unlockTime; // first unlock
    }

    address[] public allUsers;
    mapping(address => uint256) public _userIndex;

    struct UserInfo {
        address user;
        bool buyBackGuarantee;
        Deposit[] Deposits;
        TokenSale[] TokenSales;
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
        uint256 unlockTime;
        uint256 soldCoins;
    }

    PrivateSale[] public privateSales;

    struct PublicSale {
        uint256 price;
        uint256 totalCoins;
        uint256 min;
        uint256 max;
        uint256 unlockTime;
        uint256 soldCoins;
    }

    PublicSale[] public publicSales;

    constructor() ERC20("OXO Chain Token", "OXOt") {
        _initPayTokens();
        allUsers.push();
    }

    function _initPayTokens() internal {
        _payTokens.push(
            payToken("USDT: B-Peg", 0x55d398326f99059fF775485246999027B3197955)
        );

        _payTokens.push(
            payToken("USDC: B-Peg", 0x8AC76a51cc950d9822D68b83fE1Ad97B32Cd580d)
        );

        _payTokens.push(
            payToken("BUSD: B-Peg", 0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56)
        );

        _payTokens.push(
            payToken("DAI: B-Peg", 0x1AF3F329e8BE154074D8769D1FFa4eE058B1DBc3)
        );

        _payTokens.push(
            payToken("TUSD: B-Peg", 0x14016E85a25aeb13065688cAFB43044C2ef86784)
        );

        _payTokens.push(
            payToken("USDP: B-Peg", 0xb3c11196A4f3b1da7c23d9FB0A3dDE9c6340934F)
        );

        for (uint256 i = 0; i < _payTokens.length; i++) {
            acceptedPayTokens[_payTokens[i].contractAddress] = true;
            payTokenIndex[_payTokens[i].contractAddress] = i;
        }
    }

    function _initPrivateSales() public onlyOwner {
        privateSales.push(
            PrivateSale({
                price: 0.040 * 1e18,
                totalCoins: 4800000 * 1e18,
                min: 20000 * 1e18,
                max: 500000 * 1e18,
                unlockTime: 360 days,
                soldCoins: 0
            })
        );
        privateSales.push(
            PrivateSale({
                price: 0.055 * 1e18,
                totalCoins: 4800000 * 1e18,
                min: 5000 * 1e18,
                max: 350000 * 1e18,
                unlockTime: 270 days,
                soldCoins: 0
            })
        );
        privateSales.push(
            PrivateSale({
                price: 0.070 * 1e18,
                totalCoins: 4800000 * 1e18,
                min: 2000 * 1e18,
                max: 400000 * 1e18,
                unlockTime: 180 days,
                soldCoins: 0
            })
        );
    }

    function _initPublicSales() public onlyOwner {
        publicSales.push(
            PublicSale({
                price: 0.10 * 1e18,
                totalCoins: 13600000 * 1e18,
                min: 500 * 1e18,
                max: 500000 * 1e18,
                unlockTime: 161 days,
                soldCoins: 0
            })
        );

        for (uint256 i = 1; i <= 20; i++) {
            uint256 _totalCoins = (7500000 - ((i - 1) * 200000)) * 1e18;
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

            uint256 _days = 153;
            _days = _days - ((i - 1) * 8);
            _days = _days * 1 days;

            publicSales.push(
                PublicSale({
                    price: _price,
                    totalCoins: _totalCoins,
                    min: 100 * 1e18,
                    max: 500000 * 1e18,
                    unlockTime: _days,
                    soldCoins: 0
                })
            );
        }
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
    function addEditPayToken(
        address _tokenAddress,
        string memory _name,
        uint8 _decimals
    ) external onlyOwner returns (bool) {
        require(_decimals == 18, "Only 18 decimals stable USD tokens");
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
        require(_canBeDeposited, "You can not deposit");
        require(
            acceptedPayTokens[_tokenAddress],
            "We do not accept this ERC20 token!"
        );

        IERC20 erc20Token = IERC20(address(_tokenAddress));

        // uint256 ptIndex = payTokenIndex[_tokenAddress];
        // uint8 payTokenDecimals = _payTokens[ptIndex].decimals;
        // uint256 _amountFixDecimal = _amount;
        // if (payTokenDecimals != 18) {
        //     _amountFixDecimal = (_amount * 10 ** payTokenDecimals) / 1e18;
        // }

        // Firstly checking user approve result
        require(
            erc20Token.allowance(msg.sender, address(this)) >= _amount,
            "Houston, You do not approve this amount for transfer to us"
        );
        // Check user's payToken balance
        uint256 tokenBalance = erc20Token.balanceOf(msg.sender);

        if (tokenBalance > _amount) {
            // get/create user record
            uint256 uIndex = _getUserIndex(msg.sender);

            // Transfer payToken to US
            erc20Token.transferFrom(msg.sender, address(this), _amount);

            // add amount to User USD Balance in SC
            _totalDeposits += _amount; // Total Deposits
            _totalOfUserDeposits[msg.sender] += _amount; // The total of all deposits of the user
            _totalOfUserDepositsPerPayToken[msg.sender][
                _tokenAddress
            ] += _amount; // User's PayToken Deposits by Type
            _totalOfPayTokenDeposits[_tokenAddress] += _amount; // Total PayToken Deposits by Type
            _userRecords[uIndex].Deposits.push(
                Deposit({
                    user: msg.sender,
                    payToken: _tokenAddress,
                    amount: _amount,
                    blockNumber: block.number
                })
            );
        }
    }

    function BuyToken(uint256 round, uint256 amount)
        public
        view
        returns (uint256)
    {
        uint256 don = (amount / privateSales[round].price) * 1e18;
        return don;
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
