// SPDX-License-Identifier: MIT
pragma solidity >=0.5.0;

import "./interfaces/pool/ICLPoolDerivedState.sol";
import "./libraries/LowGasSafeMath.sol";
import "./libraries/SafeCast.sol";
import "./libraries/Tick.sol";
import "./libraries/TickBitmap.sol";
import "./libraries/Position.sol";
import "./libraries/Oracle.sol";

import "./libraries/FullMath.sol";
import "./libraries/FixedPoint128.sol";
import "./libraries/TransferHelper.sol";
import "./libraries/TickMath.sol";
import "./libraries/LiquidityMath.sol";
import "./libraries/SqrtPriceMath.sol";

contract VeloOracle {

ICLPoolDerivedState public V3Pool;

uint32[] private secondsAgos = [0,1];

    function GetPrice(address pool) public view returns (uint) {
        uint price;
        (int56[] memory tickCumulatives,) = ICLPoolDerivedState(pool).observe(secondsAgos);
        int56 ticka = tickCumulatives[0];
        int56 tickb = tickCumulatives[1];
        int56 tick = (ticka-tickb)/1;
        int24 tick24 = int24(tick);
        uint160 sqrtRatioX96 = TickMath.getSqrtRatioAtTick(tick24);
        uint256 a = uint256(sqrtRatioX96);
        uint256 s = (a ** 2);
        uint256 t = (2 ** 192);
        uint256 r = (10 ** 14);
        uint256 d = FullMath.mulDiv(s,r,t);
        price = (d * r)*(10 ** 2);
        return price;
    }

     
     function calcLiquidity(address pool, ) public view returns (uint)  

     // compute the liquidity amount
        {
            (uint160 sqrtPriceX96,,,,,) = pool.slot0();
            uint160 sqrtRatioAX96 = TickMath.getSqrtRatioAtTick(params.tickLower);
            uint160 sqrtRatioBX96 = TickMath.getSqrtRatioAtTick(params.tickUpper);

            liquidity = LiquidityAmounts.getLiquidityForAmounts(
                sqrtPriceX96, sqrtRatioAX96, sqrtRatioBX96, params.amount0Desired, params.amount1Desired
            );
        }
}
