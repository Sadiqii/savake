# Savake Staking Smart Contract

This contract implements a multi-tier staking protocol with fungible and non-fungible tokens, referral rewards, and robust admin controls. It is written in Clarity for the Stacks blockchain.

---

## Features

- **Fungible Token (`savake-token`)**  
  Used for staking, rewards, and fee payments.

- **Non-Fungible Token (`staking-position`)**  
  Represents individual staking positions (Liquid Staking Derivatives, LSD).

- **Multi-Tier Staking**  
  Users are assigned tiers (1-4) based on their total staked amount:
  - Tier 0: < 1,000 tokens (0.5x multiplier)
  - Tier 1: 1,000+ tokens (1.0x multiplier)
  - Tier 2: 5,000+ tokens (1.25x multiplier)
  - Tier 3: 25,000+ tokens (1.5x multiplier)
  - Tier 4: 100,000+ tokens (2.0x multiplier)

- **Dynamic Fee Structure**
  - Standard fee: Configurable (default 1%)
  - Large deposits (10,000+ tokens): 0.5% fee

- **Referral System**  
  Users can set referrers and earn 10 token rewards per referral.

- **NFT Positions**  
  Each staking position is minted as an NFT with:
  - Owner information
  - Staked amount
  - Creation timestamp
  - Lock period
  - Tier level
  - Reward multiplier

- **Admin Controls**  
  - Pause/unpause contract
  - Set staking fees (max 10%)
  - Set treasury address
  - Mint/burn tokens

---

## Core Functions

### Staking

- `stake(amount)`  
  Stake tokens with dynamic fee structure.

- `stake-and-bake(amount, lock-period)`  
  Stake tokens with optional lock period up to 52,560 blocks (~1 year).

- `unstake(amount)`  
  Unstake tokens if not locked.

- `emergency-unstake(amount)`  
  Available when contract is paused > 144 blocks.

### NFT Positions

- `create-staking-position(amount, lock-period)`  
  Create and mint NFT position.

- `transfer-position(position-id, recipient)`  
  Transfer NFT position to new owner.

### Referral

- `set-referrer(referrer)`  
  Set referrer for reward sharing.

### Admin

- `pause-contract()`
- `unpause-contract()`
- `set-treasury-address(new-treasury)`
- `set-staking-fee(new-fee)`
- `mint-rewards(recipient, amount)`
- `burn-tokens(amount)`

---

## Read-Only Functions

- `get-user-balance(user)`
- `get-user-tier(user)`
- `get-user-lock(user)`
- `get-position-details(position-id)`
- `get-user-positions(user)`
- `get-contract-info()`
- `get-user-referrer(user)`

---

## Token Standard Implementation

### SIP-010 Functions
- `transfer(amount, from, to, memo)`
- `get-name()`
- `get-symbol()`
- `get-decimals()`
- `get-balance(who)`
- `get-total-supply()`
- `get-token-uri()`

---

## Security Features

- Input validation for all public functions
- Principal address validation
- Amount validation
- Lock period limits
- Fee caps (10% maximum)
- Emergency unstaking mechanism
- Ownership verification for transfers

---

## Error Handling

Comprehensive error codes for:
- Authentication failures
- Invalid inputs
- Insufficient balances
- Contract state issues
- Position management
- Referral system

---

## Usage Example

```clarity
;; Stake tokens
(stake u1000)

;; Create locked position
(create-staking-position u5000 u144)

;; Set referrer
(set-referrer 'SP2J6ZY48GV1EZ5V2V5RB9MP66SW86PYKKNRV9EJ7)

;; Transfer position
(transfer-position u1 'SP2J6ZY48GV1EZ5V2V5RB9MP66SW86PYKKNRV9EJ7)
```

---

## License

This contract is provided for educational and demonstration purposes. Please audit and test thoroughly before deploying in production.

---

**Savake Protocol – Multi-Tier Staking, NFT Positions, and Referral Rewards**
