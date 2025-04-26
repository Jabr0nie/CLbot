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

contract LiquidityCalculator {
    // Uniswap V3 pool for the token pair
    ICLPool public immutable pool;

    constructor(address _pool) {
        pool = ICLPool(_pool);
    }


    function getTicks () public view returns (int24 lowTick, int24 highTick){
        int24 tickSpacing = ICLPoolConstants(pool).tickSpacing();
        (, int24 currentTick, , , , ) = ICLPool(pool).slot0();
        currentTick = (currentTick / tickSpacing) * tickSpacing;
        lowTick = currentTick - tickSpacing;
        highTick = currentTick + tickSpacing;

    
        return (lowTick, highTick);
        }

         // Calculate liquidity and token amounts for a given USD value
    function calculateLiquidityForUSD(
        uint256 usdAmount // Total USD value (in 18 decimals, e.g., 80e18 for $80)
    ) external view returns (uint amount0, uint amount1) {
        
        (int24 tickLower,int24 tickUpper) = getTicks();

        // Get square root prices for ticks
        uint160 sqrtPriceLower = TickMath.getSqrtRatioAtTick(tickLower);
        uint160 sqrtPriceUpper = TickMath.getSqrtRatioAtTick(tickUpper);

        // Calculate price differences
        // Δ(1/√P) = 1/√P_lower - 1/√P_upper
        uint256 deltaInvSqrtPrice;
        {
            deltaInvSqrtPrice = FullMath.mulDiv(1e18, 1 << 96, sqrtPriceLower) -
                                FullMath.mulDiv(1e18, 1 << 96, sqrtPriceUpper);
        }

        // Δ√P = √P_upper - √P_lower
        uint256 deltaSqrtPrice = uint256(sqrtPriceUpper) - uint256(sqrtPriceLower);

        // Assume USD value splits evenly for stablecoin pair (1:1 price)
        // For DAI/USDC at 1:1, amount0 (DAI, 18 decimals) + amount1 (USDC, 6 decimals) ≈ usdAmount
        // Total USD value: amount0 + amount1 * 10^12 (adjusting USDC to 18 decimals) = usdAmount
        // amount0 = L * Δ(1/√P), amount1 = L * Δ√P
        // Total USD: L * Δ(1/√P) + L * Δ√P * 10^12 = usdAmount
        // L = usdAmount / (Δ(1/√P) + Δ√P * 10^12)

        uint256 denominator = deltaInvSqrtPrice + FullMath.mulDiv(deltaSqrtPrice, 1e12, 1 << 96);
        uint128 liquidity = uint128(FullMath.mulDiv(usdAmount, 1e18, denominator));

        amount0 = getAmount0ForLiquidity(sqrtPriceLower, sqrtPriceUpper, liquidity);
        amount1 = getAmount1ForLiquidity(sqrtPriceLower, sqrtPriceUpper, liquidity);
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