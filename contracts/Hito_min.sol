pragma solidity 0.8.2;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";


interface aaveMin {
    struct ReserveConfigurationMap {
        //bit 0-15: LTV
        //bit 16-31: Liq. threshold
        //bit 32-47: Liq. bonus
        //bit 48-55: Decimals
        //bit 56: Reserve is active
        //bit 57: reserve is frozen
        //bit 58: borrowing is enabled
        //bit 59: stable rate borrowing enabled
        //bit 60-63: reserved
        //bit 64-79: reserve factor
        uint256 data;
  }

  struct UserConfigurationMap {
    uint256 data;
  }

  enum InterestRateMode {NONE, STABLE, VARIABLE}
    struct ReserveData {
        //stores the reserve configuration
        ReserveConfigurationMap configuration;
        //the liquidity index. Expressed in ray
        uint128 liquidityIndex;
        //variable borrow index. Expressed in ray
        uint128 variableBorrowIndex;
        //the current supply rate. Expressed in ray
        uint128 currentLiquidityRate;
        //the current variable borrow rate. Expressed in ray
        uint128 currentVariableBorrowRate;
        //the current stable borrow rate. Expressed in ray
        uint128 currentStableBorrowRate;
        uint40 lastUpdateTimestamp;
        //tokens addresses
        address aTokenAddress;
        address stableDebtTokenAddress;
        address variableDebtTokenAddress;
        //address of the interest rate strategy
        address interestRateStrategyAddress;
        //the id of the reserve. Represents the position in the list of the active reserves
        uint8 id;
  }
  
    function deposit(address asset, uint256 amount, address onBehalfOf, uint16 referralCode) external;
    function withdraw(address asset, uint256 amount, address to) external;
    function getReserveData(address asset) external view returns (ReserveData memory);
}


contract HITO_MIN is Initializable {
    
    uint256 MAX_INT = 2**256-1;
    
    struct MEILENSTEIN {
        string hash;
        uint256 meilensteinDays;
        uint256 rewardAmount;
    }
    
    uint16 currentMeilenstein = 0;
    
    address public owner;
    IERC20 public asset;
    IERC20 public aToken;
    IERC20 public rewardToken;
    
    aaveMin.ReserveData reserveData;
    aaveMin lend;
    
    mapping(address=>uint256) public investments;
    mapping(address=>uint256) public userRewards;
    uint256 public totalInvestments = 0;
    uint256 public totalRewards = 0;
    
    uint256 public startDate = MAX_INT;
    uint256 public fundingPeriod;
    MEILENSTEIN public meilenstein;

    modifier onlyOwner {
        require(msg.sender == owner, 'only owner can call this function');
        _;
    }
    
    modifier isFundingPhase {
        require(
            block.timestamp >= startDate && block.timestamp <= startDate + fundingPeriod, 'funding phase not started or over'
        );
        _;
    }
    
    modifier isActive() {
        require(startDate != MAX_INT, 'contract inactive');
        _;
    }
    
    modifier allowance(uint256 amount) {
        if(asset.allowance(address(this), address(lend)) < amount) asset.approve(address(lend), MAX_INT);
        _;
    }
    
    constructor() {
        owner = msg.sender;
    }
    
    function initialize(
        address asset_, 
        address aaveLendingPool,
        address rewardToken_, 
        uint256 amountReward,
        uint16 fundingPeriodDays,
        MEILENSTEIN memory meilenstein_
        
        ) public initializer onlyOwner {
            
        asset = IERC20(asset_);
        lend = aaveMin(aaveLendingPool);
        reserveData = lend.getReserveData(address(asset));
        aToken = IERC20(reserveData.aTokenAddress);
        rewardToken = IERC20(rewardToken_);
        
        require(rewardToken.allowance(msg.sender, address(this)) >= amountReward, 'rewardToken allowance not set');
        require(rewardToken.balanceOf(msg.sender) >= amountReward, 'user rewardToken balance too low');
        
        rewardToken.transferFrom(msg.sender, address(this), amountReward);
        
        fundingPeriod = fundingPeriodDays * 1 days;
        
        
        meilenstein = meilenstein_;
    }
    
    function init() public onlyOwner {
        initialize(
            0xe22da380ee6B445bb8273C81944ADEB6E8450422, // asset
            0xE0fBa4Fc209b4948668006B2bE61711b7f465bAe, // pool
            0xC02011B1A74354AAbd50FA961ED157E5700e8b98, // reward token
            20000000000000000000000000,   // reward amount :20M
            7,                          // funding days
            MEILENSTEIN("abc123", 7, 1) // meilenstein
            );
            start();
    }
    
    function start() public onlyOwner {
            startDate = block.timestamp;
    }
    
    function deposit(uint256 amount) public isActive isFundingPhase allowance(amount) {

        require(asset.allowance(msg.sender, address(this)) >= amount, 'allowance not set');
        require(asset.balanceOf(msg.sender) >= amount, 'user has not enough balance');
      
        uint256 reward = calcReward(amount);
        require(rewardToken.balanceOf(address(this))-totalRewards >= reward, 'balance of rewardToken too low');
        
        asset.transferFrom(msg.sender, address(this), amount);
        lend.deposit(address(asset), amount, address(this), 0);
        investments[msg.sender] += amount;
        totalInvestments += amount;
        totalRewards += reward;
        
        userRewards[msg.sender] += reward;
    }
    
    function withdraw(uint256 amount) public isActive allowance(amount) {
        require(investments[msg.sender] >= amount, 'amount too high');
        require(getIsFundingPhase() || getIsRewardPhase(), 'balance locked in milestone phase');
        totalInvestments -= amount;
        investments[msg.sender] -= amount;
        lend.withdraw(address(asset), amount, msg.sender);
        uint256 reward = calcReward(amount);
        userRewards[msg.sender] -= reward;
        totalRewards -= reward;
        
        if(getIsRewardPhase()) 
            rewardToken.transfer(msg.sender, reward);
    }
    
    function withdrawInterest(uint256 amount) public onlyOwner isActive allowance(amount) {
        uint256 toWithdraw;
        if(amount == 0) {
            toWithdraw = aToken.balanceOf(address(this)) - totalInvestments;
        } else {
            toWithdraw = amount;
        }
        
        require(toWithdraw <= aToken.balanceOf(address(this)) - totalInvestments, 'amount too high');

        lend.withdraw(address(asset), toWithdraw, owner);
    }
    
    function withdrawRewardToken(uint256 amount) public onlyOwner isActive {
        uint256 toWithdraw;
        if(amount == 0) {
            toWithdraw = rewardToken.balanceOf(address(this));
        } else {
            toWithdraw = amount;
        }
        
        require(toWithdraw <= rewardToken.balanceOf(address(this)), 'amount too high');
        
        rewardToken.transfer(owner, toWithdraw);
    }
    
    function withdrawAllReward() public onlyOwner {
        rewardToken.transfer(msg.sender, rewardToken.balanceOf(address(this)));
    }
    
    function calcReward(uint256 amount) public pure returns(uint256) {
        uint256 result = (amount*10**12) / 2;
        return result;
    }
    
    function getIsFundingPhase() public view returns(bool) {
        return block.timestamp >= startDate && block.timestamp <= startDate + fundingPeriod;
    }
    
    function getIsMeilensteinPhase() public view returns(bool) {
     return (
          block.timestamp >= startDate 
          && block.timestamp >= startDate + fundingPeriod
          && block.timestamp < startDate + fundingPeriod + meilenstein.meilensteinDays*1 days
        );
    }
    
    function setOwner(address newOwner) public onlyOwner {
        owner = newOwner;
    }
    
    function getInvestments(address user) public view  returns (uint256) {
        return investments[user];
    }
    
    function getRewards(address user) public view returns (uint256) {
        return userRewards[user];
    }
    
    function getLockedRewards() public view returns (uint256) {
        return totalRewards;
    }
    
    function getIsRewardPhase() public view returns(bool) {
        return block.timestamp > startDate + fundingPeriod + meilenstein.meilensteinDays*1 days;
    }
    
    // for testing only
    function endFundingPhase() public onlyOwner {
        fundingPeriod = 0;
    }
    
    function endMeilensteinPhase() public onlyOwner {
        meilenstein.meilensteinDays = 0;
    }
}