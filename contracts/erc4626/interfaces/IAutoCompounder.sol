// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/**
 * @title Auto Compounder
 */
interface IAutoCompounder {
    /**
     * @notice CreatedToken event.
     * @dev Emitted after contract initialization, when aToken was deployed.
     *
     * @param createdToken The address of aToken.
     */
    event CreatedToken(address indexed createdToken);
    /**
     * @notice Claim event.
     * @dev Emitted after AutoCompounder claiming process.
     *
     * @param depositedUnderlying The amount of deposited underlying.
     */
    event Claim(uint256 depositedUnderlying);
    /**
     * @notice Withdraw event.
     * @dev Emitted when anyone withdraw aToken for underlying.
     *
     * @param caller The caller address.
     * @param aTokenAmount The aToken amount to withdraw.
     * @param underlyingAmount The withdrawn underlying amount.
     */
    event Withdraw(address indexed caller, uint256 aTokenAmount, uint256 underlyingAmount);
    /**
     * @notice Deposit event.
     * @dev Emitted after contract initialization, when aToken was deployed.
     *
     * @param caller The caller address.
     * @param assets The assets amount to deposit.
     * @param aTokenMinted The minted aToken amount.
     */
    event Deposit(address indexed caller, uint256 assets, uint256 aTokenMinted);

    /**
     * @dev Throw during claim process if there is no reward to reinvest
     */
    error ZeroReward();

    /**
     * @dev Deposits staking token to the Vault and returns shares.
     *
     * @param assets The amount of staking token to send.
     * @param receiver The shares receiver address.
     * @return amountToMint The amount of aToken to receive.
     */
    function deposit(uint256 assets, address receiver) external returns (uint256 amountToMint);

    /**
     * @dev Withdraws underlying asset from the Vault.
     *
     * @param aTokenAmount The amount of aToken to send.
     * @param receiver The underlying receiver address.
     * @return underlyingAmount The amount of aToken to receive.
     */
    function withdraw(uint256 aTokenAmount, address receiver) external returns (uint256 underlyingAmount);

    /**
     * @dev Claims reward from the Vault, swap to underlying and deposit back.
     */
    function claim() external;

    /**
     * @dev Returns the exchange rate for token.
     * @return exchangeRate The calculated exchange rate.
     */
    function exchangeRate() external view returns (uint256 exchangeRate);

    /**
     * @dev Returns underlying asset address.
     */
    function asset() external view returns (address);

    /**
     * @dev Returns related vault address.
     */
    function vault() external view returns (address);
}
