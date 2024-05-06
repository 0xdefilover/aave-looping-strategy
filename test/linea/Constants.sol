// SPDX-License-Identifier: MIT 
pragma solidity ^0.8.19;

library Constants {
    // === users ===
    address public constant ALICE = address(0xA11CE);
    address public constant BOB = address(0xB0B);

    // === tokens ===
    address public constant WETH = 0xe5D7C2a44FfDDf6b295A15c148167daaAf5Cf34f;
    address public constant WBTC = 0x3aAB2285ddcDdaD8edf438C1bAB47e1a9D05a9b4;

    // === zero lend address ===
    // core
    address public constant AAVE_ORACLE = 0xFF679e5B4178A2f74A56f0e2c0e1FA1C80579385;
    address public constant AAVE_LENDING_POOL = 0x2f9bB73a8e98793e26Cb2F6C4ad037BDf1C6B269;
    // aTokens
    address public constant A_ETH = 0xB4FFEf15daf4C02787bC5332580b838cE39805f5;
    address public constant A_USDC = 0x2E207ecA8B6Bf77a6ac82763EEEd2A94de4f081d;
    address public constant A_USDT = 0x508C39Cd02736535d5cB85f3925218E5e0e8F07A;
    address public constant A_WBTC = 0x8B6E58eA81679EeCd63468c6D4EAefA48A45868D;
    // debtTokens
    address public constant D_ETH = 0xCb2dA0F5aEce616e2Cbf29576CFc795fb15c6133;
    address public constant D_USDC = 0xa2703Dc9FbACCD6eC2e4CBfa700989D0238133f6;
    address public constant D_USDT = 0x476F206511a18C9956fc79726108a03E647A1817;
    address private constant D_WBTC = 0xF61a1d02103958b8603f1780702982E2ec9F9E68;

    // === lynex ===
    address public constant LYNEX_ROUTER = 0x610D2f07b7EdC67565160F587F37636194C34E74;
}
