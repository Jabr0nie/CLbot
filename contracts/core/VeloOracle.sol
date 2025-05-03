// SPDX-License-Identifier: MIT
pragma solidity >=0.5.0;

import "./interfaces/pool/ICLPoolDerivedState.sol";
import "./libraries/LowGasSafeMath.sol";
import "./libraries/SafeCast.sol";
import "./libraries/Tick.sol";
import "./libraries/TickBitmap.sol";
import "./libraries/Position.sol";
import "./libraries/Oracle.sol";
import "./interfaces/ICLPool.sol";
import "./libraries/FullMath.sol";
import "./libraries/FixedPoint128.sol";
import "./libraries/TransferHelper.sol";
import "./libraries/TickMath.sol";
import "./libraries/LiquidityMath.sol";
import "./libraries/LiquidityAmounts.sol";
import "./libraries/SqrtPriceMath.sol";
import "./IERC721.sol";
import "./INonfungiblePositionManager.sol";
import "./interfaces/ICLPool.sol";


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

contract VeloOracle {

ICLPoolDerivedState public V3Pool;


function GetPrice(address pool) public view returns (uint256 price) {
    require(pool != address(0), "Invalid pool address");

    // Fetch token addresses
    address token0 = ICLPoolConstants(pool).token0();
    address token1 = ICLPoolConstants(pool).token1();
    require(token0 != address(0) && token1 != address(0), "Invalid tokens");

    // Determine pool ordering

    // Fetch decimals
    uint8 dec0 = IERC20(token0).decimals(); // 6 (USDC)

    // Fetch current tick
    (, int24 tick, , , , ) = ICLPoolState(pool).slot0();

    // Get sqrt price
    uint160 sqrtRatioX96 = TickMath.getSqrtRatioAtTick(tick);
    uint256 sqrtPrice = uint256(sqrtRatioX96);

    // Calculate raw price: (sqrtPrice^2 / 2^192)
    uint256 priceRaw = FullMath.mulDiv(sqrtPrice * sqrtPrice, 1, 2**192);

    price = priceRaw > 0 ? FullMath.mulDiv(10**18, 10**18, priceRaw) : 0; // 18-decimal precision
    // Normalize to 18 decimals: multiply by 10^dec0 (WETH decimals)
    price = price / (10 ** (dec0 + 12));

    return (price);
}

    function getTicks (address pool) public view returns (int24 lowTick, int24 highTick){
        int24 tickSpacing = ICLPoolConstants(pool).tickSpacing();
        (, int24 currentTick, , , , ) = ICLPool(pool).slot0();
        currentTick = (currentTick / tickSpacing) * tickSpacing;
        lowTick = currentTick - tickSpacing;
        highTick = currentTick + tickSpacing;
        return (lowTick, highTick);
        }

 

function getAmount0ForLiquidity(uint160 sqrtRatioAX96, uint160 sqrtRatioBX96, uint128 liquidity)
        internal
        pure
        returns (uint256 amount0)
    {
        if (sqrtRatioAX96 > sqrtRatioBX96) (sqrtRatioAX96, sqrtRatioBX96) = (sqrtRatioBX96, sqrtRatioAX96);

        return FullMath.mulDiv(
            uint256(liquidity) << FixedPoint96.RESOLUTION, sqrtRatioBX96 - sqrtRatioAX96, sqrtRatioBX96
        ) / sqrtRatioAX96;
    }

    /// @notice Computes the amount of token1 for a given amount of liquidity and a price range
    /// @param sqrtRatioAX96 A sqrt price representing the first tick boundary
    /// @param sqrtRatioBX96 A sqrt price representing the second tick boundary
    /// @param liquidity The liquidity being valued
    /// @return amount1 The amount of token1
    function getAmount1ForLiquidity(uint160 sqrtRatioAX96, uint160 sqrtRatioBX96, uint128 liquidity)
        internal
        pure
        returns (uint256 amount1)
    {
        if (sqrtRatioAX96 > sqrtRatioBX96) (sqrtRatioAX96, sqrtRatioBX96) = (sqrtRatioBX96, sqrtRatioAX96);

        return FullMath.mulDiv(liquidity, sqrtRatioBX96 - sqrtRatioAX96, FixedPoint96.Q96);
    }




}
