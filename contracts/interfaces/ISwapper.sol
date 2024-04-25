// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface ISwapper {
    struct SwapExactInParams {
        address from; // token to swap from
        address to; // token to swap to
        bytes data; // swap data (ex: path, deadline, etc.)
    }

    struct SwapExactOutParams {
        address from; // token to swap from
        address to; // token to swap to
        uint amtOut; // amt to receive
        bytes data; // swap data (ex: path, deadline, etc.)
    }

    /// @notice using balanceOf of swapper contract to swap. caller need to check slippage by themselves
    function swapExactIn(SwapExactInParams calldata data) external;

    /// @notice using balanceOf of swapper contract to swap. caller need to check slippage by themselves
    function swapExactOut(SwapExactOutParams calldata data) external;

    function ROUTER() external returns (address);
}
