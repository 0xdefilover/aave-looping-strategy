// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IERC20} from '@openzeppelin-contracts/token/ERC20/IERC20.sol';
import {SafeERC20} from '@openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol';
import {ISwapper} from './interfaces/ISwapper.sol';

interface ILynexRouter {
    struct route {
        address from;
        address to;
        bool stable;
    }

    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        route[] calldata routes,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);
}

contract LynexSwapper is ISwapper {
    using SafeERC20 for IERC20;

    address public immutable ROUTER;

    constructor(address router) {
        ROUTER = router;
    }

    function swapExactIn(SwapExactInParams memory swapParams) external {
        // decode data
        (ILynexRouter.route[] memory routes, uint deadline) = abi.decode(swapParams.data, (ILynexRouter.route[], uint));
        // approve token in for router
        uint balance = IERC20(swapParams.from).balanceOf(address(this));
        _ensureApprove(swapParams.from, balance);
        // note: caller need to check slippage by themselves
        // call lynex router to swap exact in
        ILynexRouter(ROUTER).swapExactTokensForTokens(balance, 0, routes, msg.sender, deadline);
    }

    function swapExactOut(SwapExactOutParams memory swapParams) external {
        // pseudo-swapExactOut
        // note: overestimate slippage might cause expensive swap fee
        // 1. swap exact in with balance
        // 2. swap excess token out back to tokenIn
        // decode data
        (ILynexRouter.route[] memory routes, uint deadline) = abi.decode(swapParams.data, (ILynexRouter.route[], uint));
        // approve token in for router
        uint amtIn = IERC20(swapParams.from).balanceOf(address(this)); // using balnce as amtIn
        _ensureApprove(swapParams.from, amtIn);
        // call lynex router to swap exact in
        // note: caller need to check slippage by themselves
        ILynexRouter(ROUTER).swapExactTokensForTokens(amtIn, swapParams.amtOut, routes, address(this), deadline);
        // check if swap excess exact amt out or not
        uint balance = IERC20(swapParams.to).balanceOf(address(this));
        if (balance >= swapParams.amtOut) {
            uint excessAmt = balance - swapParams.amtOut;
            // reverse routes
            ILynexRouter.route[] memory reversedRoutes = _reverseRoutes(routes);
            // approve token out for router
            _ensureApprove(swapParams.to, excessAmt);
            // call lynex router to swap exact in
            // note: caller need to check slippage by themselves
            ILynexRouter(ROUTER).swapExactTokensForTokens(excessAmt, 0, reversedRoutes, msg.sender, deadline);
        }
        // return tokenOut to msg.sender
        balance = IERC20(swapParams.to).balanceOf(address(this));
        if (balance > 0) IERC20(swapParams.to).safeTransfer(msg.sender, balance);
    }

    function _ensureApprove(address token, uint amt) internal {
        if (IERC20(token).allowance(address(this), ROUTER) < amt) {
            IERC20(token).approve(ROUTER, type(uint).max);
        }
    }

    function _reverseRoutes(ILynexRouter.route[] memory routes)
        internal
        pure
        returns (ILynexRouter.route[] memory reversedRoutes)
    {
        reversedRoutes = new ILynexRouter.route[](routes.length);
        for (uint i; i < routes.length; ++i) {
            uint reversedRoutesIdx = routes.length - 1 - i;
            // switch from and to
            reversedRoutes[i] = ILynexRouter.route({
                from: routes[reversedRoutesIdx].to,
                to: routes[reversedRoutesIdx].from,
                stable: routes[reversedRoutesIdx].stable
            });
        }
    }
}
