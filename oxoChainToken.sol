// SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/// @custom:security-contact info@oxochain.com
contract OXOChainToken is ERC20, ERC20Burnable, Pausable, Ownable {
    struct Deposit {
        address user;
        address token;
        uint256 blockNumber;
        uint256 amount;
    }

    Deposit[] private userDeposits;

    mapping(address => uint256) private deposits;
    mapping(address => mapping(address => uint256)) private tokenDeposits;
    mapping(address => bool) public acceptedTokens;
    mapping(address => uint256) private _transferableBalance;
    address[] private _tokens = [
        0x55d398326f99059fF775485246999027B3197955, // USDT on BSC - Binance-Peg BSC-USD
        0x8AC76a51cc950d9822D68b83fE1Ad97B32Cd580d, // USDC on BSC - Binance-Peg USD Coin
        0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56, // BUSD on BSC - Binance-Peg BUSD Token
        0x23396cF899Ca06c4472205fC903bDB4de249D6fC, // UST on BSC - Wrapped UST Token
        0x1AF3F329e8BE154074D8769D1FFa4eE058B1DBc3, // DAI on BSC - Binance-Peg Dai Token
        0x14016E85a25aeb13065688cAFB43044C2ef86784, // TUSD on BSC - Binance-Peg TrueUSD Token
        0xb3c11196A4f3b1da7c23d9FB0A3dDE9c6340934F // USDP on BSC - Binance-Peg Pax Dollar Token
    ];

    constructor() ERC20("OXO Chain Token", "OXOt") {
        _initTokens();
    }

    function _initTokens() internal {
        for (uint256 i = 0; i < _tokens.length; i++) {
            acceptedTokens[_tokens[i]] = true;
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

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal override whenNotPaused {
        require(
            _transferableBalance[from] >= amount,
            "Your balance is not transferable!"
        );
        super._beforeTokenTransfer(from, to, amount);
    }

    function transferableBalanceOf(address _who) public view returns (uint256) {
        return _transferableBalance[_who];
    }

    /** ONLYOWNER */
    function addAcceptedToken(address _tokenAddress, bool _accept)
        external
        onlyOwner
        returns (bool)
    {
        acceptedTokens[_tokenAddress] = _accept;
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

    /** ONLYOWNER */

    function depositMoney(uint256 _amount, address _tokenAddress) external {
        require(acceptedTokens[_tokenAddress], "We do not accept that token!");
        IERC20 erc20Token = IERC20(address(_tokenAddress));
        require(erc20Token.allowance(msg.sender, address(this)) >= _amount);
        uint256 tokenBalance = erc20Token.balanceOf(msg.sender);
        if (tokenBalance > _amount) {
            erc20Token.transferFrom(msg.sender, address(this), _amount);
            deposits[msg.sender] += _amount;
            tokenDeposits[msg.sender][_tokenAddress] += _amount;
            userDeposits.push(
                Deposit({
                    user: msg.sender,
                    token: _tokenAddress,
                    blockNumber: block.number,
                    amount: _amount
                })
            );
        }
    }
}
