// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IStablecoinBridgePool
 * @notice Interface for the liquidity-native stablecoin bridge pool on Base.
 * @dev Used by relayers and frontends; does not include admin or view helpers.
 */
interface IStablecoinBridgePool {
    /// @notice Emitted when liquidity is deposited into the pool.
    event LiquidityDeposited(address indexed provider, uint256 amount, uint256 sharesMinted);

    /// @notice Emitted when liquidity is withdrawn from the pool.
    event LiquidityWithdrawn(address indexed provider, uint256 amount, uint256 sharesBurned);

    /// @notice Emitted when a bridge release is executed (funds sent to recipient on Base).
    event BridgeExecuted(
        address indexed recipient,
        uint256 amount,
        uint256 sourceChainId,
        uint256 indexed nonce,
        address indexed relayer
    );

    /// @notice Emitted when a bridge is reverted (e.g. source chain rollback; liquidity restored).
    event BridgeReverted(uint256 indexed nonce, uint256 amountRestored);

    /// @notice Deposit stablecoin and receive internal LP share entitlement.
    /// @param amount Amount of stablecoin to deposit (in token decimals).
    function deposit(uint256 amount) external;

    /// @notice Withdraw stablecoin by burning internal LP shares.
    /// @param amount Amount of stablecoin to withdraw (in token decimals).
    function withdraw(uint256 amount) external;

    /// @notice Execute a bridge release: transfer stablecoin to recipient (relayer-only).
    /// @param recipient Address to receive the stablecoin on Base.
    /// @param amount Amount to release (in token decimals).
    /// @param sourceChainId Chain ID where the lock/burn occurred (for idempotency and analytics).
    /// @param nonce Unique bridge intent nonce (must not have been used before).
    function executeBridgeRelease(
        address recipient,
        uint256 amount,
        uint256 sourceChainId,
        uint256 nonce
    ) external;

    /// @notice Revert a prior bridge execution by nonce (e.g. source chain reverted).
    /// @param nonce The nonce of the bridge execution to revert.
    function revertBridge(uint256 nonce) external;
}
