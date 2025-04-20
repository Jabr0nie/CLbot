// SPDX-License-Identifier: MIT
pragma solidity =0.7.6;
pragma abicoder v2;

import "@uniswap/v3-core/contracts/libraries/TickMath.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";
import "@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol";
import "@uniswap/v3-periphery/contracts/base/LiquidityManagement.sol";
import "./interfaces/ICLPool.sol";


interface ICLSwapCallback {
    function uniswapV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata data) external;
}


contract V3Bot is ICLSwapCallback, IERC721Receiver {
    address public pool; // token0/token1 pool address
    address public token0; // token0 on Optimism
    address public token1; // token1 on Optimism
    address public farmNFT;
    address public admin;
    uint24 public poolFee;

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
        poolFee = ICLPoolState(pool).fee();
    }

    function _transferToAdmin(address Token) external {
        uint256 value = IERC20(Token).balanceOf(address(this));
        IERC20(Token).transfer(admin, value);
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
        IERC20(token0).approve(pool, amountIn);

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
        IERC20(token1).approve(pool, amountIn);

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
            IERC20(token0).transfer(pool, uint256(amount0Delta));
        }
        // If amount1Delta > 0, we must pay that amount of token1 to the pool (not expected in token0->token1 swap)
        if (amount1Delta > 0) {
            IERC20(token1).transfer(pool, uint256(amount1Delta));
        }
    }

//https://docs.uniswap.org/contracts/v3/guides/providing-liquidity/mint-a-position
function addLiquidity(uint256 amount0ToMint, uint256 amount1ToMint) external payable returns (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1){
    // Approve the position manager
    //Approve Tokens
        IERC20(token0).approve(farmNFT, amount0ToMint);
        IERC20(token1).approve(farmNFT, amount1ToMint);

        INonfungiblePositionManager.MintParams memory params =
            INonfungiblePositionManager.MintParams({
                token0: token0,
                token1: token1,
                fee: poolFee,
                tickLower: TickMath.MIN_TICK,
                tickUpper: TickMath.MAX_TICK,
                amount0Desired: amount0ToMint,
                amount1Desired: amount1ToMint,
                amount0Min: 0,
                amount1Min: 0,
                recipient: address(this),
                deadline: block.timestamp
            });

        // Note that the pool defined by DAI/USDC and fee tier 0.3% must already be created and initialized in order to mint
        (tokenId, liquidity, amount0, amount1) = INonfungiblePositionManager(farmNFT).mint(params);
        
        // Create a deposit
        _createDeposit(address(this), tokenId);

}

    function onERC721Received(
        address operator,
        address,
        uint256 tokenId,
        bytes calldata
    ) external override returns (bytes4) {
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


}