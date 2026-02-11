//! Program errors. Explicit codes improve auditability and client handling.

use anchor_lang::prelude::*;

#[error_code]
pub enum BridgeError {
    #[msg("Pool or protocol is paused")]
    PoolPaused,

    #[msg("Insufficient available liquidity in pool")]
    InsufficientLiquidity,

    #[msg("Lock amount exceeds max_lock_per_tx")]
    LockAmountExceedsLimit,

    #[msg("Lock cooldown not elapsed")]
    LockCooldownActive,

    #[msg("Bridge lock already released")]
    AlreadyReleased,

    #[msg("Invalid bridge lock for this pool")]
    InvalidBridgeLock,

    #[msg("Unauthorized: admin required")]
    UnauthorizedAdmin,

    #[msg("Unauthorized: relayer required")]
    UnauthorizedRelayer,

    #[msg("Fee rate must be between 0 and 10000 bps")]
    InvalidFeeRate,

    #[msg("Arithmetic overflow or invalid share calculation")]
    MathOverflow,

    #[msg("Invalid pool state: total_liquidity != available + locked")]
    InvalidPoolState,

    #[msg("LP token amount must be greater than zero")]
    ZeroLpAmount,

    #[msg("Stablecoin amount must be greater than zero")]
    ZeroStablecoinAmount,
}
