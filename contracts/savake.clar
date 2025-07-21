(define-fungible-token sbtc-token)
(define-non-fungible-token staking-position uint)

;; Constants
(define-constant err-not-admin u100)
(define-constant err-paused u101)
(define-constant err-fee-too-high u102)
(define-constant err-zero-deposit u103)
(define-constant err-locked u104)
(define-constant err-no-referral u105)
(define-constant err-not-allowed u106)
(define-constant err-insufficient-balance u107)
(define-constant err-invalid-amount u108)
(define-constant err-position-not-found u109)
(define-constant err-not-position-owner u110)
(define-constant err-invalid-tier u111)

;; Tier constants
(define-constant tier-1-threshold u1000)
(define-constant tier-2-threshold u5000)
(define-constant tier-3-threshold u25000)
(define-constant tier-4-threshold u100000)

(define-constant tier-1-multiplier u100) ;; 1.0x (100%)
(define-constant tier-2-multiplier u125) ;; 1.25x (125%)
(define-constant tier-3-multiplier u150) ;; 1.5x (150%)
(define-constant tier-4-multiplier u200) ;; 2.0x (200%)

;; Data Variables
(define-data-var admin principal tx-sender)
(define-data-var fee uint u100) ;; Default flat fee in sbtc
(define-data-var paused bool false)
(define-data-var pause-block uint u0)
(define-data-var treasury principal tx-sender)
(define-data-var total-staked uint u0)
(define-data-var next-position-id uint u1)

;; Referral system
(define-map referrals principal principal) ;; referred => referrer

;; Staking lock periods
(define-map stake-locks principal uint) ;; staker => block-height when unlocks

;; User staking balances (separate from token balance)
(define-map staking-balances principal uint) ;; user => staked amount

;; Multi-tier staking system
(define-map user-tiers principal uint) ;; user => tier level (1-4)
(define-map tier-benefits principal uint) ;; user => current multiplier

;; Liquid Staking Derivatives (LSD) - NFT positions
(define-map staking-positions uint {
  owner: principal,
  amount: uint,
  created-at: uint,
  lock-until: uint,
  tier: uint,
  multiplier: uint
})

;; Position ownership tracking
(define-map user-positions principal (list 50 uint)) ;; user => list of position IDs

;; SIP-010 Fungible Token Trait Implementation
(define-public (transfer (amount uint) (from principal) (to principal) (memo (optional (buff 34))))
  (begin
    (asserts! (or (is-eq tx-sender from) (is-eq contract-caller from)) (err u4))
    (ft-transfer? sbtc-token amount from to)
  )
)

(define-read-only (get-name)
  (ok "Savake Token")
)

(define-read-only (get-symbol)
  (ok "SAVAKE")
)

(define-read-only (get-decimals)
  (ok u8)
)

(define-read-only (get-balance (who principal))
  (ok (ft-get-balance sbtc-token who))
)

(define-read-only (get-total-supply)
  (ok (ft-get-supply sbtc-token))
)

(define-read-only (get-token-uri)
  (ok none)
)

;; Read-only accessors
(define-read-only (get-fee) 
  (ok (var-get fee)))

(define-read-only (get-paused) 
  (ok (var-get paused)))

(define-read-only (get-pause-block) 
  (ok (var-get pause-block)))

(define-read-only (get-total-staked)
  (ok (var-get total-staked)))

(define-read-only (get-stake-lock (user principal))
  (ok (default-to u0 (map-get? stake-locks user))))

(define-read-only (get-referrer (user principal))
  (ok (map-get? referrals user)))

(define-read-only (get-staking-balance (user principal))
  (ok (default-to u0 (map-get? staking-balances user))))

;; New read-only functions for tier system
(define-read-only (get-user-tier (user principal))
  (ok (default-to u1 (map-get? user-tiers user))))

(define-read-only (get-user-multiplier (user principal))
  (ok (default-to tier-1-multiplier (map-get? tier-benefits user))))

;; New read-only functions for LSD positions
(define-read-only (get-staking-position (position-id uint))
  (ok (map-get? staking-positions position-id)))

(define-read-only (get-user-positions (user principal))
  (ok (default-to (list) (map-get? user-positions user))))

(define-read-only (get-next-position-id)
  (ok (var-get next-position-id)))

;; Calculate tier based on total staked amount
(define-read-only (calculate-tier (total-amount uint))
  (if (>= total-amount tier-4-threshold)
    u4
    (if (>= total-amount tier-3-threshold)
      u3
      (if (>= total-amount tier-2-threshold)
        u2
        u1))))

;; Get multiplier for a tier
(define-read-only (get-tier-multiplier (tier uint))
  (if (is-eq tier u4)
    tier-4-multiplier
    (if (is-eq tier u3)
      tier-3-multiplier
      (if (is-eq tier u2)
        tier-2-multiplier
        tier-1-multiplier))))

;; Dynamic fee calculation
(define-read-only (calculate-fee (amount uint))
  (if (>= amount u10000)
      u50    ;; Lower fee for large deposits
      (var-get fee)))

;; Estimate net deposit after fee
(define-read-only (estimate-net-deposit (permit-amount uint))
  (let ((calculated-fee (calculate-fee permit-amount)))
    (if (> permit-amount calculated-fee)
      (ok (- permit-amount calculated-fee))
      (err err-zero-deposit)
    )
  )
)

;; Admin checks
(define-private (is-admin (sender principal))
  (is-eq sender (var-get admin)))

;; Update user tier based on their total staking balance
(define-private (update-user-tier (user principal))
  (let (
    (total-balance (default-to u0 (map-get? staking-balances user)))
    (new-tier (calculate-tier total-balance))
    (new-multiplier (get-tier-multiplier new-tier))
  )
    (map-set user-tiers user new-tier)
    (map-set tier-benefits user new-multiplier)
    (print {event: "tier-updated", user: user, tier: new-tier, multiplier: new-multiplier})
    (ok true)
  )
)

;; Add position to user's position list
(define-private (add-user-position (user principal) (position-id uint))
  (let (
    (current-positions (default-to (list) (map-get? user-positions user)))
    (new-positions (unwrap! (as-max-len? (append current-positions position-id) u50) (err err-invalid-amount)))
  )
    (map-set user-positions user new-positions)
    (ok true)
  )
)

;; Remove position from user's position list
(define-private (remove-user-position (user principal) (position-id uint))
  (let (
    (current-positions (default-to (list) (map-get? user-positions user)))
    (new-positions (filter is-not-target-position current-positions))
  )
    (map-set user-positions user new-positions)
    (ok true)
  )
)

;; Helper function for filtering positions
(define-private (is-not-target-position (pos-id uint))
  (not (is-eq pos-id (var-get next-position-id)))) ;; This will be set to target in actual usage

;; Admin functions
(define-public (set-admin (new-admin principal))
  (begin
    (asserts! (is-admin tx-sender) (err err-not-admin))
    (var-set admin new-admin)
    (print {event: "admin-updated", by: tx-sender, new-admin: new-admin})
    (ok true)
  )
)

(define-public (set-fee (new-fee uint))
  (begin
    (asserts! (is-admin tx-sender) (err err-not-admin))
    (asserts! (<= new-fee u100000) (err err-fee-too-high))
    (var-set fee new-fee)
    (print {event: "fee-updated", by: tx-sender, new-fee: new-fee})
    (ok true)
  )
)

(define-public (set-treasury (new-treasury principal))
  (begin
    (asserts! (is-admin tx-sender) (err err-not-admin))
    (var-set treasury new-treasury)
    (print {event: "treasury-updated", by: tx-sender, new-treasury: new-treasury})
    (ok true)
  )
)

(define-public (pause)
  (begin
    (asserts! (is-admin tx-sender) (err err-not-admin))
    (var-set paused true)
    (var-set pause-block stacks-block-height)
    (print {event: "paused", by: tx-sender, at-block: stacks-block-height})
    (ok true)
  )
)

(define-public (unpause)
  (begin
    (asserts! (is-admin tx-sender) (err err-not-admin))
    (var-set paused false)
    (print {event: "unpaused", by: tx-sender, at-block: stacks-block-height})
    (ok true)
  )
)

;; Referral registration
(define-public (register-referral (referrer principal))
  (begin
    (asserts! (not (is-eq tx-sender referrer)) (err err-no-referral))
    (asserts! (is-none (map-get? referrals tx-sender)) (err err-no-referral)) ;; Can only register once
    (map-set referrals tx-sender referrer)
    (print {event: "referral-registered", user: tx-sender, referrer: referrer})
    (ok true)
  )
)

;; Internal deposit logic
(define-private (internal-deposit (user principal) (amount uint))
  (let (
    (current-balance (default-to u0 (map-get? staking-balances user)))
    (new-balance (+ current-balance amount))
  )
    (map-set staking-balances user new-balance)
    (var-set total-staked (+ (var-get total-staked) amount))
    (unwrap-panic (update-user-tier user)) ;; Update tier after deposit
    (print {event: "deposit", user: user, amount: amount, new-balance: new-balance})
    (ok true)
  )
)

;; Internal withdrawal logic
(define-private (internal-withdraw (user principal) (amount uint))
  (let (
    (current-balance (default-to u0 (map-get? staking-balances user)))
  )
    (asserts! (>= current-balance amount) (err err-insufficient-balance))
    (let ((new-balance (- current-balance amount)))
      (if (is-eq new-balance u0)
        (map-delete staking-balances user)
        (map-set staking-balances user new-balance)
      )
      (var-set total-staked (- (var-get total-staked) amount))
      (unwrap-panic (update-user-tier user)) ;; Update tier after withdrawal
      (print {event: "withdraw", user: user, amount: amount, new-balance: new-balance})
      (ok true)
    )
  )
)

;; Create a liquid staking position (NFT)
(define-public (create-staking-position (amount uint) (lock-period uint))
  (begin
    (asserts! (not (var-get paused)) (err err-paused))
    (asserts! (> amount u0) (err err-invalid-amount))
    
    (let (
      (position-id (var-get next-position-id))
      (current-tier (calculate-tier (+ (default-to u0 (map-get? staking-balances tx-sender)) amount)))
      (multiplier (get-tier-multiplier current-tier))
      (calculated-fee (calculate-fee amount))
      (net-amount (- amount calculated-fee))
      (treasury-addr (var-get treasury))
      (referrer (map-get? referrals tx-sender))
      (unlock-block (if (> lock-period u0) (+ stacks-block-height lock-period) u0))
    )
      (asserts! (> amount calculated-fee) (err err-zero-deposit))
      
      ;; Mint tokens to user (1:1 ratio with staked amount)
      (try! (ft-mint? sbtc-token amount tx-sender))
      
      ;; Transfer fee to treasury
      (try! (ft-transfer? sbtc-token calculated-fee tx-sender treasury-addr))
      (print {event: "fee-paid", payer: tx-sender, amount: calculated-fee})

      ;; Handle referral rewards
      (match referrer
        ref (begin
          (try! (ft-mint? sbtc-token u10 ref)) ;; Mint referral reward
          (print {event: "referral-rewarded", user: tx-sender, referrer: ref, reward: u10})
          true
        )
        true
      )

      ;; Create the NFT position
      (try! (nft-mint? staking-position position-id tx-sender))
      
      ;; Store position data
      (map-set staking-positions position-id {
        owner: tx-sender,
        amount: net-amount,
        created-at: stacks-block-height,
        lock-until: unlock-block,
        tier: current-tier,
        multiplier: multiplier
      })
      
      ;; Add to user's position list
      (try! (add-user-position tx-sender position-id))
      
      ;; Record the staking deposit
      (unwrap-panic (internal-deposit tx-sender net-amount))
      
      ;; Increment position ID for next use
      (var-set next-position-id (+ position-id u1))
      
      (print {event: "position-created", user: tx-sender, position-id: position-id, amount: net-amount, tier: current-tier, multiplier: multiplier})
      (ok position-id)
    )
  )
)

;; Transfer a staking position (NFT)
(define-public (transfer-position (position-id uint) (to principal))
  (begin
    (let (
      (position (unwrap! (map-get? staking-positions position-id) (err err-position-not-found)))
      (current-owner (get owner position))
    )
      (asserts! (is-eq tx-sender current-owner) (err err-not-position-owner))
      
      ;; Transfer the NFT
      (try! (nft-transfer? staking-position position-id tx-sender to))
      
      ;; Update position owner
      (map-set staking-positions position-id (merge position {owner: to}))
      
      ;; Remove from sender's positions and add to receiver's positions
      (unwrap-panic (remove-user-position tx-sender position-id))
      (try! (add-user-position to position-id))
      
      (print {event: "position-transferred", position-id: position-id, from: tx-sender, to: to})
      (ok true)
    )
  )
)

;; Redeem a staking position
(define-public (redeem-position (position-id uint))
  (begin
    (let (
      (position (unwrap! (map-get? staking-positions position-id) (err err-position-not-found)))
      (owner (get owner position))
      (amount (get amount position))
      (lock-until (get lock-until position))
    )
      (asserts! (is-eq tx-sender owner) (err err-not-position-owner))
      (asserts! (<= lock-until stacks-block-height) (err err-locked))
      
      ;; Check if user has enough tokens
      (asserts! (>= (ft-get-balance sbtc-token tx-sender) amount) (err err-insufficient-balance))
      
      ;; Burn the tokens
      (try! (ft-burn? sbtc-token amount tx-sender))
      
      ;; Burn the NFT
      (try! (nft-burn? staking-position position-id tx-sender))
      
      ;; Remove position data
      (map-delete staking-positions position-id)
      
      ;; Remove from user's position list
      (unwrap-panic (remove-user-position tx-sender position-id))
      
      ;; Update staking records
      (try! (internal-withdraw tx-sender amount))
      
      (print {event: "position-redeemed", user: tx-sender, position-id: position-id, amount: amount})
      (ok amount)
    )
  )
)

;; Core staking function with optional lock and referral (backward compatible)
(define-public (stake-and-bake (amount uint) (lock-period uint))
  (begin
    (asserts! (not (var-get paused)) (err err-paused))
    (asserts! (> amount u0) (err err-invalid-amount))
    
    (let (
      (calculated-fee (calculate-fee amount))
      (net-amount (- amount calculated-fee))
      (treasury-addr (var-get treasury))
      (referrer (map-get? referrals tx-sender))
    )
      (asserts! (> amount calculated-fee) (err err-zero-deposit))
      
      ;; Mint tokens to user (1:1 ratio with staked amount)
      (try! (ft-mint? sbtc-token amount tx-sender))
      
      ;; Transfer fee to treasury
      (try! (ft-transfer? sbtc-token calculated-fee tx-sender treasury-addr))
      (print {event: "fee-paid", payer: tx-sender, amount: calculated-fee})

      ;; Handle referral rewards
      (match referrer
        ref (begin
          (try! (ft-mint? sbtc-token u10 ref)) ;; Mint referral reward
          (print {event: "referral-rewarded", user: tx-sender, referrer: ref, reward: u10})
          true
        )
        true
      )

      ;; Set lock if requested
      (if (> lock-period u0)
        (begin
          (map-set stake-locks tx-sender (+ stacks-block-height lock-period))
          (print {event: "stake-locked", user: tx-sender, unlock-block: (+ stacks-block-height lock-period)})
          true
        )
        true
      )

      ;; Record the staking deposit
      (unwrap! (internal-deposit tx-sender net-amount) (err err-insufficient-balance))
      
      (print {event: "stake", staker: tx-sender, amount: amount, net-amount: net-amount, lock-period: lock-period})
      (ok net-amount)
    )
  )
)

;; Simple staking without lock
(define-public (stake (amount uint))
  (stake-and-bake amount u0)
)

;; Unstake with lock check
(define-public (unstake (amount uint))
  (begin
    (asserts! (> amount u0) (err err-invalid-amount))
    
    (let (
      (unlock-block (default-to u0 (map-get? stake-locks tx-sender)))
      (user-balance (ft-get-balance sbtc-token tx-sender))
    )
      ;; Check if tokens are locked
      (asserts! (<= unlock-block stacks-block-height) (err err-locked))
      
      ;; Check if user has enough tokens
      (asserts! (>= user-balance amount) (err err-insufficient-balance))
      
      ;; Burn the tokens
      (try! (ft-burn? sbtc-token amount tx-sender))
      
      ;; Update staking records
      (try! (internal-withdraw tx-sender amount))
      
      (print {event: "unstake", user: tx-sender, amount: amount})
      (ok amount)
    )
  )
)

;; Emergency unstake if paused for > 144 blocks (~24h)
(define-public (emergency-unstake (amount uint))
  (begin
    (asserts! (> amount u0) (err err-invalid-amount))
    
    (let (
      (is-paused (var-get paused))
      (pause-block-val (var-get pause-block))
      (user-balance (ft-get-balance sbtc-token tx-sender))
    )
      ;; Check emergency conditions
      (asserts! is-paused (err err-not-allowed))
      (asserts! (>= (- stacks-block-height pause-block-val) u144) (err err-not-allowed))
      
      ;; Check if user has enough tokens
      (asserts! (>= user-balance amount) (err err-insufficient-balance))
      
      ;; Burn the tokens (emergency unstake ignores locks)
      (try! (ft-burn? sbtc-token amount tx-sender))
      
      ;; Update staking records
      (try! (internal-withdraw tx-sender amount))
      
      (print {event: "emergency-unstake", user: tx-sender, amount: amount})
      (ok amount)
    )
  )
)

;; Unlock staked tokens (remove lock)
(define-public (unlock-stake)
  (begin
    (let ((unlock-block (default-to u0 (map-get? stake-locks tx-sender))))
      (asserts! (>= stacks-block-height unlock-block) (err err-locked))
      (map-delete stake-locks tx-sender)
      (print {event: "stake-unlocked", user: tx-sender})
      (ok true)
    )
  )
)

;; Admin function to mint rewards (for yield distribution)
(define-public (mint-rewards (recipient principal) (amount uint))
  (begin
    (asserts! (is-admin tx-sender) (err err-not-admin))
    (try! (ft-mint? sbtc-token amount recipient))
    (print {event: "rewards-minted", recipient: recipient, amount: amount})
    (ok true)
  )
)

;; Admin function to burn tokens (for rebalancing)
(define-public (admin-burn (amount uint))
  (begin
    (asserts! (is-admin tx-sender) (err err-not-admin))
    (try! (ft-burn? sbtc-token amount tx-sender))
    (print {event: "admin-burn", amount: amount})
    (ok true)
  )
)