// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IStablecoinBridgePool } from "./interfaces/IStablecoinBridgePool.sol";

/**
 * @title StablecoinBridgePool
 * @author RailX
 * @notice Liquidity pool for a liquidity-native stablecoin bridge on Base. Holds real stablecoins
 *         (e.g. USDC), issues internal LP shares, and releases funds when a valid cross-chain
 *         bridge intent is executed by an authorized relayer. This is NOT a wrapped token or
 *         mint/burn bridge—funds are transferred 1:1 from this pool to the recipient.
 * @dev Designed for future validator-based verification; MVP uses single relayer and off-chain
 *      verification by the routing engine. No on-chain verification of Solana state in MVP.
 */
contract StablecoinBridgePool is IStablecoinBridgePool, AccessControl, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////
                                ROLES
    //////////////////////////////////////////////////////////////*/

    /// @dev Relayer can call executeBridgeRelease and revertBridge.
    bytes32 public constant RELAYER_ROLE = keccak256("RELAYER_ROLE");

    /*//////////////////////////////////////////////////////////////
                                STATE
    //////////////////////////////////////////////////////////////*/

    /// @notice The ERC20 stablecoin held by this pool (e.g. USDC on Base).
    IERC20 public immutable stablecoin;

    /// @notice Total stablecoin balance held by the pool (deposits minus released, plus reverted).
    uint256 public totalLiquidity;

    /// @notice Liquidity available for bridge releases (total minus amounts in-flight if tracked; MVP = totalLiquidity).
    uint256 public availableLiquidity;

    /// @notice Fee taken from bridge operations, in basis points (e.g. 5 = 0.05%). Applied on executeBridgeRelease.
    uint256 public feeRateBps;

    /// @notice Total LP shares in existence. LP share ratio = totalLiquidity / totalShares (with 1:1 initial).
    uint256 public totalShares;

    /// @notice LP shares per provider (internal accounting; no ERC20 LP token in MVP).
    mapping(address => uint256) public sharesOf;

    /// @notice Nonce => amount released. Used to support revertBridge and prevent double-spend of nonce.
    mapping(uint256 => uint256) public bridgeReleaseByNonce;

    /// @notice Nonce => recipient (for revertBridge: we do not store recipient in event-only design; optional for extensions).
    mapping(uint256 => address) public bridgeRecipientByNonce;

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    error ZeroAmount();
    error InsufficientLiquidity();
    error InsufficientShares();
    error NonceAlreadyUsed();
    error BridgeNotExecuted();
    error InvalidFeeRate();
    error ZeroAddress();

    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @param _stablecoin Address of the ERC20 stablecoin (e.g. USDC on Base).
     * @param _admin Admin address (granted DEFAULT_ADMIN_ROLE and RELAYER_ROLE for MVP).
     */
    constructor(address _stablecoin, address _admin) {
        if (_stablecoin == address(0) || _admin == address(0)) revert ZeroAddress();
        stablecoin = IERC20(_stablecoin);
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(RELAYER_ROLE, _admin);
        // Initial share ratio 1:1; first depositor gets shares equal to amount
        totalShares = 0;
        totalLiquidity = 0;
        availableLiquidity = 0;
        feeRateBps = 0;
    }

    /*//////////////////////////////////////////////////////////////
                        LIQUIDITY (LP) FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Deposit stablecoin into the pool and receive internal LP share entitlement.
     * @param amount Amount of stablecoin to deposit (must be > 0 and approved to this contract).
     */
    function deposit(uint256 amount) external nonReentrant whenNotPaused {
        if (amount == 0) revert ZeroAmount();

        uint256 shares = totalShares == 0 ? amount : (amount * totalShares) / totalLiquidity;
        if (shares == 0) revert ZeroAmount();

        totalLiquidity += amount;
        availableLiquidity += amount;
        totalShares += shares;
        sharesOf[msg.sender] += shares;

        stablecoin.safeTransferFrom(msg.sender, address(this), amount);

        emit LiquidityDeposited(msg.sender, amount, shares);
    }

    /**
     * @notice Withdraw stablecoin from the pool by burning LP shares.
     * @param amount Amount of stablecoin to withdraw (will burn proportional shares).
     */
    function withdraw(uint256 amount) external nonReentrant whenNotPaused {
        if (amount == 0) revert ZeroAmount();
        if (amount > availableLiquidity) revert InsufficientLiquidity();

        uint256 shares = totalShares == 0 ? 0 : (amount * totalShares) / totalLiquidity;
        if (shares == 0) revert ZeroAmount();
        if (shares > sharesOf[msg.sender]) revert InsufficientShares();

        totalLiquidity -= amount;
        availableLiquidity -= amount;
        totalShares -= shares;
        sharesOf[msg.sender] -= shares;

        stablecoin.safeTransfer(msg.sender, amount);

        emit LiquidityWithdrawn(msg.sender, amount, shares);
    }

    /*//////////////////////////////////////////////////////////////
                        BRIDGE EXECUTION
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Execute a bridge release: send stablecoin to recipient. Callable only by relayer.
     *         Off-chain verification (e.g. Solana lock proof) is assumed done by the routing engine.
     * @param recipient Address to receive the stablecoin on Base.
     * @param amount Gross amount to release (before fee). Fee is retained in the pool (increases LP value).
     * @param sourceChainId Chain ID of the source chain (for idempotency and analytics).
     * @param nonce Unique nonce for this bridge intent; must not have been used before.
     */
    function executeBridgeRelease(
        address recipient,
        uint256 amount,
        uint256 sourceChainId,
        uint256 nonce
    ) external nonReentrant whenNotPaused onlyRole(RELAYER_ROLE) {
        if (amount == 0) revert ZeroAmount();
        if (bridgeReleaseByNonce[nonce] != 0) revert NonceAlreadyUsed();

        uint256 fee = (amount * feeRateBps) / 10_000;
        uint256 netAmount = amount - fee;

        if (netAmount > availableLiquidity) revert InsufficientLiquidity();

        totalLiquidity -= netAmount;
        availableLiquidity -= netAmount;
        bridgeReleaseByNonce[nonce] = netAmount;
        bridgeRecipientByNonce[nonce] = recipient;

        stablecoin.safeTransfer(recipient, netAmount);

        emit BridgeExecuted(recipient, netAmount, sourceChainId, nonce, msg.sender);
    }

    /**
     * @notice Revert a prior bridge execution by nonce (e.g. source chain reverted). Pulls
     *         stablecoin back from the recipient and restores pool liquidity. Recipient must
     *         have approved this contract for at least `amount`, or the relayer must have
     *         arranged for tokens to be at recipient and approved (e.g. via relayer-owned
     *         recipient or refund flow).
     * @param nonce The nonce of the bridge execution to revert.
     */
    function revertBridge(uint256 nonce) external nonReentrant whenNotPaused onlyRole(RELAYER_ROLE) {
        uint256 amount = bridgeReleaseByNonce[nonce];
        if (amount == 0) revert BridgeNotExecuted();

        address recipient = bridgeRecipientByNonce[nonce];
        bridgeReleaseByNonce[nonce] = 0;
        bridgeRecipientByNonce[nonce] = address(0);

        totalLiquidity += amount;
        availableLiquidity += amount;

        stablecoin.safeTransferFrom(recipient, address(this), amount);

        emit BridgeReverted(nonce, amount);
    }

    /*//////////////////////////////////////////////////////////////
                            ADMIN
    //////////////////////////////////////////////////////////////*/

    /// @notice Update the bridge fee rate (basis points). Admin only.
    function updateFeeRate(uint256 newFeeBps) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newFeeBps > 10_000) revert InvalidFeeRate();
        feeRateBps = newFeeBps;
    }

    /// @notice Pause deposits, withdrawals, and bridge execution.
    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    /// @notice Unpause the pool.
    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    /*//////////////////////////////////////////////////////////////
                            VIEW HELPERS
    //////////////////////////////////////////////////////////////*/

    /// @notice Get the current fee rate in basis points.
    function feeRate() external view returns (uint256) {
        return feeRateBps;
    }

    /// @notice Get LP share balance for an account.
    function balanceOf(address account) external view returns (uint256) {
        return sharesOf[account];
    }

    /// @notice Get stablecoin value of an account's shares (rounded down).
    function balanceOfUnderlying(address account) external view returns (uint256) {
        uint256 s = sharesOf[account];
        if (totalShares == 0) return 0;
        return (s * totalLiquidity) / totalShares;
    }

    /// @notice Check whether a nonce has been used (executed).
    function isNonceUsed(uint256 nonce) external view returns (bool) {
        return bridgeReleaseByNonce[nonce] != 0;
    }
}
