// SPDX-License-Identifier: MIT
pragma solidity =0.7.6;
pragma abicoder v2;

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

interface Oracle {
    function GetPrice(address pooladdress) external view returns (uint256 price);
    function getAmountsforLiquidity(address pool, uint256 usdAmount) external view returns (uint amount0, uint amount1);
}

interface Bot {
    function tokenId() external view returns (uint256);
    function token0() external view returns (address);
    function token1() external view returns (address);
    function tickSpacing() external view returns (int24);
    function farmNFT() external view returns (address);
}


contract BRAIN {

    address public admin;
    address public oracle;
    address public bot;
    address public token0; // token0 on Optimism
    address public token1; // token1 on Optimism
    address public farmNFT;
    uint256 public tokenId;
    int24 public tickSpacing;

    constructor() {
        admin = msg.sender;
    }


    function _newAdmin(address newAdmin) external {
        require(msg.sender == admin, "Only owner can do this");
        admin = newAdmin;
    }


    function _newBot(address newBot) external {
        require(msg.sender == admin, "Only owner can do this");
        bot = newBot;
        token0 = Bot(bot).token0();
        token1 = Bot(bot).token1();
        farmNFT = Bot(bot).farmNFT();
        tickSpacing = Bot(bot).tickSpacing();
    }

    function _newOracle(address newOracle) external {
        require(msg.sender == admin, "Only owner can do this");
        oracle = newOracle;
    }



}
 