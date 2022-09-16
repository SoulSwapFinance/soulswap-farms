// SPDX-License-Identifier: MIT

// P1 - P3: OK
pragma solidity ^0.8.0;

import '../libraries/SafeERC20.sol';
import '@soulswap/swap-core/contracts/interfaces/ISoulSwapPair.sol';
import '@soulswap/swap-core/contracts/interfaces/ISoulSwapFactory.sol';
import '../libraries/Operable.sol';

// SoulReaper is SoulSummoner's most generous wizard. SoulReaper may reap up Soul from pretty much anything!
// This contract handles 'serving up' rewards for SpellBound holders by trading tokens collected from fees for Soul.

// T1 - T4: OK
contract SoulReaper is Ownable, Operable {
    using SafeERC20 for IERC20;

    ISoulSwapFactory public immutable factory;
    address public immutable spell;
    address private immutable soul;
    address private immutable weth;

    mapping(address => address) internal _bridges;

    event LogBridgeSet(address indexed token, address indexed bridge);
    event LogConvert(
        address indexed server,
        address indexed token0,
        address indexed token1,
        uint256 amount0,
        uint256 amount1,
        uint256 amountSOUL
    );

    constructor(
        address _factory,
        address _spell,
        address _soul,
        address _weth
    ) {
        factory = ISoulSwapFactory(_factory);
        spell = _spell;
        soul = _soul;
        weth = _weth;
    }

    function bridgeFor(address token) public view returns (address bridge) {
        bridge = _bridges[token];
        if (bridge == address(0)) {
            bridge = weth;
        }
    }

    function setBridge(address token, address bridge) external onlyOperator {
        // Checks
        require(
            token != soul && token != weth && token != bridge,
            'SoulReaper: Invalid bridge'
        );

        // Effects
        _bridges[token] = bridge;
        emit LogBridgeSet(token, bridge);
    }

    // not a fool proof, but prevents flash loans, so here it's ok to use tx.origin
    modifier onlyEOA() {
        // try to making flash-loan exploit harder to do by only allowing externally owned addresses.
        require(msg.sender == tx.origin, 'SoulReaper: must use EOA');
        _;
    }

    // _convert is separate to save gas by only checking the 'onlyEOA' modifier once in case of convertMultiple
    // there is an exploit to add lots of SOUL to the spellbound, run convert, then remove the SOUL again.
    // as the size of the SpellBound has grown, this requires large amounts of funds and isn't super profitable anymore
    // the onlyEOA modifier prevents this being done with a flash loan.
    function convert(address token0, address token1) external onlyEOA() {
        _convert(token0, token1);
    }

    // C3: Loop is under control of the caller
    function convertMultiple(
        address[] calldata token0,
        address[] calldata token1
    ) external onlyEOA() {
        // TODO: This can be optimized a fair bit, but this is safer and simpler for now
        uint256 len = token0.length;
        for (uint256 i = 0; i < len; i++) {
            _convert(token0[i], token1[i]);
        }
    }

    function _convert(address token0, address token1) internal {
        // Interactions
        ISoulSwapPair pair = ISoulSwapPair(factory.getPair(token0, token1));
        require(address(pair) != address(0), 'SoulReaper: Invalid pair');
        IERC20(address(pair)).safeTransfer(
            address(pair),
            pair.balanceOf(address(this))
        );

        (uint256 amount0, uint256 amount1) = pair.burn(address(this));

        if (token0 != pair.token0()) { (amount0, amount1) = (amount1, amount0); }
        emit LogConvert(
            msg.sender,
            token0,
            token1,
            amount0,
            amount1,
            _convertStep(token0, token1, amount0, amount1)
        );
    }

    function _convertStep(
        address token0,
        address token1,
        uint256 amount0,
        uint256 amount1
    ) internal returns (uint256 soulOut) {
        // Interactions
        if (token0 == token1) {
            uint256 amount = amount0 + amount1;
            if (token0 == soul) {
                IERC20(soul).safeTransfer(spell, amount);
                soulOut = amount;
            } else if (token0 == weth) {
                soulOut = _toSOUL(weth, amount);
            } else {
                address bridge = bridgeFor(token0);
                amount = _swap(token0, bridge, amount, address(this));
                soulOut = _convertStep(bridge, bridge, amount, 0);
            }
        } else if (token0 == soul) {
            // eg. SOUL - ETH
            IERC20(soul).safeTransfer(spell, amount0);
            soulOut = _toSOUL(token1, amount1) + amount0;
        } else if (token1 == soul) {
            // eg. USDT - SOUL
            IERC20(soul).safeTransfer(spell, amount1);
            soulOut = _toSOUL(token0, amount0) + amount1;
        } else if (token0 == weth) {
            // eg. ETH - USDC
            soulOut = _toSOUL(
                weth,
                _swap(token1, weth, amount1, address(this)) + amount0
            );
        } else if (token1 == weth) {
            // eg. USDT - ETH
            soulOut = _toSOUL(
                weth,
                _swap(token0, weth, amount0, address(this)) + amount1
            );
        } else {
            // eg. MIC - USDT
            address bridge0 = bridgeFor(token0);
            address bridge1 = bridgeFor(token1);
            if (bridge0 == token1) {
                // eg. MIC - USDT - and bridgeFor(MIC) = USDT
                soulOut = _convertStep(
                    bridge0,
                    token1,
                    _swap(token0, bridge0, amount0, address(this)),
                    amount1
                );
            } else if (bridge1 == token0) {
                // eg. WBTC - DSD - and bridgeFor(DSD) = WBTC
                soulOut = _convertStep(
                    token0,
                    bridge1,
                    amount0,
                    _swap(token1, bridge1, amount1, address(this))
                );
            } else {
                soulOut = _convertStep(
                    bridge0,
                    bridge1, // eg. USDT - DSD - and bridgeFor(DSD) = WBTC
                    _swap(token0, bridge0, amount0, address(this)),
                    _swap(token1, bridge1, amount1, address(this))
                );
            }
        }
    }

    function _swap(
        address fromToken,
        address toToken,
        uint256 amountIn,
        address to
    ) internal returns (uint256 amountOut) {
        // Checks
        ISoulSwapPair pair =
            ISoulSwapPair(factory.getPair(fromToken, toToken));
        require(address(pair) != address(0), 'SoulReaper: Cannot convert');

        // Interactions
        (uint256 reserve0, uint256 reserve1, ) = pair.getReserves();
        uint256 amountInWithFee = amountIn * 997;
        if (fromToken == pair.token0()) {
            amountOut =
                amountInWithFee * reserve1 /
                reserve0 * 1000 + amountInWithFee;
            IERC20(fromToken).safeTransfer(address(pair), amountIn);
            pair.swap(0, amountOut, to, new bytes(0));
            // TODO: Add maximum slippage?
        } else {
            amountOut =
                amountInWithFee * reserve0 /
                reserve1 * 1000 + amountInWithFee;
            IERC20(fromToken).safeTransfer(address(pair), amountIn);
            pair.swap(amountOut, 0, to, new bytes(0));
            // TODO: Add maximum slippage?
        }
    }

    function _toSOUL(address token, uint256 amountIn)
        internal
        returns (uint256 amountOut)
    {
        amountOut = _swap(token, soul, amountIn, spell);
    }

}