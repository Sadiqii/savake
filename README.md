# Savake Staking Smart Contract

This contract implements a multi-tier staking protocol with fungible and non-fungible tokens, referral rewards, and robust admin controls. It is written in Clarity for the Stacks blockchain.

---

## Features

- **Fungible Token (`sbtc-token`)**  
  Used for staking, rewards, and fee payments.

- **Non-Fungible Token (`staking-position`)**  
  Represents individual staking positions (Liquid Staking Derivatives, LSD).

- **Multi-Tier Staking**  
  Users are assigned tiers (1-4) based on their total staked amount. Higher tiers receive better multipliers.

- **Referral System**  
  Users can register a referrer and earn referral rewards.

- **NFT Positions**  
  Each staking position is represented as an NFT, which can be transferred or redeemed.

- **Admin Controls**  
  Admin can pause/unpause the contract, set fees, mint/burn tokens, and set the treasury address.

- **Emergency Unstake**  
  If the contract is paused for more than 144 blocks, users can unstake even if locked.

---

## Tier System

| Tier | Threshold (sbtc) | Multiplier |
|------|------------------|------------|
| 1    | 1,000            | 1.0x       |
| 2    | 5,000            | 1.25x      |
| 3    | 25,000           | 1.5x       |
| 4    | 100,000          | 2.0x       |

---

## Core Functions

### Staking

- `stake(amount)`  
  Stake tokens without a lock.

- `stake-and-bake(amount, lock-period)`  
  Stake tokens with an optional lock period and referral.

- `unstake(amount)`  
  Unstake tokens (if not locked).

- `emergency-unstake(amount)`  
  Unstake tokens during emergency (if paused > 144 blocks).

### NFT Positions

- `create-staking-position(amount, lock-period)`  
  Create an NFT staking position.

- `transfer-position(position-id, to)`  
  Transfer an NFT position.

- `redeem-position(position-id)`  
  Redeem an NFT position (burn NFT and tokens).

### Referral

- `register-referral(referrer)`  
  Register a referrer for referral rewards.

### Admin

- `set-admin(new-admin)`  
  Change admin.

- `set-fee(new-fee)`  
  Set staking fee.

- `set-treasury(new-treasury)`  
  Set treasury address.

- `pause()`  
  Pause contract.

- `unpause()`  
  Unpause contract.

- `mint-rewards(recipient, amount)`  
  Mint rewards to a user.

- `admin-burn(amount)`  
  Burn tokens from admin account.

---

## Read-Only Functions

- `get-balance(who)`  
  Get sbtc-token balance.

- `get-total-staked`  
  Get total staked amount.

- `get-user-tier(user)`  
  Get user's tier.

- `get-user-multiplier(user)`  
  Get user's multiplier.

- `get-staking-position(position-id)`  
  Get NFT position details.

- `get-user-positions(user)`  
  Get user's NFT positions.

---

## Events

The contract emits events for all major actions, including:

- Deposits, withdrawals, staking, unstaking
- Position creation, transfer, redemption
- Referral registration and rewards
- Admin updates and emergency actions

---

## Usage Example

1. **Stake Tokens**
   ```
   (stake u1000)
   ```

2. **Create NFT Position**
   ```
   (create-staking-position u5000 u144)
   ```

3. **Register Referral**
   ```
   (register-referral 'SP...REFERRER)
   ```

4. **Unstake Tokens**
   ```
   (unstake u1000)
   ```

---

## Security & Controls

- Only admin can perform sensitive actions.
- Emergency unstake is available if contract is paused for > 144 blocks.
- All state changes are validated and logged via events.

---

## License

This contract is provided for educational and demonstration purposes. Please audit and test thoroughly before deploying in production.

---

**Savake Protocol – Multi-Tier Staking, NFT Positions, and Referral Rewards**
