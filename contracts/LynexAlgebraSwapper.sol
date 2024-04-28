// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IERC20} from '@openzeppelin-contracts/token/ERC20/IERC20.sol';
import {SafeERC20} from '@openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol';
import {ISwapper} from './interfaces/ISwapper.sol';

interface ILynexAlgebraRouter {
    struct ExactInputParams {
        bytes path;
        address recipient;
        uint deadline;
        uint amountIn;
        uint amountOutMinimum;
    }

    /// @notice Swaps `amountIn` of one token for as much as possible of another along the specified path
    /// @param params The parameters necessary for the multi-hop swap, encoded as `ExactInputParams` in calldata
    /// @return amountOut The amount of the received token
    function exactInput(ExactInputParams calldata params) external payable returns (uint amountOut);

    struct ExactOutputParams {
        bytes path;
        address recipient;
        uint deadline;
        uint amountOut;
        uint amountInMaximum;
    }

    /// @notice Swaps as little as possible of one token for `amountOut` of another along the specified path (reversed)
    /// @param params The parameters necessary for the multi-hop swap, encoded as `ExactOutputParams` in calldata
    /// @return amountIn The amount of the input token
    function exactOutput(ExactOutputParams calldata params) external payable returns (uint amountIn);
}

contract LynexAlgebraSwapper is ISwapper {
    using SafeERC20 for IERC20;

    address public immutable ROUTER;

    constructor(address router) {
        ROUTER = router;
    }

    function swapExactIn(SwapExactInParams memory swapParams) external {
        // decode data
        (bytes memory path, uint deadline) = abi.decode(swapParams.data, (bytes, uint));
        // approve token in for router
        uint balance = IERC20(swapParams.from).balanceOf(address(this));
        _ensureApprove(swapParams.from, balance);

        // construct new swap data
        // note: caller need to check slippage by themselves
        ILynexAlgebraRouter.ExactInputParams memory exactInputParams = ILynexAlgebraRouter.ExactInputParams({
            path: path,
            recipient: msg.sender,
            deadline: deadline,
            amountIn: balance,
            amountOutMinimum: 0
        });

        // call lynex router to swap exact in
        ILynexAlgebraRouter(ROUTER).exactInput(exactInputParams);
    }

    function swapExactOut(SwapExactOutParams memory swapParams) external {
        // decode data
        (bytes memory path, uint deadline) = abi.decode(swapParams.data, (bytes, uint));
        // approve token in for router
        uint balance = IERC20(swapParams.from).balanceOf(address(this));
        _ensureApprove(swapParams.from, balance);

        // construct new swap data
        // note: caller need to check slippage by themselves
        ILynexAlgebraRouter.ExactOutputParams memory exactOutputParams = ILynexAlgebraRouter.ExactOutputParams({
            path: path,
            recipient: msg.sender,
            deadline: deadline,
            amountOut: swapParams.amtOut,
            amountInMaximum: balance
        });

        // call lynex router to swap exact out
        ILynexAlgebraRouter(ROUTER).exactOutput(exactOutputParams);

        // in case transfered to the contract more than amt, transfer leftover tokenIn to msg.sender
        balance = IERC20(swapParams.from).balanceOf(address(this));
        if (balance > 0) IERC20(swapParams.from).safeTransfer(msg.sender, balance);
    }

    function _ensureApprove(address token, uint amt) internal {
        if (IERC20(token).allowance(address(this), ROUTER) < amt) {
            IERC20(token).safeApprove(ROUTER, type(uint).max);
        }
    }
}
