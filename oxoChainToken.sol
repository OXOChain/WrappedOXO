// SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;

import "./ERC20.sol";
import "./ERC20Burnable.sol";
import "./Pausable.sol";
import "./Ownable.sol";

// import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
// import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
// import "@openzeppelin/contracts/security/Pausable.sol";
// import "@openzeppelin/contracts/access/Ownable.sol";
/// @custom:security-contact info@oxochain.com
contract OXOChainToken is ERC20, ERC20Burnable, Pausable, Ownable {
    bool allUnlocked = false;

    struct Deposit {
        address user;
        address payToken;
        uint256 amount;
        uint256 blockNumber;
    }

    struct TokenSale {
        uint256 saleTime; // block.timestamp
        uint256 amount; // oxo
        uint256 price; // 0.65
        uint256 total; // USD
        uint256 unlockTime; // first unlock
    }

    address[] private allUsers;
    mapping(address => uint256) private _userIndex;

    struct UserInfo {
        address user;
        bool buyBackGuarantee;
        Deposit[] Deposits;
        TokenSale[] TokenSales;
    }

    mapping(uint256 => UserInfo) private _userRecords;

    uint256 private _totalDeposits;
    mapping(address => uint256) private _totalOfUserDeposits;

    mapping(address => mapping(address => uint256))
        private _totalOfUserDepositsPerPayToken;

    mapping(address => uint256) private _totalOfPayTokenDeposits;

    mapping(address => bool) public acceptedPayTokens;
    mapping(address => uint256) public payTokenIndex;

    struct payToken {
        bytes32 name;
        address contractAddress;
        uint256 decimals;
    }

    payToken[] private _payTokens = [
        (
            "USDT on BSC - Binance-Peg BSC-USD",
            0x55d398326f99059fF775485246999027B3197955,
            18
        ),
        (
            "USDC on BSC - Binance-Peg USD Coin",
            0x8AC76a51cc950d9822D68b83fE1Ad97B32Cd580d,
            18
        ),
        (
            "BUSD on BSC - Binance-Peg BUSD Token",
            0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56,
            18
        ),
        (
            "DAI on BSC - Binance-Peg Dai Token",
            0x1AF3F329e8BE154074D8769D1FFa4eE058B1DBc3,
            18
        ),
        (
            "TUSD on BSC - Binance-Peg TrueUSD Token",
            0x14016E85a25aeb13065688cAFB43044C2ef86784,
            18
        ),
        (
            "USDP on BSC - Binance-Peg Pax Dollar Token",
            0xb3c11196A4f3b1da7c23d9FB0A3dDE9c6340934F,
            18
        ),
        (
            "UST on BSC - Wrapped UST Token",
            0x23396cF899Ca06c4472205fC903bDB4de249D6fC,
            18
        ),
        (
            "vUSDC on BSC - Venus USDC",
            0xecA88125a5ADbe82614ffC12D0DB554E2e2867C8,
            8
        ),
        (
            "vUSDT on BSC - Venus USDT",
            0xfD5840Cd36d94D7229439859C0112a4185BC0255,
            8
        ),
        (
            "vDAI on BSC - Venus DAI",
            0x334b3eCB4DCa3593BCCC3c7EBD1A1C1d1780FBF1,
            8
        )
    ];

    struct PrivateSale {
        uint256 price;
        uint256 totalSupply;
        uint256 min;
        uint256 max;
        uint256 unlockTime;
    }

    PrivateSale[] privateSales;

    constructor() ERC20("OXO Chain Token", "OXOt") {
        _initPayTokens();
        _initPrivateSale();
        allUsers.push();
    }

    function _initPayTokens() internal {
        for (uint256 i = 0; i < _payTokens.length; i++) {
            acceptedPayTokens[_payTokens[i].contractAddress] = true;
            payTokenIndex[_payTokens[i].contractAddress] = i;
        }
    }

    function _initPrivateSale() internal {
        privateSales[0] = PrivateSale({
            price: 40,
            totalSupply: 4800000,
            min: 20000,
            max: 500000,
            unlockTime: 360
        });
        privateSales[1] = PrivateSale({
            price: 55,
            totalSupply: 4800000,
            min: 5000,
            max: 350000,
            unlockTime: 270
        });
        privateSales[2] = PrivateSale({
            price: 70,
            totalSupply: 4800000,
            min: 2000,
            max: 400000,
            unlockTime: 180
        });
    }

    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
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
        if (allUnlocked) {
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
    function addEditPayToken(address _tokenAddress, string memory name)
        external
        onlyOwner
        returns (bool)
    {
        require(_tokenAddress.isContract, "This address is not valid!");
        uint256 ptIndex = payTokenIndex[_tokenAddress];
        if (ptIndex == 0) {
            acceptedPayTokens[_tokenAddress] = true;
            _payTokens.push(
                payToken({
                    name: name,
                    contractAddress: _tokenAddress,
                    decimals: decimals
                })
            );
            ptIndex = _payTokens.length;
            payTokenIndex[_tokenAddress] = ptIndex;
            return true;
        } else {
            _payTokens[ptIndex] = payToken({
                name: name,
                contractAddress: _tokenAddress,
                decimals: decimals
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
        allUnlocked = true;
    }

    /** *************** */

    /** Deposit Money */
    function depositMoney(uint256 _amount, address _tokenAddress) external {
        require(
            acceptedPayTokens[_tokenAddress],
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

    function BuyToken(uint256 round, uint256 amount) public returns (bool) {
        return true;
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
