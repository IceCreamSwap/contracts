/*

https://icecreamswap.finance/

Telegram: https://t.me/IceCreamSwap

Twitter: https://twitter.com/SwapIceCream

*/

pragma solidity 0.6.12;

import './libs/math/SafeMath.sol';
import './libs/token/BEP20/IBEP20.sol';
import './libs/token/BEP20/SafeBEP20.sol';
import './libs/access/Ownable.sol';

import "./CreamToken.sol";
import "./MilkShake.sol";

// import "@nomiclabs/buidler/console.sol";

// MasterChef is the master of Cream. He can make Cream and he is a fair guy.
//
// Note that it's ownable and the owner wields tremendous power. The ownership
// will be transferred to a governance smart contract once CREAM is sufficiently
// distributed and the community can show to govern itself.
//
// Have fun reading it. Hopefully it's bug-free. God bless.
contract MasterChef is Ownable {
    using SafeMath for uint256;
    using SafeBEP20 for IBEP20;

    // Info of each user.
    struct UserInfo {
        uint256 amount;     // How many LP tokens the user has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.
        //
        // We do some fancy math here. Basically, any point in time, the amount of CREAMs
        // entitled to a user but is pending to be distributed is:
        //
        //   pending reward = (user.amount * pool.accCreamPerShare) - user.rewardDebt
        //
        // Whenever a user deposits or withdraws LP tokens to a pool. Here's what happens:
        //   1. The pool's `accCreamPerShare` (and `lastRewardBlock`) gets updated.
        //   2. User receives the pending reward sent to his/her address.
        //   3. User's `amount` gets updated.
        //   4. User's `rewardDebt` gets updated.
    }

    // Info of each pool.
    struct PoolInfo {
        IBEP20 lpToken;           // Address of LP token contract.
        uint256 allocPoint;       // How many allocation points assigned to this pool. CREAMs to distribute per block.
        uint256 lastRewardBlock;  // Last block number that CREAMs distribution occurs.
        uint256 accCreamPerShare; // Accumulated CREAMs per share, times 1e12. See below.
    }

    // The CREAM TOKEN!
    CreamToken public cream;
    // The milkshake TOKEN!
    MilkShake public milkshake;
    address public devFee;
    // CREAM tokens created per block.
    uint256 public creamPerBlock;
    // Bonus muliplier for early cream makers.
    uint256 public BONUS_MULTIPLIER = 1;
    uint256 public bonusEndBlock;

    // Info of each pool.
    PoolInfo[] public poolInfo;
    // Info of each user that stakes LP tokens.
    mapping (uint256 => mapping (address => UserInfo)) public userInfo;
    // Total allocation points. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint = 0;
    // The block number when CREAM mining starts.
    uint256 public startBlock;

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);

    constructor(
        CreamToken _cream,
        MilkShake _milkshake,
        address _devFee,
        uint256 _creamPerBlock,
        uint256 _startBlock,
        uint256 _multiplier
    ) public {
        cream = _cream;
        milkshake = _milkshake;

        devFee = _devFee;
        creamPerBlock = _creamPerBlock;
        startBlock = _startBlock;
        BONUS_MULTIPLIER = _multiplier;

        // staking pool
        poolInfo.push(PoolInfo({
            lpToken: _cream,
            allocPoint: 1000,
            lastRewardBlock: startBlock,
            accCreamPerShare: 0
        }));

        totalAllocPoint = 1000;

    }

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    // Add a new lp to the pool. Can only be called by the owner.
    // XXX DO NOT add the same LP token more than once. Rewards will be messed up if you do.
    function add(uint256 _allocPoint, IBEP20 _lpToken, bool _withUpdate) public onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        checkPoolDuplicate(_lpToken);
        uint256 lastRewardBlock = block.number > startBlock ? block.number : startBlock;
        totalAllocPoint = totalAllocPoint.add(_allocPoint);
        poolInfo.push(PoolInfo({
            lpToken: _lpToken,
            allocPoint: _allocPoint,
            lastRewardBlock: lastRewardBlock,
            accCreamPerShare: 0
        }));
        updateStakingPool();
    }
    // Detects whether the given pool already exists
    function checkPoolDuplicate(IBEP20 _lpToken) public {
        uint256 length = poolInfo.length;
        for (uint256 _pid = 0; _pid < length; _pid++) {
            require(poolInfo[_pid].lpToken != _lpToken, "add: existing pool");
        }
    }
    // Update the given pool's CREAM allocation point. Can only be called by the owner.
    function set(uint256 _pid, uint256 _allocPoint, bool _withUpdate) public onlyOwner validatePool(_pid){
        if (_withUpdate) {
            massUpdatePools();
        }
        uint256 prevAllocPoint = poolInfo[_pid].allocPoint;
        poolInfo[_pid].allocPoint = _allocPoint;
        if (prevAllocPoint != _allocPoint) {
            totalAllocPoint = totalAllocPoint.sub(prevAllocPoint).add(_allocPoint);
            updateStakingPool();
        }
    }

    function updateStakingPool() internal {
        uint256 length = poolInfo.length;
        uint256 points = 0;
        for (uint256 pid = 1; pid < length; ++pid) {
            points = points.add(poolInfo[pid].allocPoint);
        }
        if (points != 0) {
            points = points.div(3);
            totalAllocPoint = totalAllocPoint.sub(poolInfo[0].allocPoint).add(points);
            poolInfo[0].allocPoint = points;
        }
    }

    // Return reward multiplier over the given _from to _to block.
    function getMultiplier(uint256 _from, uint256 _to) public view returns (uint256) {
        return _to.sub(_from).mul(BONUS_MULTIPLIER);
    }

    // View function to see pending CREAMs on frontend.
    function pendingCream(uint256 _pid, address _user) external view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accCreamPerShare = pool.accCreamPerShare;
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (block.number > pool.lastRewardBlock && lpSupply != 0) {
            uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
            uint256 creamReward = multiplier.mul(creamPerBlock).mul(pool.allocPoint).div(totalAllocPoint);
            accCreamPerShare = accCreamPerShare.add(creamReward.mul(1e12).div(lpSupply));
        }
        return user.amount.mul(accCreamPerShare).div(1e12).sub(user.rewardDebt);
    }

    // Update reward variables for all pools. Be careful of gas spending!
    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }


    // Update reward variables of the given pool to be up-to-date.
    function updatePool(uint256 _pid) public validatePool(_pid) {
        PoolInfo storage pool = poolInfo[_pid];
        if (block.number <= pool.lastRewardBlock) {
            return;
        }
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (lpSupply == 0) {
            pool.lastRewardBlock = block.number;
            return;
        }
        uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
        uint256 creamReward = multiplier.mul(creamPerBlock).mul(pool.allocPoint).div(totalAllocPoint);

        // fix: to avoid printing 105%
        uint256 creamDevReward = creamReward.div(20); // dev fee 5%
        uint256 creamUserReward = creamReward.sub(creamDevReward);
        cream.mint(devFee, creamDevReward );
        cream.mint(address(milkshake), creamUserReward);
        pool.accCreamPerShare = pool.accCreamPerShare.add(creamReward.mul(1e12).div(lpSupply));
        pool.lastRewardBlock = block.number;
    }

    // Deposit LP tokens to MasterChef for CREAM allocation.
    function deposit(uint256 _pid, uint256 _amount) public validatePool(_pid){

        require (_pid != 0, 'deposit CREAM by staking');

        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        updatePool(_pid);

        if (user.amount > 0) {
            uint256 pending = user.amount.mul(pool.accCreamPerShare).div(1e12).sub(user.rewardDebt);
            if(pending > 0) {
                safeCreamTransfer(msg.sender, pending);
            }
        }
        if (_amount > 0) {
            pool.lpToken.safeTransferFrom(address(msg.sender), address(this), _amount);
            user.amount = user.amount.add(_amount);
        }
        user.rewardDebt = user.amount.mul(pool.accCreamPerShare).div(1e12);
        emit Deposit(msg.sender, _pid, _amount);
    }

    // Withdraw LP tokens from MasterChef.
    function withdraw(uint256 _pid, uint256 _amount) public validatePool(_pid) {

        require (_pid != 0, 'withdraw CREAM by unstaking');
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.amount >= _amount, "withdraw: not good");

        updatePool(_pid);
        uint256 pending = user.amount.mul(pool.accCreamPerShare).div(1e12).sub(user.rewardDebt);
        if(pending > 0) {
            safeCreamTransfer(msg.sender, pending);
        }
        if(_amount > 0) {
            user.amount = user.amount.sub(_amount);
            pool.lpToken.safeTransfer(address(msg.sender), _amount);
        }
        user.rewardDebt = user.amount.mul(pool.accCreamPerShare).div(1e12);
        emit Withdraw(msg.sender, _pid, _amount);
    }

    // Stake CREAM tokens to MasterChef
    function enterStaking(uint256 _amount) public {
        PoolInfo storage pool = poolInfo[0];
        UserInfo storage user = userInfo[0][msg.sender];
        updatePool(0);
        if (user.amount > 0) {
            uint256 pending = user.amount.mul(pool.accCreamPerShare).div(1e12).sub(user.rewardDebt);
            if(pending > 0) {
                safeCreamTransfer(msg.sender, pending);
            }
        }
        if(_amount > 0) {
            pool.lpToken.safeTransferFrom(address(msg.sender), address(this), _amount);
            user.amount = user.amount.add(_amount);
        }
        user.rewardDebt = user.amount.mul(pool.accCreamPerShare).div(1e12);

        milkshake.mint(msg.sender, _amount);
        emit Deposit(msg.sender, 0, _amount);
    }

    // Withdraw CREAM tokens from STAKING.
    function leaveStaking(uint256 _amount) public {
        PoolInfo storage pool = poolInfo[0];
        UserInfo storage user = userInfo[0][msg.sender];
        require(user.amount >= _amount, "withdraw: not good");
        updatePool(0);
        uint256 pending = user.amount.mul(pool.accCreamPerShare).div(1e12).sub(user.rewardDebt);
        if(pending > 0) {
            safeCreamTransfer(msg.sender, pending);
        }
        if(_amount > 0) {
            user.amount = user.amount.sub(_amount);
            pool.lpToken.safeTransfer(address(msg.sender), _amount);
        }
        user.rewardDebt = user.amount.mul(pool.accCreamPerShare).div(1e12);

        milkshake.burn(msg.sender, _amount);
        emit Withdraw(msg.sender, 0, _amount);
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        if(_pid == 0) {
            milkshake.burn(msg.sender, user.amount );
        }
        pool.lpToken.safeTransfer(address(msg.sender), user.amount);
        emit EmergencyWithdraw(msg.sender, _pid, user.amount);
        user.amount = 0;
        user.rewardDebt = 0;
    }

    // Safe cream transfer function, just in case if rounding error causes pool to not have enough CREAMs.
    function safeCreamTransfer(address _to, uint256 _total) internal {
        milkshake.safeCreamTransfer(_to, _total);
    }
    modifier validatePool(uint256 _pid) {
        require(_pid < poolInfo.length, "validatePool: pool exists?");
        _;
    }


    function updateMultiplier(uint256 _multiplierNumber) external onlyOwner {
        BONUS_MULTIPLIER = _multiplierNumber;
    }

    function updateBonus(uint256 _bonusEndBlock) external onlyOwner {
        bonusEndBlock = _bonusEndBlock;
    }

    function updateCreamPerBlock(uint256 _creamPerBlock) external onlyOwner {
        creamPerBlock = _creamPerBlock;
    }

    function setDevFee(address _devFee) external onlyOwner {
        devFee = _devFee;
    }

    // allow to change tax treasure via timelock
    function setTaxAddr(address _taxTo) external onlyOwner {
        milkshake.setTaxAddr(_taxTo);
    }

    // allow to change tax via timelock
    function setTax(uint256 _tax) external onlyOwner {
        require( _tax <= 100, "can't be more than 10%" );
        milkshake.setTax(_tax);
    }
}
