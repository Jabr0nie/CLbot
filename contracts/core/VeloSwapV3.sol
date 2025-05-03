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


contract V3Swap is ICLSwapCallback {
    address public pool; // token0/token1 pool address
    address public token0; // token0 on Optimism
    address public token1; // token1 on Optimism
    address public farmNFT;
    address public admin;
    int24 public tickSpacing;
    int24 public spaceMultiplier;
    address public oracle = 0xf0F8249cA6493AaEbBF971B3a2FD8A2e6736981E;

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

    function _newPool(address newPool) external {
        require(msg.sender == admin, "Only owner can do this");
        pool = newPool;
        token0 = ICLPoolConstants(pool).token0();
        token1 = ICLPoolConstants(pool).token1();
        farmNFT = ICLPoolConstants(pool).nft();
        tickSpacing = ICLPoolConstants(pool).tickSpacing();
    }

    function Swap0for1(uint256 amountIn) public payable {
        require(amountIn > 0, "Invalid input amount");

        IERC20(token0).transferFrom(msg.sender, address(this), amountIn);

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
            msg.sender,     // recipient
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
            msg.sender,     // recipient
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

}