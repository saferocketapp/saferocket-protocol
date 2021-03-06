// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "./libs/bep20.sol";
import "./libs/safe-math.sol";
import "./libs/ownable.sol";

/**
 * @dev A token holder contract that will allow a beneficiary to extract the
 * tokens after a given release time.
 *
 * Useful for simple vesting schedules like "advisors get all of their tokens
 * after 1 year".
 */
contract SafeRocketTokenTimelock is Ownable {
    using SafeMath for uint256;
    using SafeBEP20 for IBEP20;

    // ERC20 basic token contract being held
    IBEP20 private _token;

    // beneficiary of tokens after they are released
    address private _beneficiary;

    // timestamp when token release is enabled
    uint256 private _releaseTime;

    // minimum release time
    uint256 private _minReleaseTime = 365 days;

    constructor (address beneficiary_, uint256 releaseTime_, address token_) public {
        // solhint-disable-next-line not-rely-on-time
        require(releaseTime_ > block.timestamp, "TokenTimelock: release time is before current time");
        require(releaseTime_ > block.timestamp.add(_minReleaseTime), "TokenTimelock: release time below minimum");
        _beneficiary = beneficiary_;
        _releaseTime = releaseTime_;
        _token = IBEP20(token_);
    }

    /**
     * @return the token being held.
     */
    function token() public view returns (IBEP20) {
        return _token;
    }

    /**
     * @return the beneficiary of the tokens.
     */
    function beneficiary() public view returns (address) {
        return _beneficiary;
    }

    /**
     * @return the time when the tokens are released.
     */
    function releaseTime() public view returns (uint256) {
        return _releaseTime;
    }

    /**
     * @notice Transfers tokens held by timelock to beneficiary.
     */
    function release() public virtual {
        // solhint-disable-next-line not-rely-on-time
        require(block.timestamp >= _releaseTime, "TokenTimelock: current time is before release time");

        uint256 amount = _token.balanceOf(address(this));
        require(amount > 0, "TokenTimelock: no tokens to release");

        _token.safeTransfer(_beneficiary, amount);
    }

    // *** MODIFIERS ***

    modifier restricted {
        require(
            msg.sender == owner(),
            '!restricted'
        );

        _;
    }
}