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
    bool isToken0Base = token0 < token1;

    // Fetch decimals
    uint8 dec0 = IERC20(token0).decimals(); // 6 (USDC)
    uint8 dec1 = IERC20(token1).decimals(); // 18 (WETH)

    // Fetch current tick
    (, int24 tick, , , , ) = ICLPoolState(pool).slot0();

    // Get sqrt price
    uint160 sqrtRatioX96 = TickMath.getSqrtRatioAtTick(tick);
    uint256 sqrtPrice = uint256(sqrtRatioX96);

    // Calculate raw price: (sqrtPrice^2 / 2^192)
    uint256 priceRaw = FullMath.mulDiv(sqrtPrice * sqrtPrice, 1, 2**192);

    // Adjust for decimals and pool ordering
    if (isToken0Base) {
        // Price is quoteToken/baseToken (WETH/USDC)
        price = priceRaw; // Raw price is WETH/USDC
        // Normalize to 18 decimals: multiply by 10^dec0 (USDC decimals)
        price = FullMath.mulDiv(price, 10**dec0, 1); // e.g., *10^6 for USDC
    } else {
        // Price is quoteToken/baseToken (USDC/WETH)
        // Invert the price: 1 / priceRaw
        price = priceRaw > 0 ? FullMath.mulDiv(10**18, 10**18, priceRaw) : 0; // 18-decimal precision
        // Normalize to 18 decimals: multiply by 10^dec0 (WETH decimals)
        price = FullMath.mulDiv(price, 10**dec1, 1); // e.g., *10^18 for WETH
    }

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

    function getAmountsforLiquidity(address pool,
        uint256 usdAmount // Total USD value (in 18 decimals, e.g., 80e18 for $80)
    ) external view returns (uint amount0, uint amount1) {
        
        (int24 tickLower,int24 tickUpper) = getTicks(pool);

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

        function getLiquidityForAmount0(uint160 sqrtRatioAX96, uint160 sqrtRatioBX96, uint256 amount0)
        internal
        pure
        returns (uint128 liquidity)
    {
        if (sqrtRatioAX96 > sqrtRatioBX96) (sqrtRatioAX96, sqrtRatioBX96) = (sqrtRatioBX96, sqrtRatioAX96);
        uint256 intermediate = FullMath.mulDiv(sqrtRatioAX96, sqrtRatioBX96, FixedPoint96.Q96);
        return toUint128(FullMath.mulDiv(amount0, intermediate, sqrtRatioBX96 - sqrtRatioAX96));
    }

    /// @notice Computes the amount of liquidity received for a given amount of token1 and price range
    /// @dev Calculates amount1 / (sqrt(upper) - sqrt(lower)).
    /// @param sqrtRatioAX96 A sqrt price representing the first tick boundary
    /// @param sqrtRatioBX96 A sqrt price representing the second tick boundary
    /// @param amount1 The amount1 being sent in
    /// @return liquidity The amount of returned liquidity
    function getLiquidityForAmount1(uint160 sqrtRatioAX96, uint160 sqrtRatioBX96, uint256 amount1)
        internal
        pure
        returns (uint128 liquidity)
    {
        if (sqrtRatioAX96 > sqrtRatioBX96) (sqrtRatioAX96, sqrtRatioBX96) = (sqrtRatioBX96, sqrtRatioAX96);
        return toUint128(FullMath.mulDiv(amount1, FixedPoint96.Q96, sqrtRatioBX96 - sqrtRatioAX96));
    }

}
