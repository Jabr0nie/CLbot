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

address _pool = 0x7cfc2Da3ba598ef4De692905feDcA32565AB836E;
function addLiquidity(uint256 amount0ToMint) public view returns (uint128) {
    // Approve the position manager
    (int24 tickLower,int24 tickUpper) = getTicks(_pool);

    uint160 sqrtPriceLower = TickMath.getSqrtRatioAtTick(tickLower);
    uint160 sqrtPriceUpper = TickMath.getSqrtRatioAtTick(tickUpper);



    uint128 liquidity = LiquidityAmounts.getLiquidityForAmount0(sqrtPriceLower, sqrtPriceUpper, amount0ToMint);

    return liquidity;
}
}