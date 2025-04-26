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

contract LiquidityCalculator {
    // Uniswap V3 pool for the token pair
    ICLPool public immutable pool;

    constructor(address _pool) {
        pool = ICLPool(_pool);
    }


    function getTicks (uint128 liquidity) external view returns (uint amount0, uint amount1){
        //address token0 = ICLPoolConstants(pool).token0();
       // address token1 = ICLPoolConstants(pool).token1();
       // address farmNFT = ICLPoolConstants(pool).nft();


 //      Estimate Liquidity (L):
                        //    The USD value of the position is approximately the sum of amount0 (DAI) and amount1 (USDC), since both are stablecoins worth $1.
//
  //                          For a position in the range [-600, 600] with the current price at tick = 0, you provide both tokens.
//
  //                          The token amounts are:
    //                        amount0 = L * (1/√P_lower - 1/√P_upper).
//
  //                          amount1 = L * (√P_upper - √P_lower).
//
  //                          Substituting:
    //                        √P_lower ≈ 0.994, √P_upper ≈ 1.006, √P_current = 1.

      //                      amount0 = L * (1/0.994 - 1/1.006) ≈ L * (1.006 - 0.994) ≈ L * 0.012.

        //                    amount1 = L * (1.006 - 0.994) ≈ L * 0.012.

          //                  Total USD value: amount0 + amount1 ≈ L * 0.012 + L * 0.012 = L * 0.024.

            //                Set the USD value to $80:
              //              L * 0.024 = 80.

                //            L ≈ 80 / 0.024 ≈ 3333.33.


        int24 tickSpacing = ICLPoolConstants(pool).tickSpacing();
        (uint160 sqrtPriceX96, int24 currentTick, , , , ) = ICLPool(pool).slot0();
        currentTick = (currentTick / tickSpacing) * tickSpacing;
        int24 lowTick = currentTick - tickSpacing;
        int24 highTick = currentTick + tickSpacing;
        uint160 sqrtPriceLower = TickMath.getSqrtRatioAtTick(lowTick);
        uint160 sqrtPriceUpper = TickMath.getSqrtRatioAtTick(highTick);
        // Current price in range: both tokens needed
        amount0 = getAmount0ForLiquidity(sqrtPriceLower, sqrtPriceUpper, liquidity);
        amount1 = getAmount1ForLiquidity(sqrtPriceLower, sqrtPriceUpper, liquidity);
        
        return (amount0, amount1);
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