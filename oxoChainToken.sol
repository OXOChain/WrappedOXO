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
        address token;
        uint256 blockNumber;
        uint256 amount;
    }

    struct TokenSale {
        uint256 salesDate;
        uint256 oxoAmount;
        uint256 usdAmount;
        uint256 usdPerOXO;
        uint256 unlockTime;
    }

    address[] private allUsers;
    mapping(address => uint256) private _userIndex;

    struct UserInfo {
        address user;
        Deposit[] Deposits;
        TokenSale[] TokenSales;
    }

    mapping(uint256 => UserInfo) private _userRecords;
    mapping(address => uint256) private _usdBalances;

    mapping(address => mapping(address => uint256))
        private _payTokenDepositsForUser;
    mapping(address => uint256) private _payTokenDepositsTotal;

    mapping(address => bool) public acceptedPayTokens;

    address[] private _payTokens = [
        0x55d398326f99059fF775485246999027B3197955, // USDT on BSC - Binance-Peg BSC-USD
        0x8AC76a51cc950d9822D68b83fE1Ad97B32Cd580d, // USDC on BSC - Binance-Peg USD Coin
        0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56, // BUSD on BSC - Binance-Peg BUSD Token
        0x23396cF899Ca06c4472205fC903bDB4de249D6fC, // UST on BSC - Wrapped UST Token
        0x1AF3F329e8BE154074D8769D1FFa4eE058B1DBc3, // DAI on BSC - Binance-Peg Dai Token
        0x14016E85a25aeb13065688cAFB43044C2ef86784, // TUSD on BSC - Binance-Peg TrueUSD Token
        0xb3c11196A4f3b1da7c23d9FB0A3dDE9c6340934F // USDP on BSC - Binance-Peg Pax Dollar Token
    ];

    constructor() ERC20("OXO Chain Token", "OXOt") {
        _initPayTokens();
        allUsers.push();
    }

    function _initPayTokens() internal {
        for (uint256 i = 0; i < _payTokens.length; i++) {
            acceptedPayTokens[_payTokens[i]] = true;
        }
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
    function addAcceptedPayToken(address _tokenAddress)
        external
        onlyOwner
        returns (bool)
    {
        acceptedPayTokens[_tokenAddress] = true;
        return true;
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

    /** ONLYOWNER */

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
        // Check user token balance
        uint256 tokenBalance = erc20Token.balanceOf(msg.sender);

        if (tokenBalance > _amount) {
            // Check/get user record
            uint256 uIndex = _getUserIndex(msg.sender);

            // Transfer USD(token) to this SC
            erc20Token.transferFrom(msg.sender, address(this), _amount);

            // add amount to User USD Balance in SC
            _usdBalances[msg.sender] += _amount;
            _payTokenDepositsForUser[msg.sender][_tokenAddress] += _amount;
            _payTokenDepositsTotal[_tokenAddress] += _amount;
            _userRecords[uIndex].Deposits.push(
                Deposit({
                    user: msg.sender,
                    token: _tokenAddress,
                    blockNumber: block.number,
                    amount: _amount
                })
            );
        }
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
