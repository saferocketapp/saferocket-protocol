// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "./saferocket.sol";

contract SafeRocketController is Ownable {
    using SafeBEP20 for IBEP20;
    using SafeMath for uint256;
    using Address for address;

    SafeRocket public safeRocket = SafeRocket(0x95AAC643E2760267cbE4c52b2BAc5505B9049a1E); // fill with address
    IBEP20 public immutable liquidityPair;

    address private constant burnAddress = address(0x000000000000000000000000000000000000dEaD);

    uint256 public foundationFee = 50;
    uint256 public foundationFeeMax = 50;
    uint256 private foundationFeeBase = 1000;

    constructor () public {
        liquidityPair = IBEP20(safeRocket.pancakePair());
    }

    event LiquidityBurn(uint256 burned, uint256 foundation);

    // PROTOCOL FUNCTIONS

    function excludeFromReward(address account) external onlyOwner {
        safeRocket.excludeFromReward(account);
    }

    function includeInReward(address account) external onlyOwner {
        safeRocket.includeInReward(account);
    }

    function excludeFromFee(address account) external onlyOwner {
        safeRocket.excludeFromFee(account);
    }

    function includeInFee(address account) external onlyOwner {
        safeRocket.includeInFee(account);
    }

    function setTaxFeePercent(uint256 taxFee) external onlyOwner {
        safeRocket.setTaxFeePercent(taxFee);
    }

    function setLiquidityFeePercent(uint256 liquidityFee) external onlyOwner {
        safeRocket.setLiquidityFeePercent(liquidityFee);
    }

    function setMaxTxPercent(uint256 maxTxPercent) external onlyOwner {
        safeRocket.setMaxTxPercent(maxTxPercent);
    }

    function setSwapAndLiquifyEnabled(bool _enabled) external onlyOwner {
        safeRocket.setSwapAndLiquifyEnabled(_enabled);
    }

    function setLotteryAddress(address payable _lottery) external onlyOwner {
        safeRocket.setLotteryAddress(_lottery);
    }

    function updateMinTokensBeforeSwap(uint256 minTokensBeforeSwap) external onlyOwner {
        safeRocket.updateMinTokensBeforeSwap(minTokensBeforeSwap);
    }

    function enableTrading() external onlyOwner {
        safeRocket.enableTrading();
    }

    function toggleLottery() external onlyOwner {
        safeRocket.toggleLottery();
    }

    // CONTROLLER FUNCTIONS

    function burnLiquidity() external onlyOwner {
        uint256 balance = liquidityPair.balanceOf(address(this));
        if (balance > 0) {
            uint256 foundationAmount = balance.mul(foundationFee).div(foundationFeeBase);
            liquidityPair.safeTransfer(burnAddress, balance.sub(foundationAmount));
            liquidityPair.safeTransfer(owner(), foundationAmount);
            emit LiquidityBurn(balance, foundationAmount);
        }
    }

    // OWNER FUNCTIONS

    function setFoundationFee(uint256 _foundationFee) external onlyOwner {
        require(_foundationFee <= foundationFeeMax, '!maxFee');
        foundationFee = _foundationFee;
    }

    function salvage(address token, uint256 amount) external onlyOwner {
        require(token != address(liquidityPair), '!lpToken');
        IBEP20(token).safeTransfer(owner(), amount);
    }
}