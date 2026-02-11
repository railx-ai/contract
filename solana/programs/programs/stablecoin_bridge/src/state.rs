//! Program state accounts for the liquidity-native stablecoin bridge.
//!
//! No mint/burn across chains: funds are locked on Solana and released
//! on destination by relayers. Pools hold native liquidity; LP tokens
//! represent proportional share of pool.

use anchor_lang::prelude::*;

/// Global protocol config. Single instance per program.
/// Holds admin and relayer authority for access control.
#[account]
#[derive(Default)]
pub struct Config {
    /// Authority that can update fee rates, pause pools, and manage relayers.
    pub admin: Pubkey,
    /// Authority allowed to call release_locked_liquidity (bridge revert).
    pub relayer: Pubkey,
    /// Protocol-level pause: when true, no lock_for_bridge or deposits.
    pub paused: bool,
    /// Bump used to derive the config PDA.
    pub bump: u8,
}

impl Config {
    pub const LEN: usize = 8 + 32 + 32 + 1 + 1;
}

/// One pool per stablecoin. Holds vault ATA and LP mint; tracks liquidity.
#[account]
#[derive(Default)]
pub struct Pool {
    /// Stablecoin mint (e.g. USDC). Pool holds this token in vault.
    pub stablecoin_mint: Pubkey,
    /// Pool's token account holding stablecoins (vault).
    pub vault: Pubkey,
    /// LP token mint. Minted on deposit, burned on withdraw.
    pub lp_token_mint: Pubkey,
    /// Total stablecoin liquidity in pool (available + locked). Invariant: total = available + locked.
    pub total_liquidity: u64,
    /// Liquidity available for LP withdrawals (not locked for bridge).
    pub available_liquidity: u64,
    /// Amount currently locked in bridge intents (released on revert or when bridge completes off-chain).
    pub locked_liquidity: u64,
    /// Fee in basis points (0..=10000) taken on deposits/withdraws or bridge. Applied per pool.
    pub fee_rate_bps: u16,
    /// Pool admin (can update fee, pause this pool).
    pub admin: Pubkey,
    /// Config this pool belongs to (for admin/relayer checks).
    pub config: Pubkey,
    /// Pool paused: no deposits, withdraws, or lock_for_bridge.
    pub paused: bool,
    /// PDA bump for this pool.
    pub bump: u8,
    /// Max amount that can be locked in a single lock_for_bridge call (rate limit).
    pub max_lock_per_tx: u64,
    /// Optional: cooldown in seconds between lock_for_bridge from same user (0 = disabled).
    pub lock_cooldown_seconds: u32,
    /// Next nonce to assign to a new BridgeLock (incremented on each lock_for_bridge).
    pub next_lock_nonce: u64,
}

impl Pool {
    pub const LEN: usize = 8 + 32 + 32 + 32 + 8 + 8 + 8 + 2 + 32 + 32 + 1 + 1 + 8 + 4 + 8;
}

/// Single bridge lock record. Created on lock_for_bridge; closed or marked released on release_locked_liquidity.
/// Enables relayer to release the exact lock by referencing this account.
#[account]
#[derive(Default)]
pub struct BridgeLock {
    /// Pool this lock belongs to.
    pub pool: Pubkey,
    /// Stablecoin amount locked.
    pub amount: u64,
    /// Unique nonce for this lock (emitted in BridgeIntent for relayer).
    pub nonce: u64,
    /// Destination chain id (e.g. EVM chain id).
    pub destination_chain_id: u64,
    /// Recipient on destination (opaque bytes; interpretation is off-chain).
    pub recipient_address: [u8; 32],
    /// User who initiated the lock (for accounting / future use).
    pub sender: Pubkey,
    /// True if release_locked_liquidity was called (funds returned to available).
    pub released: bool,
    /// Timestamp when lock was created (for cooldown / rate limits).
    pub locked_at: i64,
}

impl BridgeLock {
    pub const LEN: usize = 8 + 32 + 8 + 8 + 32 + 32 + 1 + 8;
}
