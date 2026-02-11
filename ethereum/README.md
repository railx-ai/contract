# RailX Stablecoin Bridge Pool (Base)

Production-ready Solidity contracts for the **liquidity pool side** of the liquidity-native stablecoin bridge on Ethereum Base.

## Overview

- **Role**: Holds real stablecoins (e.g. USDC) on Base and releases liquidity when a valid cross-chain bridge intent is executed. This is **not** a wrapped token or mint/burn bridge.
- **LP model**: Internal LP shares (no ERC20 LP token in MVP); proportional deposits/withdrawals.
- **Bridge execution**: Authorized relayer calls `executeBridgeRelease(recipient, amount, sourceChainId, nonce)` after off-chain verification; `revertBridge(nonce)` pulls funds back from recipient if the source chain reverts.

## Contracts

| Contract | Description |
|----------|-------------|
| `StablecoinBridgePool.sol` | Main pool: deposits, withdrawals, bridge release/revert, fee, pause, roles. |
| `interfaces/IStablecoinBridgePool.sol` | Interface for relayers and frontends. |

## Dependencies

- **OpenZeppelin** (AccessControl, ReentrancyGuard, Pausable, SafeERC20, IERC20).

### Using Foundry

```bash
cd contract/ethereum
forge install OpenZeppelin/openzeppelin-contracts
forge build
```

### Using npm (e.g. Hardhat)

```bash
cd contract/ethereum
npm init -y
npm install @openzeppelin/contracts
# Configure Hardhat/Remix to use node_modules path for @openzeppelin
```

## Architecture

- **totalLiquidity**: Sum of stablecoin in the pool (increases on deposit/revert, decreases on withdraw/release).
- **availableLiquidity**: Same as totalLiquidity in MVP (no separate in-flight tracking).
- **totalShares / sharesOf**: LP accounting; share price = totalLiquidity / totalShares.
- **feeRateBps**: Fee in basis points applied on `executeBridgeRelease`; fee stays in pool (benefits LPs).
- **bridgeReleaseByNonce**: Nonce → amount released; used for idempotency and for `revertBridge` to pull back funds.

## Security

- **Roles**: `DEFAULT_ADMIN_ROLE` (admin), `RELAYER_ROLE` (execute/revert).
- **ReentrancyGuard**: All state-changing external functions.
- **Pausable**: Admin can pause deposits, withdrawals, and bridge execution.
- **SafeERC20**: All stablecoin transfers use SafeERC20.

## Events

- `LiquidityDeposited(provider, amount, sharesMinted)`
- `LiquidityWithdrawn(provider, amount, sharesBurned)`
- `BridgeExecuted(recipient, amount, sourceChainId, nonce, relayer)`
- `BridgeReverted(nonce, amountRestored)`

## MVP Assumptions

- Single relayer (or multiple addresses with `RELAYER_ROLE`).
- No on-chain verification of Solana (or other source chain) state; off-chain verification by routing engine.
- Designed so validator-based verification can be added later (e.g. relayer replaced by a verifier contract).
