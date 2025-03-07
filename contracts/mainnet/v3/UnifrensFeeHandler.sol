 // SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

contract UnifrensFeeHandler is Ownable {
    using SafeERC20 for IERC20;

    ISwapRouter public immutable swapRouter;
    address public immutable WETH;
    address public targetToken;
    uint24 public constant POOL_FEE = 3000; // 0.3% fee tier

    constructor(
        address _swapRouter,
        address _weth,
        address _targetToken
    ) Ownable(msg.sender) {
        swapRouter = ISwapRouter(_swapRouter);
        WETH = _weth;
        targetToken = _targetToken;
    }

    /// @dev Receive ETH and swap for target token
    receive() external payable {
        if (msg.value > 0) {
            _swapExactInputSingle(msg.value);
        }
    }

    /// @dev Swap exact ETH for target token
    function _swapExactInputSingle(uint256 amountIn) internal {
        // Approve the router to spend WETH
        IERC20(WETH).approve(address(swapRouter), amountIn);

        // Create the swap parameters
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter
            .ExactInputSingleParams({
                tokenIn: WETH,
                tokenOut: targetToken,
                fee: POOL_FEE,
                recipient: owner(),
                deadline: block.timestamp + 15 minutes,
                amountIn: amountIn,
                amountOutMinimum: 0, // Accept any amount of tokens
                sqrtPriceLimitX96: 0
            });

        // Execute the swap
        swapRouter.exactInputSingle(params);
    }

    /// @dev Set new target token
    function setTargetToken(address _targetToken) external onlyOwner {
        require(_targetToken != address(0), "Invalid token address");
        targetToken = _targetToken;
    }

    /// @dev Emergency withdraw ETH
    function withdrawETH() external onlyOwner {
        uint256 balance = address(this).balance;
        require(balance > 0, "No ETH to withdraw");
        payable(owner()).transfer(balance);
    }

    /// @dev Emergency withdraw tokens
    function withdrawToken(address token) external onlyOwner {
        require(token != address(0), "Invalid token address");
        uint256 balance = IERC20(token).balanceOf(address(this));
        require(balance > 0, "No tokens to withdraw");
        IERC20(token).safeTransfer(owner(), balance);
    }
}