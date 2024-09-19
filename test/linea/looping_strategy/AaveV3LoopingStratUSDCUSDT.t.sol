pragma solidity ^0.8.19;

import {AaveV3LoopingStrategy, IAaveV3LoopingStrategy, IAToken} from '../../../contracts/AaveV3LoopingStrategy.sol';
import {LynexSwapper, ILynexRouter} from '../../../contracts/LynexSwapper.sol';
import {IERC20} from '@openzeppelin-contracts/token/ERC20/IERC20.sol';

import {Constants} from '../Constants.sol';
import {BaseTest} from './BaseTest.sol';
import {Vm, console} from 'forge-std/Test.sol';

interface IDebtToken {
    function UNDERLYING_ASSET_ADDRESS() external view returns (address);

    function balanceOf(address account) external view returns (uint);

    function approveDelegation(address delegatee, uint amount) external;
}

interface IPool {
    function FLASHLOAN_PREMIUM_TOTAL() external view returns (uint);
}

// note: use lynex swapper for testing
//       other swappers are testes as unit tests
contract AaveV3LoopingStratUSDCUSDTTest is BaseTest {
    function setUp() public {
        collPool = Constants.A_USDC;
        debtPool = Constants.D_USDT;
        _setUp();
    }

    // increase pos (tokenIn = collToken)
    function testIncreasePosCollToken(uint seed0) public {
        uint usdIn = bound(seed0, 10, 1_000_000);
        _increasePos(Constants.ALICE, collToken, usdIn, usdIn);
    }

    // increase pos (tokenIn = debtToken)
    function testIncreasePosDebtToken(uint seed0) public {
        uint usdIn = bound(seed0, 10, 1_000_000);
        _increasePos(Constants.ALICE, debtToken, usdIn, usdIn);
    }

    // increase pos (slippage)
    function testIncreaseSlippage() public {
        address user = Constants.ALICE;
        // deal token
        uint amtIn = _getTokenAmtFromUSD(debtToken, 100);
        deal(debtToken, user, amtIn);
        // prepare params
        uint debtAmt = _getTokenAmtFromUSD(debtToken, 100);
        ILynexRouter.route[] memory routes = new ILynexRouter.route[](1);
        routes[0] = ILynexRouter.route({from: debtToken, to: collToken, stable: false});
        bytes memory data = abi.encode(routes, block.timestamp);
        IAaveV3LoopingStrategy.IncreasePosParams memory params = IAaveV3LoopingStrategy.IncreasePosParams({
            tokenIn: debtToken,
            amtIn: amtIn,
            collPool: collPool,
            borrPool: debtPool,
            borrAmt: debtAmt,
            swapInfo: IAaveV3LoopingStrategy.SwapInfo({swapper: swapper, slippage: type(uint).max, data: data})
        });
        vm.startPrank(user, user);
        vm.expectRevert('AaveV3LoopingStrategy: insufficient amtOut');
        // call increase position
        IAaveV3LoopingStrategy(loopStrat).increasePos(params);
        vm.stopPrank();
    }

    // decrease pos (tokenOut = collToken)
    function testDecreasePosCollToken(uint seed0, uint seed1) public {
        uint usdIn = bound(seed0, 10, 1_000_000);
        address user = Constants.ALICE;
        // increase pos
        _increasePos(user, collToken, usdIn, usdIn);
        // prepare params
        skip(1000);
        uint divisor = bound(seed1, 2, 100);
        uint collAmt = IERC20(collPool).balanceOf(user) / divisor;
        uint repayAmt = IERC20(debtPool).balanceOf(user) / divisor;
        _decreasePos(user, collAmt, repayAmt, collToken);
    }

    // decrease pos (tokenOut = collToken have dust in contract)
    function testDecreasePosCollTokenDust(uint seed0, uint seed1) public {
        // add dust
        deal(debtToken, loopStrat, 1);
        deal(collToken, loopStrat, 1);
        // decrease pos (tokenOut = collToken)
        testDecreasePosCollToken(seed0, seed1);
    }

    // decrease pos (tokenOut = collToken slippage swap)
    function testDecreasePosCollTokenSlippageSwap() public {
        address user = Constants.ALICE;
        // increase pos
        _increasePos(user, collToken, 100, 100);
        // prepare params
        skip(1000);
        uint collAmt = IERC20(collPool).balanceOf(user) / 2;
        uint repayAmt = IERC20(debtPool).balanceOf(user) / 2;
        address tokenOut = collToken;
        // prepare params
        ILynexRouter.route[] memory routes = new ILynexRouter.route[](1);
        routes[0] = ILynexRouter.route({from: collToken, to: debtToken, stable: false});
        bytes memory data = abi.encode(routes, block.timestamp);
        IAaveV3LoopingStrategy.DecreasePosParams memory params = IAaveV3LoopingStrategy.DecreasePosParams({
            collPool: collPool,
            collAmt: collAmt,
            borrPool: debtPool,
            debtAmt: repayAmt,
            tokenOut: tokenOut,
            swapInfo: IAaveV3LoopingStrategy.SwapInfo({swapper: swapper, slippage: 0, data: data})
        });
        vm.startPrank(user, user);
        vm.expectRevert('AaveV3LoopingStrategy: exceed maxAmtIn');
        // call decrease position
        IAaveV3LoopingStrategy(loopStrat).decreasePos(params);
        vm.stopPrank();
    }

    // decrease pos (tokenOut = debtToken)
    function testDecreasePosDebtToken(uint seed0, uint seed1) public {
        uint usdIn = bound(seed0, 10, 1_000_000);
        address user = Constants.ALICE;
        // increase pos
        _increasePos(user, collToken, usdIn, usdIn);
        // prepare params
        skip(1000);
        uint divisor = bound(seed1, 2, 100);
        uint collAmt = IERC20(collPool).balanceOf(user) / divisor;
        uint repayAmt = IERC20(debtPool).balanceOf(user) / divisor;
        _decreasePos(user, collAmt, repayAmt, debtToken);
    }

    // decrease pos (tokenOut = debtToken dust)
    function testDecreasePosDebtTokenDust(uint seed0, uint seed1) public {
        // add dust
        deal(debtToken, loopStrat, 1);
        deal(collToken, loopStrat, 1);
        // decrease pos (tokenOut = debtToken)
        testDecreasePosDebtToken(seed0, seed1);
    }

    // decrease pos (tokenOut = debtToken slippage swap)
    function testDecreasePosDebtTokenSlippageSwap() public {
        address user = Constants.ALICE;
        // increase pos
        _increasePos(user, collToken, 100, 100);
        // prepare params
        skip(1000);
        uint collAmt = IERC20(collPool).balanceOf(user) / 2;
        uint repayAmt = IERC20(debtPool).balanceOf(user) / 2;
        address tokenOut = debtToken;
        // prepare params
        ILynexRouter.route[] memory routes = new ILynexRouter.route[](1);
        routes[0] = ILynexRouter.route({from: collToken, to: debtToken, stable: false});
        bytes memory data = abi.encode(routes, block.timestamp);
        IAaveV3LoopingStrategy.DecreasePosParams memory params = IAaveV3LoopingStrategy.DecreasePosParams({
            collPool: collPool,
            collAmt: collAmt,
            borrPool: debtPool,
            debtAmt: repayAmt,
            tokenOut: tokenOut,
            swapInfo: IAaveV3LoopingStrategy.SwapInfo({swapper: swapper, slippage: type(uint).max, data: data})
        });
        vm.startPrank(user, user);
        vm.expectRevert('AaveV3LoopingStrategy: insufficient amtOut');
        // call decrease position
        IAaveV3LoopingStrategy(loopStrat).decreasePos(params);
        vm.stopPrank();
    }

    // increase leverage
    function testDecrerasePosIncreaseLeverage(uint seed0) public {
        uint usdIn = bound(seed0, 10, 1_000_000);
        address user = Constants.ALICE;
        // increase pos
        _increasePos(user, collToken, usdIn, usdIn);
        // prepare params
        skip(1000);
        uint collAmt = IERC20(collPool).balanceOf(user) * 51 / 100;
        uint repayAmt = IERC20(debtPool).balanceOf(user) * 50 / 100;
        _decreasePos(user, collAmt, repayAmt, debtToken);
    }

    // decrease leverage
    function testDecrerasePosDecreaseLeverage(uint seed0) public {
        uint usdIn = bound(seed0, 10, 1_000_000);
        address user = Constants.ALICE;
        // increase pos
        _increasePos(user, collToken, usdIn, usdIn);
        // prepare params
        skip(1000);
        uint collAmt = IERC20(collPool).balanceOf(user) * 20 / 100;
        uint repayAmt = IERC20(debtPool).balanceOf(user) * 21 / 100;
        _decreasePos(user, collAmt, repayAmt, debtToken);
    }

    // close pos
    function testClosePos() public {
        address user = Constants.ALICE;
        // increase pos
        _increasePos(user, collToken, 100, 100);
        // prepare params
        skip(1000);
        uint collAmt = IERC20(collPool).balanceOf(user);
        uint repayAmt = IERC20(debtPool).balanceOf(user);
        _decreasePos(user, collAmt, repayAmt, debtToken);
        assertEq(IERC20(collPool).balanceOf(user), 0, 'coll pool not withdrawn');
        assertEq(IERC20(debtPool).balanceOf(user), 0, 'debt not repaid');
    }

    // repay debt with collateral
    function testRepayDebtWithCollateral(uint seed0, uint seed1) public {
        uint usdIn = bound(seed0, 10, 1_000_000);
        address user = Constants.ALICE;
        // increase pos
        _increasePos(user, collToken, usdIn, usdIn);
        // prepare params
        skip(1000);
        uint divisor = bound(seed1, 2, 100);
        uint collAmt = IERC20(collPool).balanceOf(user) / divisor;
        uint repayAmt = IERC20(debtPool).balanceOf(user) / divisor;
        _repayDebtWithCollateral(user, collAmt, repayAmt);
    }

    // repay total debt with collateral
    function testRepayDebtWithCollateralTotalDebt(uint seed0) public {
        uint usdIn = bound(seed0, 10, 1_000_000);
        address user = Constants.ALICE;
        // increase pos
        _increasePos(user, collToken, usdIn, usdIn);
        // prepare params
        skip(1000);
        uint collAmt = IERC20(collPool).balanceOf(user);
        uint repayAmt = IERC20(debtPool).balanceOf(user);
        _repayDebtWithCollateral(user, collAmt, repayAmt);
    }

    // repay total debt with collateral (slippage)
    function testRepayDebtWithCollateralSlippage() public {
        address user = Constants.ALICE;
        // increase pos
        _increasePos(user, collToken, 100, 100);
        // prepare params
        skip(1000);
        uint collAmt = IERC20(collPool).balanceOf(user);
        uint repayAmt = IERC20(debtPool).balanceOf(user);
        // prepare params
        ILynexRouter.route[] memory routes = new ILynexRouter.route[](1);
        routes[0] = ILynexRouter.route({from: collToken, to: debtToken, stable: false});
        bytes memory data = abi.encode(routes, block.timestamp);
        IAaveV3LoopingStrategy.RepayDebtWithCollateralParams memory params = IAaveV3LoopingStrategy
            .RepayDebtWithCollateralParams({
            collPool: collPool,
            collAmt: collAmt,
            borrPool: debtPool,
            debtAmt: repayAmt,
            swapInfo: IAaveV3LoopingStrategy.SwapInfo({swapper: swapper, slippage: 0, data: data})
        });
        vm.startPrank(user, user);
        vm.expectRevert('AaveV3LoopingStrategy: exceed maxAmtIn');
        // call repay debt with collateral
        IAaveV3LoopingStrategy(loopStrat).repayDebtWithCollateral(params);
        vm.stopPrank();
    }
}
