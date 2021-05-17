// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "./libs/ownable.sol";
import "./libs/bep20.sol";
import "./libs/safe-math.sol";

import "./interfaces/wbnb.sol";

enum LotteryState {
    Ongoing,
    Completed,
    Closed
}

contract SafeRocketLotteryV1 is Ownable {
    using SafeMath for uint256;
    using SafeBEP20 for IBEP20;

    address constant internal _wbnb = address(0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c);

    IBEP20 public rewardsToken = IBEP20(0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c); // WBNB
    IBEP20 public ticketsToken = IBEP20(0x95AAC643E2760267cbE4c52b2BAc5505B9049a1E); // SROCKET

    address private constant burnAddress = address(0x000000000000000000000000000000000000dEaD);

    struct LotteryCombination {
        uint256 first;
        uint256 second;
        uint256 third;
        uint256 fourth;
    }
    
    struct LotteryInfo {
        uint256 count;
        uint256 price;
        uint256 pool;
        LotteryCombination combination;
        uint256 count_two;
        uint256 count_three;
        uint256 count_four;
        LotteryState status;
        uint256 timestamp;
    }

    struct LotteryEntry {
        address player;
        LotteryCombination combination;
    }

    uint256[] public lotteries;
    mapping(uint256 => LotteryInfo) public lotteryInfo;
    mapping(uint256 => LotteryEntry[]) public lotteryEntries;
    mapping(uint256 => mapping(address => LotteryCombination[])) public playerCombinations;

    mapping(address => uint256) private _balances;

    uint256 public lottery_current_id;
    uint256 public lottery_ticket_price;
    uint256 public lottery_duration;
    uint256 public lottery_prize_pool;
    uint256 public lottery_max_entries = 1000;
    uint256 public lottery_max_player_entries = 50;
    bool public lottery_active = false;
    bool public lottery_loop = true;

    uint256 private seed;

    uint256 public prize_pool_percentage = 95;
    uint256 private prize_pool_base = 100;

    uint256 private distribution_four = 75;
    uint256 private distribution_three = 20;
    uint256 private distribution_base = 100;
    
    address[] internal winners_four;
    address[] internal winners_three;
    address[] internal winners_two;
    uint256[] internal other_numbers;

    /**
    * event to signal lottery start
    */
    event LotteryStarted();

    /**
    * event to signal lottery entry
    */
    event LotteryEntered(address indexed player, LotteryCombination combination);

    /**
    * event for signaling lottery winner
    * @param lottery_id the current lottery identifier
    * @param amount amount of prize
    */
    event LotteryDistributed(uint256 indexed lottery_id, uint256 amount);

    /**
    * event for signaling burn of prize pool
    * @param amount amount of tokens burned
    */
    event LotteryBurned(uint256 amount);

    /**
    * event for signaling claim of rewards
    * @param account the beneficiary
    * @param amount of the rewards
    */
    event LotteryClaimed(address account, uint256 amount);

    constructor () public {
        lottery_duration = 12 hours;
        lottery_ticket_price = 1000000 * 10**9;
    }

    receive() external payable {
        require(msg.sender == address(_wbnb));
    }

    // *** EXTERNAL **** //

    function enter(uint256 amount, uint256[] memory entries) external {
        require(lottery_active, '!active');
        require(lotteryInfo[lottery_current_id].status == LotteryState.Ongoing, '!ongoing');
        require(block.timestamp < lotteryInfo[lottery_current_id].timestamp.add(lottery_duration), '!duration');
        require(amount > 0 && amount <= 10, '0 < amount <= 10');
        require(ticketsToken.balanceOf(msg.sender) >= lottery_ticket_price.mul(amount), '!balance');
        require(amount.mul(4) == entries.length, '!entries');
        require(entries.length % 4 == 0, '!entries');
        require(lotteryInfo[lottery_current_id].count.add(amount) <= lottery_max_entries, '!max entries');
        require(playerCombinations[lottery_current_id][msg.sender].length.add(amount) <= lottery_max_player_entries, '!max player entries');

        uint256 total_amount = lottery_ticket_price.mul(amount);

        uint256 position;
        LotteryCombination memory combination;
        for (uint256 i = 0; i < entries.length; i++) {
            require(entries[i] > 0, '!number');
            require(entries[i] <= 16, '!number');

            position = position + 1;
            uint256 number = entries[i];

            if (position == 1) {
                combination.first = number;
            } else if (position == 2) {
                combination.second = number;
            } else if (position == 3) {
                combination.third = number;
            } else if (position == 4) {
                combination.fourth = number;
            }

            if (position == 4) {
                require(
                    _all_unique_numbers(
                        combination.first, 
                        combination.second, 
                        combination.third, 
                        combination.fourth), 
                    '!unique'
                );
                lotteryInfo[lottery_current_id].count = lotteryInfo[lottery_current_id].count.add(1);
                lotteryEntries[lottery_current_id].push(LotteryEntry(msg.sender, combination));
                playerCombinations[lottery_current_id][msg.sender].push(combination);
                emit LotteryEntered(msg.sender, combination);
                position = 0;
                combination = LotteryCombination(0, 0, 0, 0);
            }
        }

        ticketsToken.safeTransferFrom(msg.sender, address(this), total_amount);
        ticketsToken.safeTransfer(burnAddress, ticketsToken.balanceOf(address(this)));
    }

    function draw() public returns (bool) {
        require(lottery_active, '!active');
        require(block.timestamp >= lotteryInfo[lottery_current_id].timestamp.add(lottery_duration) ||
        lotteryEntries[lottery_current_id].length == lottery_max_entries, '!draw');
        
        if (lotteryInfo[lottery_current_id].count == 0) {
            _reset();
            return false;
        }

        uint256 prize_pool = lottery_prize_pool.mul(prize_pool_percentage).div(prize_pool_base);
        uint256 next_prize_pool = lottery_prize_pool.sub(prize_pool);

        lotteryInfo[lottery_current_id].pool = prize_pool;

        uint256 count_four;
        uint256 count_three;
        uint256 count_two;

        LotteryCombination memory combination = _get_random_combination();
        for (uint256 i = 0; i < lotteryEntries[lottery_current_id].length; i++) {
            uint256 hits;
            if (
                lotteryEntries[lottery_current_id][i].combination.first == combination.first ||
                lotteryEntries[lottery_current_id][i].combination.first == combination.second ||
                lotteryEntries[lottery_current_id][i].combination.first == combination.third ||
                lotteryEntries[lottery_current_id][i].combination.first == combination.fourth
            ) {
                hits = hits.add(1);
            }

            if (
                lotteryEntries[lottery_current_id][i].combination.second == combination.first ||
                lotteryEntries[lottery_current_id][i].combination.second == combination.second ||
                lotteryEntries[lottery_current_id][i].combination.second == combination.third ||
                lotteryEntries[lottery_current_id][i].combination.second == combination.fourth
            ) {
                hits = hits.add(1);
            }

            if (
                lotteryEntries[lottery_current_id][i].combination.third == combination.first ||
                lotteryEntries[lottery_current_id][i].combination.third == combination.second ||
                lotteryEntries[lottery_current_id][i].combination.third == combination.third ||
                lotteryEntries[lottery_current_id][i].combination.third == combination.fourth
            ) {
                hits = hits.add(1);
            }

            if (
                lotteryEntries[lottery_current_id][i].combination.fourth == combination.first ||
                lotteryEntries[lottery_current_id][i].combination.fourth == combination.second ||
                lotteryEntries[lottery_current_id][i].combination.fourth == combination.third ||
                lotteryEntries[lottery_current_id][i].combination.fourth == combination.fourth
            ) {
                hits = hits.add(1);
            }

            if (hits == 4) {
                count_four = count_four.add(1);
                winners_four.push(lotteryEntries[lottery_current_id][i].player);
                continue;
            } else if (hits == 3) {
                count_three = count_three.add(1);
                winners_three.push(lotteryEntries[lottery_current_id][i].player);
                continue;
            } else if (hits == 2) {
                count_two = count_two.add(1);
                winners_two.push(lotteryEntries[lottery_current_id][i].player);
                continue;
            }
        }

        uint256 distribution_four_amount = prize_pool.mul(distribution_four).div(distribution_base);
        if (count_four > 0) {
            uint256 distribution_per_player = distribution_four_amount.div(count_four);
            for (uint256 i = 0; i < winners_four.length; i++) {
                _balances[winners_four[i]] = _balances[winners_four[i]].add(distribution_per_player);
            }
        } else {
            next_prize_pool = next_prize_pool.add(distribution_four_amount);
        }

        uint256 distribution_three_amount = prize_pool.mul(distribution_three).div(distribution_base);
        if (count_three > 0) {
            uint256 distribution_per_player = distribution_three_amount.div(count_three);
            for (uint256 i = 0; i < winners_three.length; i++) {
                _balances[winners_three[i]] = _balances[winners_three[i]].add(distribution_per_player);
            }
        } else {
            next_prize_pool = next_prize_pool.add(distribution_three_amount);
        }

        uint256 distribution_two_amount = prize_pool.sub(distribution_four_amount).sub(distribution_three_amount);
        if (count_two > 0) {
            uint256 distribution_per_player = distribution_two_amount.div(count_two);
            for (uint256 i = 0; i < winners_two.length; i++) {
                _balances[winners_two[i]] = _balances[winners_two[i]].add(distribution_per_player);
            }
        } else {
            next_prize_pool = next_prize_pool.add(distribution_two_amount);
        }

        lotteryInfo[lottery_current_id].combination = combination;
        lotteryInfo[lottery_current_id].count_four = count_four;
        lotteryInfo[lottery_current_id].count_three = count_three;
        lotteryInfo[lottery_current_id].count_two = count_two;
        lotteryInfo[lottery_current_id].status = LotteryState.Completed;

        emit LotteryDistributed(lottery_current_id, prize_pool);
        
        winners_four = new address[](0);
        winners_three = new address[](0);
        winners_two = new address[](0);
        other_numbers = new uint256[](0);

        lottery_prize_pool = next_prize_pool;

        if (lottery_loop && lottery_active) {
            _start();
        } else {
            _reset();
        }

        return true;
    }

    function claim() external {
        _claim(msg.sender);
    }

    function contribute(uint256 amount) external {
        lottery_prize_pool = lottery_prize_pool.add(amount);
        rewardsToken.safeTransferFrom(msg.sender, address(this), amount);
    }

    // *** INTERNAL **** //

    function _start() internal {
        uint256 id = lotteries.length;
        lotteries.push(id);
        lottery_active = true;
        lotteryInfo[id] = LotteryInfo(
            0, lottery_ticket_price, 0, LotteryCombination(0, 0, 0, 0), 0, 0, 0, LotteryState.Ongoing, block.timestamp
        );
        lottery_current_id = id;

        emit LotteryStarted();
    }

    function _reset() internal {
        lottery_active = false;
        lotteryInfo[lottery_current_id].status = LotteryState.Closed;
    }

    function _claim(address payable account) internal {
        require(_balances[account] > 0, '!balance');

        uint256 claimable = _balances[account];
        _balances[account] = 0;

        unwrap(claimable);
        account.transfer(claimable);
        emit LotteryClaimed(account, claimable);
    }

    function _all_unique_numbers(uint256 first, uint256 second, uint256 third, uint256 fourth) internal pure returns (bool) {
        if (first == second ||
            first == third ||
            first == fourth ||
            second == third ||
            third == fourth ||
            second == fourth
        ) {
            return false;
        }

        return true;
    }

    function _get_random_combination() internal returns (LotteryCombination memory) {
        LotteryCombination memory combination;
        
        uint256 first = _random();
        uint256 second = _random();
        uint256 third = _random();
        uint256 fourth = _random();

        if (_all_unique_numbers(first, second, third, fourth)) {
            combination.first = first;
            combination.second = second;
            combination.third = third;
            combination.fourth = fourth;
            
            return combination;
        } else {
            for (uint256 i = 1; i <= 16; i++) {
                if (i != first &&
                    i != second &&
                    i != third &&
                    i != fourth
                ) {
                    other_numbers.push(i);
                }
            }

            if (first == second ||
                first == third ||
                first == fourth
            ) {
                first = other_numbers[2];
                if (_all_unique_numbers(first, second, third, fourth)) {
                    combination.first = first;
                    combination.second = second;
                    combination.third = third;
                    combination.fourth = fourth;
                    
                    return combination;
                }
            }

            if (second == third ||
                second == fourth
            ) {
                second = other_numbers[3];
                if (_all_unique_numbers(first, second, third, fourth)) {
                    combination.first = first;
                    combination.second = second;
                    combination.third = third;
                    combination.fourth = fourth;
                    
                    return combination;
                }
            }

            if (third == fourth) {
                third = other_numbers[4];
                if (_all_unique_numbers(first, second, third, fourth)) {
                    combination.first = first;
                    combination.second = second;
                    combination.third = third;
                    combination.fourth = fourth;
                    
                    return combination;
                }
            }

            require(_all_unique_numbers(first, second, third, fourth), '!unique');
        }
    }

    function _random() internal returns (uint256) {
        uint256 random_number = uint256(keccak256(abi.encodePacked(block.difficulty, block.timestamp, seed))) % 16;
        random_number = random_number + 1;
        seed++;
        return random_number;
    }

    function unwrap(uint256 amount) internal {
        IWBNB(_wbnb).withdraw(amount);
    }

    // *** RESTRICTED **** //

    function start() public onlyOwner {
        require(!lottery_active, '!active');
        _start();
    }

    function close() external onlyOwner {
        require(lotteries.length > 0, '!lottery');
        lottery_loop = false;
        if (lottery_active) {
            draw();
        } else {
            _reset();
        }
    }

    function set_loop(bool _loop) external onlyOwner {
        lottery_loop = _loop;
    }

    function set_lottery_ticket_price(uint256 _lottery_ticket_price) external onlyOwner {
        require(!lottery_active, '!active');
        lottery_ticket_price = _lottery_ticket_price * 10**9;
    }

    function set_lottery_duration(uint256 _lottery_duration) external onlyOwner {
        require(!lottery_active, '!active');
        lottery_duration = _lottery_duration;
    }

    function set_prize_pool_percentage(uint256 _prize_pool_percentage) external onlyOwner {
        require(!lottery_active, '!active');
        require(_prize_pool_percentage > 0 && _prize_pool_percentage < prize_pool_base, '!invalid');
        prize_pool_percentage = _prize_pool_percentage;
    }

    function set_max_limits(uint256 _lottery_max_entries, uint256 _lottery_max_player_entries) external onlyOwner {
        require(!lottery_active, '!active');
        require(_lottery_max_entries > 0 && _lottery_max_player_entries > 0, '!invalid');
        lottery_max_entries = _lottery_max_entries;
        lottery_max_player_entries = _lottery_max_player_entries;
    }

    function set_percentages(uint256 _distribution_four, uint256 _distribution_three) external onlyOwner {
        require(_distribution_four > 0 && _distribution_three > 0, '!null');
        require(_distribution_four.add(_distribution_three) < distribution_base, '!invalid');
        distribution_four = _distribution_four;
        distribution_three = _distribution_three;
    }

    function set_seed(uint256 _seed) external onlyOwner {
        require(_seed > 0, '!seed');
        seed = _seed;
    }
    
    function salvage(address _token, uint256 amount) external onlyOwner {
        IBEP20(_token).safeTransfer(msg.sender, amount);
    }

    // *** VIEWS **** //

    function get_balance() public view returns (uint256) {
        return _balances[msg.sender];
    }

    function get_prize_pool() public view returns (uint256) {
        return lottery_prize_pool;
    }

    function get_entries() public view returns (uint256) {
        return lotteryInfo[lottery_current_id].count;
    }

    function get_latest_winning_combination() external view returns (LotteryCombination memory) {
        return lotteryInfo[lottery_current_id.sub(1)].combination;
    }

    function get_current_lottery() external view returns (LotteryInfo memory) {
        return lotteryInfo[lottery_current_id];
    }

    function get_current_lottery_start() external view returns (uint256 timestamp) {
        return lotteryInfo[lottery_current_id].timestamp;
    }

    function get_lottery_info(uint256 lottery_id) external view returns (LotteryInfo memory) {
        return lotteryInfo[lottery_id];
    }

    function get_current_lottery_entries() external view returns (LotteryCombination[] memory) {
        return playerCombinations[lottery_current_id][msg.sender];
    }

    function get_lottery_entries(uint256 lottery_id) external view returns (LotteryCombination[] memory) {
        return playerCombinations[lottery_id][msg.sender];
    }
}