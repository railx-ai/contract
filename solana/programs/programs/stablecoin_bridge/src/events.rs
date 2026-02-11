//! Events emitted by the stablecoin bridge program.
//! Indexers and relayers consume these for cross-chain coordination.

use anchor_lang::prelude::*;

#[event]
pub struct LiquidityDeposited {
    pub pool: Pubkey,
    pub depositor: Pubkey,
    pub stablecoin_amount: u64,
    pub lp_tokens_minted: u64,
    pub timestamp: i64,
}

#[event]
pub struct LiquidityWithdrawn {
    pub pool: Pubkey,
    pub withdrawer: Pubkey,
    pub stablecoin_amount: u64,
    pub lp_tokens_burned: u64,
    pub timestamp: i64,
}

#[event]
pub struct BridgeIntent {
    pub pool: Pubkey,
    pub sender: Pubkey,
    pub amount: u64,
    pub destination_chain_id: u64,
    /// Recipient on destination chain (opaque; 32 bytes).
    pub recipient_address: [u8; 32],
    pub nonce: u64,
    pub timestamp: i64,
}

#[event]
pub struct BridgeReverted {
    pub pool: Pubkey,
    pub bridge_lock: Pubkey,
    pub amount: u64,
    pub nonce: u64,
    pub timestamp: i64,
}
