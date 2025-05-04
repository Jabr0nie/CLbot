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
import "./IERC721.sol";
import "./INonfungiblePositionManager.sol";

interface Oracle {
    function GetPrice(address pooladdress) external view returns (uint256 price);
    function getAmountsforLiquidity(address pool, uint256 usdAmount) external view returns (uint amount0, uint amount1);
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


contract V3Bot {
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

    mapping(uint256 => Deposit) public deposits;

    event SwapExecuted(address indexed user, uint256 amountIn, uint256 amountOut);

    constructor() {
        admin = msg.sender;
    }

    function _newAdmin(address newAdmin) external {
        require(msg.sender == admin, "Only owner can do this");
        admin = newAdmin;
    }

    function _newSpaceMultiplier(int24 newSpaceMultiplier) external {
        require(msg.sender == admin, "Only owner can do this");
        spaceMultiplier = newSpaceMultiplier;
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

    function getTicks () public view returns (int24 lowTick, int24 highTick){
        (, int24 currentTick, , , , ) = ICLPool(pool).slot0();
        currentTick = (currentTick / tickSpacing) * tickSpacing;
        lowTick = currentTick - tickSpacing;
        highTick = currentTick + tickSpacing;
        return (lowTick, highTick);
        }


function addLiquidity(uint256 amount0ToMint) public payable {
    // Approve the position manager
    (int24 tickLower,int24 tickUpper) = getTicks();

    // Get square root prices for ticks
    //(, int24 tick, , , , ) = ICLPoolState(pool).slot0();
   //uint160 currentSqrtPrice = TickMath.getSqrtRatioAtTick(tick);
    uint160 sqrtPriceLower = TickMath.getSqrtRatioAtTick(tickLower);
    uint160 sqrtPriceUpper = TickMath.getSqrtRatioAtTick(tickUpper);



    uint128 _liquidity = LiquidityAmounts.getLiquidityForAmount0(sqrtPriceLower, sqrtPriceUpper, amount0ToMint);

    uint amount1ToMint =  LiquidityAmounts.getAmount1ForLiquidity(sqrtPriceLower, sqrtPriceUpper, _liquidity);

    //(uint amount0ToMint, uint amount1ToMint) = Oracle(oracle).getAmountsforLiquidity(pool, _liquidity); -- V2 Pools

    //Approve Tokens
        IERC20(token0).transferFrom(msg.sender, address(this), amount0ToMint);
        IERC20(token1).transferFrom(msg.sender, address(this), amount1ToMint);

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
                recipient: msg.sender,
                deadline: block.timestamp + 1500000,
                sqrtPriceX96: 0
            });


        (tokenId, , , ) = INonfungiblePositionManager(farmNFT).mint(params);
}

}