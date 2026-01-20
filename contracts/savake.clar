;; Savake Liquid Staking Protocol
;; A comprehensive staking system with liquid staking derivatives

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-token-owner (err u101))
(define-constant err-insufficient-balance (err u102))
(define-constant err-contract-paused (err u103))
(define-constant err-invalid-amount (err u104))
(define-constant err-locked-tokens (err u105))
(define-constant err-invalid-lock-period (err u106))
(define-constant err-referrer-not-found (err u107))
(define-constant err-self-referral (err u108))
(define-constant err-already-has-referrer (err u109))
(define-constant err-invalid-tier (err u110))
(define-constant err-position-not-found (err u111))
(define-constant err-invalid-fee (err u112))
(define-constant err-invalid-address (err u113))
(define-constant err-zero-amount (err u114))
(define-constant err-invalid-principal (err u115))
(define-constant err-insufficient-contract-balance (err u116))

;; Data Variables
(define-data-var contract-paused bool false)
(define-data-var pause-timestamp uint u0)
(define-data-var treasury-address principal tx-sender)
(define-data-var total-staked uint u0)
(define-data-var staking-fee uint u100) ;; 1% fee (100 basis points)
(define-data-var next-position-id uint u1)
(define-data-var contract-stx-balance uint u0) ;; Track STX held by contract

;; Data Maps
(define-map user-balances principal uint)
(define-map user-tiers principal uint)
(define-map user-locks principal uint)
(define-map user-referrers principal principal)
(define-map user-positions principal (list 100 uint))
(define-map position-details uint {
    owner: principal,
    amount: uint,
    created-at: uint,
    lock-period: uint,
    tier: uint,
    multiplier: uint
})

;; SIP-010 Fungible Token Implementation
(define-fungible-token savake-token)

;; NFT for liquid staking positions
(define-non-fungible-token staking-position uint)

;; Input validation helpers
(define-private (is-valid-amount (amount uint))
    (> amount u0))

(define-private (is-valid-principal (principal-to-check principal))
    (not (is-eq principal-to-check 'SP000000000000000000002Q6VF78)))

(define-private (is-valid-lock-period (period uint))
    (<= period u52560)) ;; Max 1 year in blocks

;; SIP-010 Token Standard Functions
(define-public (transfer (amount uint) (from principal) (to principal) (memo (optional (buff 34))))
    (begin
        ;; Input validation
        (asserts! (is-valid-amount amount) err-zero-amount)
        (asserts! (is-valid-principal from) err-invalid-principal)
        (asserts! (is-valid-principal to) err-invalid-principal)
        (asserts! (is-eq tx-sender from) err-not-token-owner)
        
        (ft-transfer? savake-token amount from to)
    ))

(define-read-only (get-name)
    (ok "Savake Token"))

(define-read-only (get-symbol)
    (ok "SAVAKE"))

(define-read-only (get-decimals)
    (ok u6))

(define-read-only (get-balance (who principal))
    (begin
        (asserts! (is-valid-principal who) err-invalid-principal)
        (ok (ft-get-balance savake-token who))
    ))

(define-read-only (get-total-supply)
    (ok (ft-get-supply savake-token)))

(define-read-only (get-token-uri)
    (ok (some u"https://savake.io/token-metadata.json")))

;; Tier System Functions
(define-private (calculate-tier (balance uint))
    (if (>= balance u100000)
        u4
        (if (>= balance u25000)
            u3
            (if (>= balance u5000)
                u2
                (if (>= balance u1000)
                    u1
                    u0)))))

(define-private (get-tier-multiplier (tier uint))
    (if (is-eq tier u4)
        u200  ;; 2.0x
        (if (is-eq tier u3)
            u150  ;; 1.5x
            (if (is-eq tier u2)
                u125  ;; 1.25x
                (if (is-eq tier u1)
                    u100  ;; 1.0x
                    u50)))))  ;; 0.5x for tier 0

(define-private (update-user-tier (user principal))
    (let ((balance (default-to u0 (map-get? user-balances user))))
        (begin
            (asserts! (is-valid-principal user) err-invalid-principal)
            (map-set user-tiers user (calculate-tier balance))
            (ok true))))

;; Fee Calculation
(define-private (calculate-fee (amount uint))
    (let ((fee-rate (var-get staking-fee)))
        (if (>= amount u10000)
            (/ (* amount u50) u10000)  ;; 0.5% for large deposits
            (/ (* amount fee-rate) u10000))))

;; Core Staking Functions - FIXED STX FLOW
(define-public (stake (amount uint))
    (begin
        ;; Input validation
        (asserts! (is-valid-amount amount) err-zero-amount)
        (asserts! (not (var-get contract-paused)) err-contract-paused)
        
        (let ((fee (calculate-fee amount))
              (net-amount (- amount fee))
              (current-balance (default-to u0 (map-get? user-balances tx-sender))))
            
            ;; FIXED: Transfer FULL amount to contract first
            (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
            
            ;; Update contract STX balance
            (var-set contract-stx-balance (+ (var-get contract-stx-balance) amount))
            
            ;; Send fee to treasury FROM the contract
            (try! (as-contract (stx-transfer? fee tx-sender (var-get treasury-address))))
            
            ;; Update contract balance (subtract fee sent to treasury)
            (var-set contract-stx-balance (- (var-get contract-stx-balance) fee))
            
            ;; Mint tokens to user (now backed by STX held in contract)
            (try! (ft-mint? savake-token net-amount tx-sender))
            
            ;; Update user balance
            (map-set user-balances tx-sender (+ current-balance net-amount))
            
            ;; Update total staked
            (var-set total-staked (+ (var-get total-staked) net-amount))
            
            ;; Update user tier
            (try! (update-user-tier tx-sender))
            
            ;; Handle referral rewards
            (match (map-get? user-referrers tx-sender)
                referrer (try! (ft-mint? savake-token u10 referrer))
                true)
            
            (ok net-amount))))

(define-public (stake-and-bake (amount uint) (lock-period uint))
    (begin
        ;; Input validation
        (asserts! (is-valid-amount amount) err-zero-amount)
        (asserts! (is-valid-lock-period lock-period) err-invalid-lock-period)
        (asserts! (not (var-get contract-paused)) err-contract-paused)
        
        (let ((stake-result (try! (stake amount))))
            ;; Set lock period if specified
            (if (> lock-period u0)
                (map-set user-locks tx-sender (+ stacks-block-height lock-period))
                true)
            (ok stake-result))))

;; FIXED: Proper unstaking with STX return
(define-public (unstake (amount uint))
    (begin
        ;; Input validation
        (asserts! (is-valid-amount amount) err-zero-amount)
        (asserts! (not (var-get contract-paused)) err-contract-paused)
        
        (let ((current-balance (default-to u0 (map-get? user-balances tx-sender)))
              (lock-height (default-to u0 (map-get? user-locks tx-sender)))
              (contract-balance (var-get contract-stx-balance))
              (sender tx-sender))
            
            ;; Check sufficient balance
            (asserts! (>= current-balance amount) err-insufficient-balance)
            
            ;; Check contract has enough STX
            (asserts! (>= contract-balance amount) err-insufficient-contract-balance)
            
            ;; Check if tokens are locked (unless emergency unstake conditions are met)
            (asserts! (or (<= lock-height stacks-block-height)
                         (and (var-get contract-paused)
                              (> (- stacks-block-height (var-get pause-timestamp)) u144))) ;; 24 hours
                     err-locked-tokens)
            
            ;; Burn tokens first
            (try! (ft-burn? savake-token amount tx-sender))
            
            ;; Update user balance
            (map-set user-balances tx-sender (- current-balance amount))
            
            ;; Update total staked
            (var-set total-staked (- (var-get total-staked) amount))
            
            ;; Update user tier
            (try! (update-user-tier tx-sender))
            
            ;; FIXED: Transfer STX from contract to user
            (try! (as-contract (stx-transfer? amount tx-sender sender)))
            
            ;; Update contract STX balance
            (var-set contract-stx-balance (- contract-balance amount))
            
            (ok amount))))

;; Liquid Staking Position Functions
(define-public (create-staking-position (amount uint) (lock-period uint))
    (begin
        ;; Input validation
        (asserts! (is-valid-amount amount) err-zero-amount)
        (asserts! (is-valid-lock-period lock-period) err-invalid-lock-period)
        (asserts! (not (var-get contract-paused)) err-contract-paused)
        
        (let ((position-id (var-get next-position-id))
              (user-tier (calculate-tier amount))
              (multiplier (get-tier-multiplier user-tier))
              (current-positions (default-to (list) (map-get? user-positions tx-sender))))
            
            ;; Stake the amount first
            (try! (stake amount))
            
            ;; Create NFT position
            (try! (nft-mint? staking-position position-id tx-sender))
            
            ;; Store position details
            (map-set position-details position-id {
                owner: tx-sender,
                amount: amount,
                created-at: stacks-block-height,
                lock-period: lock-period,
                tier: user-tier,
                multiplier: multiplier
            })
            
            ;; Add position to user's list
            (map-set user-positions tx-sender (unwrap! (as-max-len? (append current-positions position-id) u100) err-invalid-amount))
            
            ;; Increment position counter
            (var-set next-position-id (+ position-id u1))
            
            (ok position-id))))

(define-public (transfer-position (position-id uint) (recipient principal))
    (begin
        ;; Input validation
        (asserts! (> position-id u0) err-invalid-amount)
        (asserts! (is-valid-principal recipient) err-invalid-principal)
        
        (let ((position (unwrap! (map-get? position-details position-id) err-position-not-found)))
            ;; Verify ownership
            (asserts! (is-eq (get owner position) tx-sender) err-not-token-owner)
            
            ;; Transfer NFT
            (try! (nft-transfer? staking-position position-id tx-sender recipient))
            
            ;; Update position owner
            (map-set position-details position-id (merge position { owner: recipient }))
            
            (ok true))))

;; Referral System
(define-public (set-referrer (referrer principal))
    (begin
        ;; Input validation
        (asserts! (is-valid-principal referrer) err-invalid-principal)
        (asserts! (not (is-eq tx-sender referrer)) err-self-referral)
        (asserts! (is-none (map-get? user-referrers tx-sender)) err-already-has-referrer)
        
        (map-set user-referrers tx-sender referrer)
        (ok true)))

;; Admin Functions
(define-public (pause-contract)
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (var-set contract-paused true)
        (var-set pause-timestamp stacks-block-height)
        (ok true)))

(define-public (unpause-contract)
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (var-set contract-paused false)
        (ok true)))

(define-public (set-treasury-address (new-treasury principal))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (asserts! (is-valid-principal new-treasury) err-invalid-principal)
        (var-set treasury-address new-treasury)
        (ok true)))

(define-public (set-staking-fee (new-fee uint))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (asserts! (<= new-fee u100000) err-invalid-fee) ;; Max 10% fee
        (var-set staking-fee new-fee)
        (ok true)))

(define-public (mint-rewards (recipient principal) (amount uint))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (asserts! (is-valid-principal recipient) err-invalid-principal)
        (asserts! (is-valid-amount amount) err-zero-amount)
        (ft-mint? savake-token amount recipient)))

(define-public (burn-tokens (amount uint))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (asserts! (is-valid-amount amount) err-zero-amount)
        (ft-burn? savake-token amount tx-sender)))

;; Admin function to sync contract balance (for maintenance)
(define-public (sync-contract-balance)
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (let ((actual-balance (stx-get-balance (as-contract tx-sender))))
            (var-set contract-stx-balance actual-balance)
            (ok actual-balance))))

;; Read-only Functions
(define-read-only (get-user-balance (user principal))
    (begin
        (asserts! (is-valid-principal user) err-invalid-principal)
        (ok (default-to u0 (map-get? user-balances user)))))

(define-read-only (get-user-tier (user principal))
    (begin
        (asserts! (is-valid-principal user) err-invalid-principal)
        (ok (default-to u0 (map-get? user-tiers user)))))

(define-read-only (get-user-lock (user principal))
    (begin
        (asserts! (is-valid-principal user) err-invalid-principal)
        (ok (default-to u0 (map-get? user-locks user)))))

(define-read-only (get-position-details (position-id uint))
    (begin
        (asserts! (> position-id u0) err-invalid-amount)
        (ok (map-get? position-details position-id))))

(define-read-only (get-user-positions (user principal))
    (begin
        (asserts! (is-valid-principal user) err-invalid-principal)
        (ok (default-to (list) (map-get? user-positions user)))))

(define-read-only (get-contract-info)
    (ok {
        total-staked: (var-get total-staked),
        treasury-address: (var-get treasury-address),
        staking-fee: (var-get staking-fee),
        contract-paused: (var-get contract-paused),
        next-position-id: (var-get next-position-id),
        contract-stx-balance: (var-get contract-stx-balance)
    }))

(define-read-only (get-user-referrer (user principal))
    (begin
        (asserts! (is-valid-principal user) err-invalid-principal)
        (ok (map-get? user-referrers user))))

;; Contract solvency check
(define-read-only (get-contract-solvency)
    (let ((total-tokens (ft-get-supply savake-token))
          (contract-stx (var-get contract-stx-balance)))
        (ok {
            total-tokens-issued: total-tokens,
            contract-stx-balance: contract-stx,
            is-solvent: (>= contract-stx total-tokens),
            solvency-ratio: (if (> total-tokens u0) 
                              (/ (* contract-stx u10000) total-tokens) 
                              u10000)
        })))

;; FIXED: Emergency unstake with proper STX return
(define-public (emergency-unstake (amount uint))
    (begin
        ;; Input validation
        (asserts! (is-valid-amount amount) err-zero-amount)
        (asserts! (var-get contract-paused) err-contract-paused)
        (asserts! (> (- stacks-block-height (var-get pause-timestamp)) u144) err-locked-tokens) ;; 24 hours
        
        (let ((current-balance (default-to u0 (map-get? user-balances tx-sender)))
              (contract-balance (var-get contract-stx-balance))
              (sender tx-sender))
            
            (asserts! (>= current-balance amount) err-insufficient-balance)
            (asserts! (>= contract-balance amount) err-insufficient-contract-balance)
            
            ;; Burn tokens
            (try! (ft-burn? savake-token amount tx-sender))
            
            ;; Update balances
            (map-set user-balances tx-sender (- current-balance amount))
            (var-set total-staked (- (var-get total-staked) amount))
            
            ;; Update tier
            (try! (update-user-tier tx-sender))
            
            ;; FIXED: Return STX to user in emergency
            (try! (as-contract (stx-transfer? amount tx-sender sender)))
            
            ;; Update contract STX balance
            (var-set contract-stx-balance (- contract-balance amount))
            
            (ok amount))))
