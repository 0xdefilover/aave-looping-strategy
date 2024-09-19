// SPDX-License-Identifier: MIT 
pragma solidity ^0.8.19;

import {IERC20} from '@openzeppelin-contracts/token/ERC20/IERC20.sol';
import {IERC20Metadata} from '@openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol';
import {Constants} from '../Constants.sol';
import {AaveV3LoopingStrategy, IAaveV3LoopingStrategy, IAToken} from '../../../contracts/AaveV3LoopingStrategy.sol';
import {LynexSwapper} from '../../../contracts/LynexSwapper.sol';

import {Test, Vm, console} from 'forge-std/Test.sol';

interface IAaveOracle {
    function getAssetPrice(address token) external view returns (uint);
}

interface IPool {
    function flashLoan(
        address receiver,
        address[] calldata assets,
        uint[] calldata amts,
        uint[] calldata modes,
        address onBehalfOf,
        bytes calldata params,
        uint16 referralCode
    ) external;

    function supply(address asset, uint amount, address onBehalfOf, uint16 referralCode) external;

    function repay(address asset, uint amount, uint interestRateMode, address onBehalfOf) external returns (uint);

    function withdraw(address asset, uint amount, address to) external returns (uint);

    function FLASHLOAN_PREMIUM_TOTAL() external view returns (uint);
}

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

    function addLiquidity(
        address tokenA,
        address tokenB,
        bool stable,
        uint amountADesired,
        uint amountBDesired,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external returns (uint amountA, uint amountB, uint liquidity);
}

interface IDebtToken {
    function UNDERLYING_ASSET_ADDRESS() external view returns (address);

    function balanceOf(address account) external view returns (uint);

    function approveDelegation(address delegatee, uint amount) external;
}

contract BaseTest is Test {
    address loopStrat;
    address swapper;
    address collPool;
    address collToken;
    address debtPool;
    address debtToken;

    function _setUp() internal {
        vm.createSelectFork(vm.rpcUrl('linea'), 8998125);
        loopStrat = address(new AaveV3LoopingStrategy(Constants.AAVE_LENDING_POOL, Constants.WETH));
        swapper = address(new LynexSwapper(Constants.LYNEX_ROUTER));
        address underlying_asset = IAToken(collPool).UNDERLYING_ASSET_ADDRESS();
        collToken = underlying_asset == address(0) ? Constants.WETH : underlying_asset;
        debtToken = IDebtToken(debtPool).UNDERLYING_ASSET_ADDRESS();
        // init lynex pool liquidity
        _addLiquidityLynex(Constants.BOB, collToken, debtToken, false);
        // init lending pool liquidity
        _addLiquidityLending(Constants.BOB, debtToken);
        _approveForStrat(Constants.ALICE);
    }

    function _getTokenAmtFromUSD(address token, uint usd) internal view returns (uint) {
        // getPrice from oracle
        uint pricePerTokenE8 = IAaveOracle(Constants.AAVE_ORACLE).getAssetPrice(token);
        // use 1e36 for precision to be able to very low price token in 18 decimals
        uint pricePerTokenE36 = pricePerTokenE8 * 1e28;
        uint decimal = IERC20Metadata(token).decimals();
        uint pricePerWeiE36 = pricePerTokenE36 / (10 ** decimal);
        return usd * 1e36 / pricePerWeiE36;
    }

    // add liquidity lynex pool
    function _addLiquidityLynex(address user, address tokenA, address tokenB, bool stable) internal {
        uint amtA = _getTokenAmtFromUSD(tokenA, 100_000_000);
        uint amtB = _getTokenAmtFromUSD(tokenB, 100_000_000);
        deal(tokenA, user, amtA);
        deal(tokenB, user, amtB);
        vm.startPrank(user, user);
        IERC20(tokenA).approve(Constants.LYNEX_ROUTER, amtA);
        IERC20(tokenB).approve(Constants.LYNEX_ROUTER, amtB);
        ILynexRouter(Constants.LYNEX_ROUTER).addLiquidity(
            tokenA, tokenB, stable, amtA, amtB, 0, 0, user, block.timestamp
        );
        vm.stopPrank();
    }

    // add liquidity to lending pool
    function _addLiquidityLending(address user, address token) internal {
        uint amt = _getTokenAmtFromUSD(token, 100_000_000);
        deal(token, user, amt);
        vm.startPrank(user, user);
        IERC20(token).approve(Constants.AAVE_LENDING_POOL, amt);
        IPool(Constants.AAVE_LENDING_POOL).supply(token, amt, user, 0);
        vm.stopPrank();
    }

    function _approveForStrat(address user) internal {
        vm.startPrank(user, user);
        // approve collPool to loopStrat
        IERC20(collPool).approve(loopStrat, type(uint).max);
        // approve collToken to loopStrat
        IERC20(collToken).approve(loopStrat, type(uint).max);
        // delegate to debt to loopStrat
        IDebtToken(debtPool).approveDelegation(loopStrat, type(uint).max);
        // approve debtToken to loopStrat
        IERC20(debtToken).approve(loopStrat, type(uint).max);
        vm.stopPrank();
    }

    function _increasePos(address user, address tokenIn, uint usdIn, uint borrUsd) internal {
        // deal token
        uint amtIn = _getTokenAmtFromUSD(tokenIn, usdIn);
        deal(tokenIn, user, amtIn);
        // prepare params
        uint debtAmt = _getTokenAmtFromUSD(debtToken, borrUsd);
        bytes memory data;
        {
            ILynexRouter.route[] memory routes = new ILynexRouter.route[](1);
            routes[0] = ILynexRouter.route({from: debtToken, to: collToken, stable: false});
            data = abi.encode(routes, block.timestamp);
        }
        IAaveV3LoopingStrategy.IncreasePosParams memory params = IAaveV3LoopingStrategy.IncreasePosParams({
            tokenIn: tokenIn,
            amtIn: amtIn,
            collPool: collPool,
            borrPool: debtPool,
            borrAmt: debtAmt,
            swapInfo: IAaveV3LoopingStrategy.SwapInfo({swapper: swapper, slippage: 0, data: data})
        });
        uint collPoolBalBf = IERC20(collPool).balanceOf(user);
        uint debtBalBf = IDebtToken(debtPool).balanceOf(user);
        uint dustBalBf = IERC20(debtToken).balanceOf(loopStrat);
        vm.startPrank(user, user);
        // call increase position
        vm.recordLogs();
        IAaveV3LoopingStrategy(loopStrat).increasePos(params);
        vm.stopPrank();
        Vm.Log[] memory entries = vm.getRecordedLogs();
        _checkIncreaseEvent(entries, user, collPoolBalBf, debtAmt);
        _checkSwapIncreasePosEvent(
            entries, user, (tokenIn == debtToken ? amtIn + debtAmt : debtAmt) + dustBalBf, collPoolBalBf
        );
        assertGe(IERC20(collPool).balanceOf(user) - collPoolBalBf, 0, 'bad coll balance');
        assertApproxEqAbs(IDebtToken(debtPool).balanceOf(user) + debtBalBf, debtAmt, 1, 'bad debt balance');
    }

    function _decreasePos(address user, uint collAmt, uint repayAmt, address tokenOut) internal {
        // prepare params
        bytes memory data;
        {
            ILynexRouter.route[] memory routes = new ILynexRouter.route[](1);
            routes[0] = ILynexRouter.route({from: collToken, to: debtToken, stable: false});
            data = abi.encode(routes, block.timestamp);
        }
        uint slippage = tokenOut == collToken ? type(uint).max : 0;
        IAaveV3LoopingStrategy.DecreasePosParams memory params = IAaveV3LoopingStrategy.DecreasePosParams({
            collPool: collPool,
            collAmt: collAmt,
            borrPool: debtPool,
            debtAmt: repayAmt,
            tokenOut: tokenOut,
            swapInfo: IAaveV3LoopingStrategy.SwapInfo({swapper: swapper, slippage: slippage, data: data})
        });
        uint collPoolBalBf = IERC20(collPool).balanceOf(user);
        uint debtBalBf = IDebtToken(debtPool).balanceOf(user);
        uint collTokenBalBf = IERC20(collToken).balanceOf(user);
        uint tokenOutBalBf = IERC20(tokenOut).balanceOf(user);
        vm.startPrank(user, user);
        // call decrease position
        vm.recordLogs();
        IAaveV3LoopingStrategy(loopStrat).decreasePos(params);
        vm.stopPrank();
        Vm.Log[] memory entries = vm.getRecordedLogs();
        _checkDecreaseEvent(entries, user, collPoolBalBf, debtBalBf, tokenOut, tokenOutBalBf);
        assertApproxEqAbs(collPoolBalBf - IERC20(collPool).balanceOf(user), collAmt, 1, 'bad collPool balance');
        assertApproxEqAbs(debtBalBf - IDebtToken(debtPool).balanceOf(user), repayAmt, 1, 'bad debt balance');
        assertGe(IERC20(collToken).balanceOf(user), collTokenBalBf, 'bad collToken balance');
        require(IERC20(collToken).balanceOf(loopStrat) == 0, 'coll token balance not 0');
        require(IERC20(debtToken).balanceOf(loopStrat) == 0, 'debt token balance not 0');
    }

    function _repayDebtWithCollateral(address user, uint collAmt, uint repayAmt) internal {
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
            swapInfo: IAaveV3LoopingStrategy.SwapInfo({swapper: swapper, slippage: type(uint).max, data: data})
        });

        uint collPoolBalBf = IERC20(collPool).balanceOf(user);
        uint debtBalBf = IDebtToken(debtPool).balanceOf(user);
        uint collTokenBalBf = IERC20(collToken).balanceOf(user);
        vm.startPrank(user, user);
        vm.recordLogs();
        // call repay debt with collateral
        IAaveV3LoopingStrategy(loopStrat).repayDebtWithCollateral(params);
        vm.stopPrank();
        Vm.Log[] memory entries = vm.getRecordedLogs();
        _checkRepayDebtWithCollateralEvent(entries, user, collPoolBalBf, debtBalBf);
        _checkSwapEmittedRepayDebtWithCollateral(entries, user, collPoolBalBf, debtBalBf);
        assertGe(IERC20(collPool).balanceOf(user), collPoolBalBf - collAmt, 'bad collPool balance');
        assertEq(collTokenBalBf, IERC20(collToken).balanceOf(user), 'bad coll token balance');
        assertApproxEqAbs(debtBalBf - IDebtToken(debtPool).balanceOf(user), repayAmt, 1, 'bad debt balance');
    }

    function _checkIncreaseEvent(Vm.Log[] memory logs, address user, uint collPoolBalBf, uint debtAmt) internal view {
        bool isEmmitted;
        for (uint i; i < logs.length; i++) {
            // find log
            if (logs[i].topics[0] == keccak256('IncreasePos(address,address,uint256,address,uint256)')) {
                (address _collPool, uint _collAmt, address _borrPool, uint _debtAmt) =
                    abi.decode(logs[i].data, (address, uint, address, uint));
                assertEq(logs[i].topics[1], bytes32(uint(uint160(user))), 'bad user');
                assertEq(_collPool, collPool, 'bad coll pool');
                assertApproxEqAbs(_collAmt, IERC20(collPool).balanceOf(user) - collPoolBalBf, 1, 'bad coll amount');
                assertEq(_borrPool, debtPool, 'bad borr pool');
                assertApproxEqAbs(_debtAmt, debtAmt, 1, 'bad debt amount');

                isEmmitted = true;
            }
        }
        require(isEmmitted, 'IncreasePos not emitted');
    }

    function _checkDecreaseEvent(
        Vm.Log[] memory logs,
        address user,
        uint collPoolBalBf,
        uint debtBalBf,
        address tokenOut,
        uint tokenOutBalBf
    ) internal view {
        bool isEmmitted;
        for (uint i; i < logs.length; i++) {
            // find log
            if (logs[i].topics[0] == keccak256('DecreasePos(address,address,uint256,address,uint256,address,uint256)'))
            {
                (address _collPool, uint _collAmt, address _borrPool, uint _debtAmt, address _tokenOut, uint _amtOut) =
                    abi.decode(logs[i].data, (address, uint, address, uint, address, uint));
                assertEq(logs[i].topics[1], bytes32(uint(uint160(user))), 'bad user');
                assertEq(_collPool, collPool, 'bad coll pool');
                uint curBal = IERC20(collPool).balanceOf(user);
                assertApproxEqAbs(_collAmt, collPoolBalBf - curBal, 1, 'bad coll amount');
                assertEq(_borrPool, debtPool, 'bad borr pool');
                curBal = IDebtToken(debtPool).balanceOf(user);
                assertApproxEqAbs(_debtAmt, debtBalBf - curBal, 1, ' debt amount');
                assertEq(_tokenOut, tokenOut, 'bad tokenOut');
                curBal = IERC20(tokenOut).balanceOf(user);
                assertApproxEqAbs(_amtOut, curBal - tokenOutBalBf, 0, 'bad tokenOut amount');
                isEmmitted = true;
            }
        }
        require(isEmmitted, 'decreasePos not emitted');
    }

    function _checkRepayDebtWithCollateralEvent(Vm.Log[] memory logs, address user, uint collPoolBalBf, uint debtBalBf)
        internal
        view
    {
        bool isEmmitted;
        for (uint i; i < logs.length; i++) {
            // find log
            if (logs[i].topics[0] == keccak256('RepayDebtWithCollateral(address,address,uint256,address,uint256)')) {
                (address _collPool, uint _collAmt, address _borrPool, uint _debtAmt) =
                    abi.decode(logs[i].data, (address, uint, address, uint));
                assertEq(logs[i].topics[1], bytes32(uint(uint160(user))), 'bad user');
                assertEq(_collPool, collPool, 'bad coll pool');
                assertApproxEqAbs(_collAmt, collPoolBalBf - IERC20(collPool).balanceOf(user), 1, 'bad coll amount');
                assertEq(_borrPool, debtPool, 'bad borr pool');
                assertApproxEqAbs(_debtAmt, debtBalBf - IDebtToken(debtPool).balanceOf(user), 1, 'bad debt amount');
                isEmmitted = true;
            }
        }
    }

    function _checkSwapIncreasePosEvent(Vm.Log[] memory logs, address user, uint amtIn, uint collPoolBalBf)
        internal
        view
    {
        bool isSwapEmitted;
        for (uint i; i < logs.length; i++) {
            // find log
            if (logs[i].topics[0] == keccak256('Swap(address,address,address,uint256,uint256)')) {
                assertEq(logs[i].topics[1], bytes32(uint(uint160(swapper))), 'bad user');
                (address _from, address _to, uint _amtIn, uint amtOut) =
                    abi.decode(logs[i].data, (address, address, uint, uint));
                assertEq(_from, debtToken, 'bad from');
                assertEq(_to, collToken, 'bad to');
                assertEq(_amtIn, amtIn, 'bad amtIn');
                assertApproxEqAbs(IERC20(collPool).balanceOf(user) - collPoolBalBf, amtOut, 1, 'bad amtOut emitted');
                isSwapEmitted = true;
            }
        }
        require(isSwapEmitted, 'Swap not emitted');
    }

    function _checkSwapEmittedRepayDebtWithCollateral(
        Vm.Log[] memory logs,
        address user,
        uint collPoolBalBf,
        uint debtBalBf
    ) internal view {
        bool isEmitted;
        for (uint i; i < logs.length; i++) {
            // find log
            if (logs[i].topics[0] == keccak256('Swap(address,address,address,uint256,uint256)')) {
                assertEq(logs[i].topics[1], bytes32(uint(uint160(swapper))), 'bad user');
                (address _from, address _to, uint _amtIn, uint amtOut) =
                    abi.decode(logs[i].data, (address, address, uint, uint));
                assertEq(_from, collToken, 'bad from');
                assertEq(_to, debtToken, 'bad to');
                assertApproxEqAbs(_amtIn, collPoolBalBf - IERC20(collPool).balanceOf(user), 1, 'bad amtIn');
                console.log(debtBalBf - IERC20(debtToken).balanceOf(user));
                console.log(amtOut);
                console.log(amtOut * (10_000 - IPool(Constants.AAVE_LENDING_POOL).FLASHLOAN_PREMIUM_TOTAL()) / 10_000);
                assertApproxEqAbs(
                    (debtBalBf - IERC20(debtPool).balanceOf(user))
                        * (10_000 + IPool(Constants.AAVE_LENDING_POOL).FLASHLOAN_PREMIUM_TOTAL()) / 10_000,
                    amtOut,
                    2,
                    'bad amtOut emitted'
                );
                isEmitted = true;
            }
        }
        require(isEmitted, 'Swap not emitted');
    }
}
