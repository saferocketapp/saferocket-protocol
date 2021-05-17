// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "./libs/ownable.sol";
import "./libs/bep20.sol";
import "./libs/safe-math.sol";

contract AirDrop is Ownable {
    using SafeMath for uint256;
    using SafeBEP20 for IBEP20;

    IBEP20 internal _token;

    event FailedTransfer(address indexed to, uint256 value);

    // this function can be used when you want to send same number of tokens to all the recipients
    function sendUniformAmount(address token, address[] memory dests, uint256 amount) onlyOwner external {
        require (token != address(0) && amount > 0, "Airdrop: invalid parameters");
        _token = IBEP20(token);

        uint256 i = 0;
        while (i < dests.length) {
            _send(dests[i], amount);
            i++;
        }
    }  

    function sendCustomAmount(address token, address[] memory dests, uint256[] memory amounts) onlyOwner external {
        require (token != address(0), "Airdrop: invalid parameters");
        require (dests.length == amounts.length, "Airdrop: invalid parameters");
        _token = IBEP20(token);

        uint256 i = 0;
        while (i < dests.length) {
            _send(dests[i], amounts[i]);
            i++;
        }
    }  

    function _send(address recipient, uint256 amount) internal {
        if (recipient == address(0)) return;

        if(_token.balanceOf(address(this)) >= amount) {
            _token.safeTransfer(recipient, amount);
        } else {
            emit FailedTransfer(recipient, amount); 
        }
    }   

    function salvage(address token) external onlyOwner {
        uint256 balance = IBEP20(token).balanceOf(address(this));
        require (balance > 0);
        IBEP20(token).safeTransfer(owner(), balance);
    }
}