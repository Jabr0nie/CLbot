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


contract V3BRAIN is ERC721Holder, ICLSwapCallback{
    address public pool; // token0/token1 pool address
    address public token0; // token0 on Optimism
    address public token1; // token1 on Optimism
    address public farmNFT;
    uint256 public tokenId;
    address public admin;
    int24 public tickSpacing;
    int24 public spaceMultiplier;
    address public oracle;

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

    function _newOracle(address newOracle) external {
        require(msg.sender == admin, "Only owner can do this");
        oracle = newOracle;
    }

    function _newtokenID(uint256 newTokenId) external {
        require(msg.sender == admin, "Only owner can do this");
        tokenId = newTokenId;
    }

    function Swap0for1(uint256 amountIn) public payable {
        require(amountIn > 0, "Invalid input amount");


        // Get current sqrtPriceX96 from the pool
        (uint160 sqrtPriceX96, , , , , ) = ICLPoolState(pool).slot0();
        uint160 sqrtPriceLimitX96 = uint160(sqrtPriceX96 * 99 / 100); // 1% slippage

        // Ensure valid range
        if (sqrtPriceLimitX96 <= TickMath.MIN_SQRT_RATIO) {
            sqrtPriceLimitX96 = TickMath.MIN_SQRT_RATIO + 1;
        }

        // Approve pool to spend token0
        IERC20Minimal(token0).approve(pool, amountIn);

        // Prepare data for callback (not strictly needed here, but included for completeness)
        bytes memory data = abi.encode(address(this));

        // Call the pool's swap function
        ICLPoolActions(pool).swap(
            address(this),     // recipient
            true,              // zeroForOne: token0 -> token1
            int256(amountIn),  // exact input
            sqrtPriceLimitX96, // price limit
            data               // callback data
        );
    }

    function Swap1for0(uint256 amountIn) public payable {
        require(amountIn > 0, "Invalid input amount");

        // Get current sqrtPriceX96 from the pool
        (uint160 sqrtPriceX96, , , , , ) = ICLPoolState(pool).slot0();
        uint160 sqrtPriceLimitX96 = uint160(sqrtPriceX96 * 101 / 100); // 1% slippage

        // Ensure valid range
        if (sqrtPriceLimitX96 <= TickMath.MIN_SQRT_RATIO) {
            sqrtPriceLimitX96 = TickMath.MIN_SQRT_RATIO - 1;
        }

        // Approve pool to spend token0
        IERC20Minimal(token1).approve(pool, amountIn);

        // Prepare data for callback (not strictly needed here, but included for completeness)
        bytes memory data = abi.encode(address(this));

        // Call the pool's swap function
        ICLPoolActions(pool).swap(
            address(this),     // recipient
            false,              // zeroForOne: token0 -> token1
            int256(amountIn),  // exact input
            sqrtPriceLimitX96, // price limit
            data               // callback data
        );
    }

    // This is the required callback for the pool to call after swap
    function uniswapV3SwapCallback(
        int256 amount0Delta,
        int256 amount1Delta,
        bytes calldata /* data */
    ) external override {
        require(msg.sender == pool, "Callback only from pool");

        // If amount0Delta > 0, we must pay that amount of token0 to the pool
        if (amount0Delta > 0) {
            IERC20Minimal(token0).transfer(pool, uint256(amount0Delta));
        }
        // If amount1Delta > 0, we must pay that amount of token1 to the pool (not expected in token0->token1 swap)
        if (amount1Delta > 0) {
            IERC20Minimal(token1).transfer(pool, uint256(amount1Delta));
        }
    }

    function approveTokens(uint approve0, uint approve1) external payable {
        IERC20Minimal(token0).approve(farmNFT, approve0);
        IERC20Minimal(token1).approve(farmNFT, approve1);
    }

    function stake() public payable {
        IERC721(0x416b433906b1B72FA758e166e239c43d68dC6F29).approve(admin, tokenId);
        IERC721(0x416b433906b1B72FA758e166e239c43d68dC6F29).approve(0xC8c7b5aE61d97Be7d02d606629059487066DC9CF, tokenId);
        ICLGauge(0xC8c7b5aE61d97Be7d02d606629059487066DC9CF).deposit(tokenId);
    }


    function withdraw() public payable {
        ICLGauge(0xC8c7b5aE61d97Be7d02d606629059487066DC9CF).withdraw(tokenId);
    }

    function _manualWithdraw(uint256 _tokenid) public payable {
        ICLGauge(0xC8c7b5aE61d97Be7d02d606629059487066DC9CF).withdraw(_tokenid);
    }

    function liquidityCurrent() public view returns(uint128){
        (, , , , , , , uint128 liquidity, , , , ) = INonfungiblePositionManager(0x416b433906b1B72FA758e166e239c43d68dC6F29).positions(tokenId);
        return (liquidity);
    }


    function removeLP() public payable {

        (, , , , , , , uint128 liquidity, , , , ) = INonfungiblePositionManager(0x416b433906b1B72FA758e166e239c43d68dC6F29).positions(tokenId);

        INonfungiblePositionManager.DecreaseLiquidityParams memory params =
            INonfungiblePositionManager.DecreaseLiquidityParams({
                tokenId: tokenId,
                liquidity: liquidity,
                amount0Min: 0,
                amount1Min: 0,
                deadline: block.timestamp + 1500000

            });


        INonfungiblePositionManager(0x416b433906b1B72FA758e166e239c43d68dC6F29).decreaseLiquidity(params);

        INonfungiblePositionManager.CollectParams memory Collectparams =
            INonfungiblePositionManager.CollectParams({
                tokenId: tokenId,
                recipient: address(this),
                amount0Max: 9007199254740991000000000000000000,
                amount1Max: 9007199254740991000000000000000000
            });
        INonfungiblePositionManager(0x416b433906b1B72FA758e166e239c43d68dC6F29).collect(Collectparams);

    }

    function sendNFTBack() public payable {
        require(msg.sender == admin, "Only owner can do this");
        IERC721(0x416b433906b1B72FA758e166e239c43d68dC6F29).transferFrom(address(this), msg.sender, tokenId);
    }

        function manualSendNFTBack(uint256 _tokenID) public payable {
        require(msg.sender == admin, "Only owner can do this");
        IERC721(0x416b433906b1B72FA758e166e239c43d68dC6F29).transferFrom(address(this), msg.sender, _tokenID);
    }


    function _newPool(address newPool) external {
        require(msg.sender == admin, "Only owner can do this");
        pool = newPool;
        token0 = ICLPoolConstants(pool).token0();
        token1 = ICLPoolConstants(pool).token1();
        farmNFT = ICLPoolConstants(pool).nft();
        tickSpacing = ICLPoolConstants(pool).tickSpacing();
    }

    function _transferToAdmin(address Token) external {
        uint256 value = IERC20Minimal(Token).balanceOf(address(this));
        IERC20Minimal(Token).transfer(admin, value);
    }

    function getTicks () public view returns (int24 lowTick, int24 highTick, int24 currentTick){
        (, currentTick, , , , ) = ICLPool(pool).slot0();
        int24 _currentTick = (currentTick / tickSpacing) * tickSpacing;
        lowTick = _currentTick;
        highTick = _currentTick + tickSpacing;
        return (lowTick, highTick, currentTick);
        }

function rebalance() public payable {
    // Fetch ticks
    (int24 tickLower,, int24 currentTick) = getTicks();
    require(currentTick >= tickLower, "Invalid tick range");

    // Get price from oracle (USDC/VELO, scaled by 10^5)
    uint256 veloPrice = Oracle(oracle).GetPrice(pool);
    require(veloPrice > 0, "Invalid oracle price");

    // Calculate proportion (0–100)
    uint256 proportion = FullMath.mulDiv(uint256(currentTick - tickLower), 100, 200);
    if (proportion > 100) {
        proportion = 100; // Cap at 100%
    }

    // Fetch token balances
    uint256 amount0 = IERC20(token0).balanceOf(address(this)); // USDC, 6 decimals
    uint256 amount1 = IERC20(token1).balanceOf(address(this)); // VELO, 18 decimals
    require(amount0 > 0 || amount1 > 0, "No tokens to rebalance");

    // Convert VELO to USDC terms
    // USDC (6 decimals) = (VELO (18 decimals) * price (5 decimals)) / 10^17
    uint256 amount1InUSDC = FullMath.mulDiv(amount1, veloPrice, 10 ** 17);

    // Calculate total value in USDC terms
    uint256 total = LowGasSafeMath.add(amount0, amount1InUSDC);
    require(total > 0, "Zero total value");

    // Calculate target proportions
    uint256 veloProp = FullMath.mulDiv(total, proportion, 100); // Target USDC
    uint256 usdcProp = LowGasSafeMath.sub(total, veloProp); // Target VELO in USDC terms

    // Calculate deviations
    int256 usdcVar = int256(amount0) - int256(usdcProp); // USDC deviation
    int256 veloVar = int256(amount1InUSDC) - int256(veloProp); // VELO deviation in USDC terms

    // Execute swap
    if (usdcVar > 0) {
        // Too much USDC, swap for VELO
        uint256 amountIn = uint256(usdcVar); // USDC amount (6 decimals)
        require(amountIn <= amount0, "Insufficient USDC");
        require(amountIn > 0, "Zero swap amount");
        Swap0for1(amountIn);
    } else if (veloVar > 0) {
        // Too much VELO, swap for USDC
        // Convert veloVar (USDC, 6 decimals) to VELO (18 decimals)
        uint256 amountIn = FullMath.mulDiv(uint256(veloVar), 10 ** 17, veloPrice);
        require(amountIn <= amount1, "Insufficient VELO");
        require(amountIn > 0, "Zero swap amount");
        Swap1for0(amountIn);
    }
}

function addLiquidity() public payable returns(uint256) {
    uint256 amount0ToMint = IERC20(token0).balanceOf(address(this));
    uint256 amount1ToMint = IERC20(token1).balanceOf(address(this));
    // Approve the position manager
    (int24 tickLower,int24 tickUpper,) = getTicks();


  //  uint160 sqrtPriceLower = TickMath.getSqrtRatioAtTick(tickLower);
 //   uint160 sqrtPriceUpper = TickMath.getSqrtRatioAtTick(tickUpper);

  //  uint128 _liquidity = LiquidityAmounts.getLiquidityForAmount0(sqrtPriceLower, sqrtPriceUpper, amount0ToMint);

  //  uint amount1ToMint =  LiquidityAmounts.getAmount1ForLiquidity(sqrtPriceLower, sqrtPriceUpper, _liquidity);

    //(uint amount0ToMint, uint amount1ToMint) = Oracle(oracle).getAmountsforLiquidity(pool, _liquidity); -- V2 Pools

        IERC20(token0).approve(farmNFT, amount0ToMint);
        IERC20(token1).approve(farmNFT, amount1ToMint);

    // Get current sqrtPriceX96 from the pool

        INonfungiblePositionManager.MintParams memory params =
            INonfungiblePositionManager.MintParams({
                token0: token0,
                token1: token1,
                tickSpacing: tickSpacing,
                tickLower: tickLower, //add custom logic
                tickUpper: tickUpper, //add custom logic
                amount0Desired: amount0ToMint,
                amount1Desired: amount1ToMint,
                amount0Min: 0,
                amount1Min: 0,
                recipient: address(this),
                deadline: block.timestamp + 1500000,
                sqrtPriceX96: 0
            });



        (tokenId, , , ) = INonfungiblePositionManager(farmNFT).mint(params);

        return tokenId;

}

    function checkFarm() public view returns(bool){
        (,, int24 currentTick) = getTicks();
        (, , , , ,int24 tickLower, int24 tickHigher, , , , , ) = INonfungiblePositionManager(0x416b433906b1B72FA758e166e239c43d68dC6F29).positions(tokenId);
        if(currentTick < tickLower){
            return false;
        }
        else if (currentTick > tickHigher) {
            return false;
        }
        else {
            return true;
        }
    }

    function UpdatePosition() public payable {
        bool inRange = checkFarm();
        if (inRange == true) {
            return;
        }
        withdraw();
        collectRewards();
        removeLP();
        rebalance();
        addLiquidity();
        stake();
    }

    function initialPosition() public payable {
        require(msg.sender == admin, "Only owner can do this");
        rebalance();
        addLiquidity();
        stake();
    }

        function collectRewards() public payable {
             ICLGauge(0xC8c7b5aE61d97Be7d02d606629059487066DC9CF).getReward(tokenId);
    }


}