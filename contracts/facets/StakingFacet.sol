// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;
// 
// import "hardhat/console.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721, IERC721Errors} from "../interfaces/IERC721.sol";
import {LibStakingToken, StakingTokenStorage, TokenInfo} from "../libraries/LibStakingToken.sol";
import {IFarmFacet} from "../interfaces/IFarmFacet.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol"; 
import {ReentrancyGuard} from "../abstract/ReentrancyGuard.sol";
import {FarmStorage, PoolInfo, UserInfo} from "../libraries/FarmStorage.sol";
import {LibFarm} from "../libraries/LibFarm.sol";

contract StakingFacet is ReentrancyGuard { 

  
  event MintStakingToken(address indexed _minter, uint256 _tokenId, uint256 indexed _pid, address _lpToken, uint256 _lpAmount);
  event BurnStakingToken(address indexed _burner, uint256 _tokenId, uint256 indexed _pid, address _lpToken, uint256 _lpAmount, uint256 _gltrAmount);
      
  // Trade liquidity tokens for GLTR Staking Token
  // Deposits liquidity and mints GLTR Staking Token
  // The pid determines which liquidity token to use with amount
  function mintStakingTokens(uint256[] calldata _pids, uint256[] calldata _amounts) public nonReentrant {
    require(_pids.length == _amounts.length, "_pids length not equal to amounts length");    
    StakingTokenStorage storage rt = LibStakingToken.diamondStorage();
    FarmStorage.Layout storage lo = FarmStorage.layout();
    uint256 pl = lo.poolInfo.length;
    uint256 tokenId = rt.tokenIdNum;
    for(uint256 i; i < _amounts.length; i++) {
      uint256 pid = _pids[i];      
      uint256 amount = _amounts[i];
      require(amount > 0, "Staked amount must be greater than 0");      
      require(pid < pl, "Invalid _pid: too large");
      LibFarm.updatePool(pid);
      PoolInfo storage pool = lo.poolInfo[pid];      
      SafeERC20.safeTransferFrom(pool.lpToken, 
        address(msg.sender),
        address(this),
        amount
      );
                    
      // mint NFT           
      tokenId++;      
      TokenInfo storage ti = rt.tokenInfo[tokenId];    
      ti.owner = msg.sender;
      uint256 tokenIndex = rt.ownerTokenIds[msg.sender].length;        
      ti.ownerTokenIdsIndex = tokenIndex;
      rt.ownerTokenIds[msg.sender].push(tokenId);
      ti.stakedTokenAmount = amount;
      ti.debt = (pool.accERC20PerShare * amount) / 1e18;    
      ti.poolId = uint96(pid);
      LibStakingToken.checkOnERC721Received(address(0), msg.sender, tokenId, "");
      emit IERC721.Transfer(address(0), msg.sender, tokenId); 
      emit MintStakingToken(msg.sender, tokenId, pid, address(pool.lpToken), amount);
    }
    rt.tokenIdNum = tokenId;
  }


  // Trade GLTR Staking Tokens for liquidity tokens and gltr
  // Withdraws liquidity tokens and gltr and burns GLTR Staking Token
  function burnStakingTokens(uint256[] calldata _tokenIds) external nonReentrant {    
    StakingTokenStorage storage st = LibStakingToken.diamondStorage();
    FarmStorage.Layout storage lo = FarmStorage.layout();
    IERC20 gltrToken = lo.rewardToken;
    for(uint256 i; i < _tokenIds.length; i++) {
      uint256 tokenId = _tokenIds[i];
      TokenInfo storage ti = st.tokenInfo[tokenId];
      address owner = ti.owner;
      if(owner == address(0)) {
        revert IERC721Errors.ERC721NonexistentToken(tokenId);
      }
      if(!LibStakingToken.isAuthorized(owner, msg.sender, tokenId)) {
        revert IERC721Errors.ERC721InsufficientApproval(msg.sender, tokenId);
      }      
      uint256 pid = ti.poolId;
      LibFarm.updatePool(pid);
      PoolInfo storage pool = lo.poolInfo[pid];
      uint256 tokenStakedAmount = ti.stakedTokenAmount;           
      uint256 gltrAmount = ((pool.accERC20PerShare * tokenStakedAmount) / 1e18) - ti.debt;
      lo.paidOut += gltrAmount;
      IERC20 lpToken = pool.lpToken;
      SafeERC20.safeTransferFrom(lpToken, address(this), owner, tokenStakedAmount);
      SafeERC20.safeTransferFrom(gltrToken, address(this), owner, gltrAmount);
      LibStakingToken.burn(tokenId);
      emit BurnStakingToken(owner, tokenId, pid, address(lpToken), tokenStakedAmount, gltrAmount);
    }
  }

  // Burn staking tokens without receiving GLTR tokens.
  // Only returns liquidity tokens
  function emergencyBurnStakingTokens(uint256[] calldata _tokenIds) external nonReentrant {    
    StakingTokenStorage storage st = LibStakingToken.diamondStorage();
    FarmStorage.Layout storage lo = FarmStorage.layout();
    IERC20 gltrToken = lo.rewardToken;
    for(uint256 i; i < _tokenIds.length; i++) {
      uint256 tokenId = _tokenIds[i];
      TokenInfo storage ti = st.tokenInfo[tokenId];
      address owner = ti.owner;
      if(owner == address(0)) {
        revert IERC721Errors.ERC721NonexistentToken(tokenId);
      }
      if(!LibStakingToken.isAuthorized(owner, msg.sender, tokenId)) {
        revert IERC721Errors.ERC721InsufficientApproval(msg.sender, tokenId);
      }      
      uint256 pid = ti.poolId;      
      PoolInfo storage pool = lo.poolInfo[pid];
      uint256 tokenStakedAmount = ti.stakedTokenAmount;           
      IERC20 lpToken = pool.lpToken;
      SafeERC20.safeTransferFrom(lpToken, address(this), owner, tokenStakedAmount);
      LibStakingToken.burn(tokenId);
      emit BurnStakingToken(owner, tokenId, pid, address(lpToken), tokenStakedAmount, 0);
      emit LibFarm.EmergencyWithdraw(owner, pid, tokenStakedAmount);
    }
  }



  struct Bonus {
    uint256 pid; // pool id
    uint256 gltrAmount; // GLTR gltr
  }
  // Add bonus GLTR to pools
  function addBonus(Bonus[] calldata _bonuses) external {
    FarmStorage.Layout storage lo = FarmStorage.layout();    
    IERC20 gltrToken = lo.rewardToken;
    uint256 pl = lo.poolInfo.length;
    uint256 totalBonus;           
    for(uint256 i; i < _bonuses.length; i++) {
      Bonus calldata bonus = _bonuses[i];
      require(bonus.pid < pl, "Invalid _pid: too large");
      totalBonus += bonus.gltrAmount;
      PoolInfo storage pool = lo.poolInfo[bonus.pid];
      uint256 lpSupply = pool.lpToken.balanceOf(address(this));     
      pool.accERC20PerShare += (bonus.gltrAmount * 1e18) / lpSupply;
    }
    SafeERC20.safeTransferFrom(gltrToken, msg.sender, address(this), totalBonus);    
  }

  //////////////////////////////////////////////////////////////////////////////
  // GETTERS
  //////////////////////////////////////////////////////////////////////////////

  // Return the total gltr that an GLTR Staking Token can be traded for
  function stakingTokenGltr(uint256 _tokenId) public view returns(uint256) {
    TokenInfo storage ti = LibStakingToken.diamondStorage().tokenInfo[_tokenId];
    if(ti.owner == address(0)) {
      revert IERC721Errors.ERC721NonexistentToken(_tokenId);
    }
    uint256 pid = ti.poolId;
    FarmStorage.Layout storage lo = FarmStorage.layout();
    PoolInfo storage pool = lo.poolInfo[pid];
    uint256 accERC20PerShare = pool.accERC20PerShare;
    uint256 lpSupply = pool.lpToken.balanceOf(address(this));
    if (block.number > pool.lastRewardBlock && lpSupply != 0) {
      uint256 nrOfBlocks = block.number - pool.lastRewardBlock;
      uint256 erc20Reward = (LibFarm.sumRewardPerBlock(
        pool.lastRewardBlock,
        nrOfBlocks
      ) * pool.allocPoint) / lo.totalAllocPoint;
      accERC20PerShare += (erc20Reward * 1e18) / lpSupply;
    }
    uint256 gltrAmount = (ti.stakedTokenAmount * accERC20PerShare) / 1e18;
    if (gltrAmount <= ti.debt) return 0;
    else return gltrAmount - ti.debt;
  }


  struct StakingTokenInfo {
    uint256 tokenId;
    uint256 stakedTokenAmount;
    uint256 poolId;
    uint256 gltrAmount;
    address owner;
  }

  function stakingTokenInfo(uint256 _tokenId) external view returns(StakingTokenInfo memory n_) {    
    TokenInfo storage ti = LibStakingToken.diamondStorage().tokenInfo[_tokenId];
    address owner = ti.owner;
    if (owner == address(0)) {
        revert IERC721Errors.ERC721NonexistentToken(_tokenId);
    }
    n_.tokenId = _tokenId;    
    n_.stakedTokenAmount = ti.stakedTokenAmount;
    n_.poolId = ti.poolId;
    n_.gltrAmount = stakingTokenGltr(_tokenId);    
    n_.owner = owner;
  }
  
  // Get owner information
  function stakingTokensInfo(address _owner) public view returns(StakingTokenInfo[] memory n_) {
    StakingTokenStorage storage rt = LibStakingToken.diamondStorage();    
    uint256[] storage tokenIds = rt.ownerTokenIds[_owner];
    uint256 tokenIdsLength = tokenIds.length;
    n_ = new StakingTokenInfo[](tokenIdsLength);
    for(uint256 i; i < tokenIdsLength; i++) {      
      StakingTokenInfo memory n;
      n.tokenId = tokenIds[i];
      TokenInfo storage ti = rt.tokenInfo[n.tokenId];
      n.stakedTokenAmount = ti.stakedTokenAmount;
      n.poolId = ti.poolId;
      n.gltrAmount = stakingTokenGltr(n.tokenId);
      n.owner = _owner;      
    }
  }

    // View function to see pending ERC20s for a user.
  function pending(uint256 _pid, address _user)
    internal
    view
    returns (uint256)
  {
    FarmStorage.Layout storage lo = FarmStorage.layout();
    PoolInfo storage pool = lo.poolInfo[_pid];
    UserInfo storage user = lo.userInfo[_pid][_user];
    uint256 accERC20PerShare = pool.accERC20PerShare;
    uint256 lpSupply = pool.lpToken.balanceOf(address(this));

    if (block.number > pool.lastRewardBlock && lpSupply != 0) {
      uint256 nrOfBlocks = block.number - pool.lastRewardBlock;
      uint256 erc20Reward = (LibFarm.sumRewardPerBlock(
        pool.lastRewardBlock,
        nrOfBlocks
      ) * pool.allocPoint) / lo.totalAllocPoint;
      accERC20PerShare += (erc20Reward * 1e18) / lpSupply;
    }
    uint256 userReward = (user.amount * accERC20PerShare) / 1e18;
    if (userReward <= user.rewardDebt) return 0;
    else return userReward - user.rewardDebt;
  }


   struct UserInfoOutput {
    IERC20 lpToken; // LP Token of the pool
    uint256 allocPoint;
    uint256 pending; // Amount of reward pending for this lp token pool
    uint256 userBalance; // Amount user has deposited
    uint256 poolBalance; // Amount of LP tokens in the pool
  }

  function allUserInfo(address _user)
    internal
    view
    returns (UserInfoOutput[] memory)
  {
    FarmStorage.Layout storage lo = FarmStorage.layout();
    UserInfoOutput[] memory userInfo_ = new UserInfoOutput[](
      lo.poolInfo.length
    );
    for (uint256 i = 0; i < lo.poolInfo.length; i++) {
      userInfo_[i] = UserInfoOutput({
        lpToken: lo.poolInfo[i].lpToken,
        allocPoint: lo.poolInfo[i].allocPoint,
        pending: pending(i, _user),
        userBalance: lo.userInfo[i][_user].amount,
        poolBalance: lo.poolInfo[i].lpToken.balanceOf(address(this))
      });
    }
    return userInfo_;
  }

  struct StakingTokensAndOwnerInfo {
    StakingTokenInfo[] stakingTokensInfo;
    UserInfoOutput[] userInfo;
  }

  function stakingTokensAndUserInfo(address _owner) external view returns (StakingTokensAndOwnerInfo memory info_) {
    info_.stakingTokensInfo = stakingTokensInfo(_owner);
    info_.userInfo = allUserInfo(_owner);
  }


}