// SPDX-License-Identifier: MIT
pragma solidity =0.7.6;
pragma abicoder v2;

import "./interfaces/ICLPool.sol";
import "./libraries/LowGasSafeMath.sol";
import "./libraries/SafeCast.sol";
import "./libraries/Tick.sol";
import "./libraries/TickBitmap.sol";
import "./libraries/Position.sol";

import "./libraries/FullMath.sol";
import "./libraries/FixedPoint128.sol";
import "./libraries/TransferHelper.sol";
import "./libraries/TickMath.sol";
import "./libraries/LiquidityMath.sol";
import "./libraries/LiquidityAmounts.sol";
import "./libraries/SqrtPriceMath.sol";

import "./interfaces/ICLFactory.sol";
import "./interfaces/IFactoryRegistry.sol";
import "./interfaces/IERC20Minimal.sol";
import "./interfaces/callback/ICLMintCallback.sol";
import "./interfaces/callback/ICLSwapCallback.sol";
import "contracts/libraries/VelodromeTimeLibrary.sol";
import "./INonfungiblePositionManager.sol";

import {ERC721Holder} from "@openzeppelin/contracts/token/ERC721/ERC721Holder.sol";

interface Oracle {
    function GetPrice(address pooladdress) external view returns (uint256 price);
    function getAmountsforLiquidity(address pool, uint256 usdAmount) external view returns (uint amount0, uint amount1);
}

interface IERC721 {
    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);
    event Approval(address indexed owner, address indexed approved, uint256 indexed tokenId);
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);
    function balanceOf(address owner) external view returns (uint256 balance);
    function ownerOf(uint256 tokenId) external view returns (address owner);
    function safeTransferFrom(address from, address to, uint256 tokenId, bytes calldata data) external;
    function safeTransferFrom(address from, address to, uint256 tokenId) external;
    function transferFrom(address from, address to, uint256 tokenId) external;
    function approve(address to, uint256 tokenId) external;
    function setApprovalForAll(address operator, bool approved) external;
    function getApproved(uint256 tokenId) external view returns (address operator);
    function isApprovedForAll(address owner, address operator) external view returns (bool);
}

interface ICLGauge {
    event NotifyReward(address indexed from, uint256 amount);
    event Deposit(address indexed user, uint256 indexed tokenId, uint128 indexed liquidityToStake);
    event Withdraw(address indexed user, uint256 indexed tokenId, uint128 indexed liquidityToStake);
    event ClaimFees(address indexed from, uint256 claimed0, uint256 claimed1);
    event ClaimRewards(address indexed from, uint256 amount);
    function nft() external view returns (INonfungiblePositionManager);
    function voter() external view returns (IVoter);
    function pool() external view returns (ICLPool);
    function feesVotingReward() external view returns (address);
    function periodFinish() external view returns (uint256);
    function rewardRate() external view returns (uint256);
    function rewards(uint256 tokenId) external view returns (uint256);
    function lastUpdateTime(uint256 tokenId) external view returns (uint256);
    function rewardRateByEpoch(uint256) external view returns (uint256);
    function fees0() external view returns (uint256);
    function fees1() external view returns (uint256);
    function token0() external view returns (address);
    function token1() external view returns (address);
    function tickSpacing() external view returns (int24);
    function left() external view returns (uint256 _left);
    function rewardToken() external view returns (address);
    function isPool() external view returns (bool);
    function rewardGrowthInside(uint256 tokenId) external view returns (uint256);
    function earned(address account, uint256 tokenId) external view returns (uint256);
    function getReward(address account) external;
    function getReward(uint256 tokenId) external;
    function notifyRewardAmount(uint256 amount) external;
    function notifyRewardWithoutClaim(uint256 amount) external;
    function deposit(uint256 tokenId) external;
    function withdraw(uint256 tokenId) external;
    function stakedValues(address depositor) external view returns (uint256[] memory);
    function stakedByIndex(address depositor, uint256 index) external view returns (uint256);
    function stakedContains(address depositor, uint256 tokenId) external view returns (bool);
    function stakedLength(address depositor) external view returns (uint256);
}

interface IERC20 {
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 value) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 value) external returns (bool);
    function transferFrom(address from, address to, uint256 value) external returns (bool);
    function decimals() external view returns (uint8);
}


contract V3BotStaking is ERC721Holder{
    address public pool; // token0/token1 pool address
    address public token0; // token0 on Optimism
    address public token1; // token1 on Optimism
    address public farmNFT;
    uint256 public tokenId;
    address public admin;
    int24 public tickSpacing;
    int24 public spaceMultiplier;
    address public oracle = 0x9465eD15b70E8A534663530C4fCc92E22B8F6032;

    struct Deposit {
        address owner;
        uint128 liquidity;
        address token0;
        address token1;
    }

    /// @dev deposits[tokenId] => Deposit
    mapping(uint256 => Deposit) public deposits;

        constructor() {
        admin = msg.sender;
    }

    function _newAdmin(address newAdmin) external {
        require(msg.sender == admin, "Only owner can do this");
        admin = newAdmin;
    }

    function _newtokenID(uint256 newTokenId) external {
        require(msg.sender == admin, "Only owner can do this");
        tokenId = newTokenId;
    }
// Us ICLGuage to stake the token
//use the 
    function stake() public payable {
        IERC721(0x416b433906b1B72FA758e166e239c43d68dC6F29).transferFrom(msg.sender, address(this), tokenId);
        IERC721(0x416b433906b1B72FA758e166e239c43d68dC6F29).approve(msg.sender, tokenId);
        IERC721(0x416b433906b1B72FA758e166e239c43d68dC6F29).approve(0xC8c7b5aE61d97Be7d02d606629059487066DC9CF, tokenId);
        ICLGauge(0xC8c7b5aE61d97Be7d02d606629059487066DC9CF).deposit(tokenId);
    }


    function withdraw() public payable {
        ICLGauge(0xC8c7b5aE61d97Be7d02d606629059487066DC9CF).withdraw(tokenId);
    }

    function sendNFTBack() public payable {
        IERC721(0x416b433906b1B72FA758e166e239c43d68dC6F29).transferFrom(address(this), msg.sender, tokenId);
    }

    function _transferToAdmin(address Token) external {
        uint256 value = IERC20Minimal(Token).balanceOf(address(this));
        IERC20Minimal(Token).transfer(admin, value);
    }

    



}