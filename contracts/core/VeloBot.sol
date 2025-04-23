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
}


contract V3Bot is ICLSwapCallback {
    address public pool; // token0/token1 pool address
    address public token0; // token0 on Optimism
    address public token1; // token1 on Optimism
    address public farmNFT;
    address public admin;
    int24 public tickSpacing;

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

    function _transferToAdmin(address Token) external {
        uint256 value = IERC20Minimal(Token).balanceOf(address(this));
        IERC20Minimal(Token).transfer(admin, value);
    }

    function Swap0for1(uint256 amountIn) external {
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

    function V3Swap1for0(uint256 amountIn) external {
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

function addLiquidity(uint256 amount0ToMint, uint256 amount1ToMint) external payable returns (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1){
    // Approve the position manager

    // Get current sqrtPriceX96 from the pool
        (uint160 sqrtPriceX96, int24 currenttick, , , , ) = ICLPoolState(pool).slot0();
        currenttick = (currenttick / tickSpacing) * tickSpacing;
        uint160 sqrtPriceX96A;

    //Approve Tokens
        IERC20Minimal(token0).approve(farmNFT, amount0ToMint);
        IERC20Minimal(token1).approve(farmNFT, amount1ToMint);

        INonfungiblePositionManager.MintParams memory params =
            INonfungiblePositionManager.MintParams({
                token0: token0,
                token1: token1,
                tickSpacing: tickSpacing,
                tickLower: TickMath.MIN_TICK, //add custom logic
                tickUpper: TickMath.MAX_TICK, //add custom logic
                amount0Desired: amount0ToMint,
                amount1Desired: amount1ToMint,
                amount0Min: 0,
                amount1Min: 0,
                recipient: address(this),
                deadline: block.timestamp,
                sqrtPriceX96: sqrtPriceX96
            });


        (tokenId, liquidity, amount0, amount1) = INonfungiblePositionManager(farmNFT).mint(params);
        

        _createDeposit(address(this), tokenId);

}

    function onERC721Received(
        address operator,
        address,
        uint256 tokenId,
        bytes calldata
    ) external returns (bytes4) {
        // get position information
        _createDeposit(operator, tokenId);
        return this.onERC721Received.selector;
    }

        function _createDeposit(address owner, uint256 tokenId) internal {
        (, , address _token0, address _token1, , , , uint128 liquidity, , , , ) =
            INonfungiblePositionManager(farmNFT).positions(tokenId);

        // set the owner and data for position
        // operator is msg.sender
        deposits[tokenId] = Deposit({owner: owner, liquidity: liquidity, token0: _token0, token1: _token1});
    }

        // Get current sqrtPriceX96 from the pool
        function _checkLiquidity() external view returns (uint amount0, uint amount1){

        (uint160 sqrtPriceX96, int24 currentTick, , , , ) = ICLPoolState(pool).slot0();
        currentTick = (currentTick / tickSpacing) * tickSpacing;
        int24 lowTick = currentTick - tickSpacing;
        int24 highTick = currentTick + tickSpacing;
        uint160 sqrtPriceX96A = TickMath.getSqrtRatioAtTick(lowTick);
        uint160 sqrtPriceX96B = TickMath.getSqrtRatioAtTick(highTick);

        //In procee = need to balance of this address for token0 and 1 and then...
 (uint liquidity) = getLiquidityForAmounts(sqrtRatioX96, sqrtRatioX96A, sqrtRatioX96B, amount0, amount1)
    ) internal pure returns (uint128 liquidity)

    }
}