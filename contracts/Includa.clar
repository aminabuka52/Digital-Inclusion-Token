
(define-fungible-token includa-token)

(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_OWNER_ONLY (err u100))
(define-constant ERR_NOT_TOKEN_OWNER (err u101))
(define-constant ERR_INSUFFICIENT_BALANCE (err u102))
(define-constant ERR_ALREADY_VERIFIED (err u103))
(define-constant ERR_NOT_VERIFIED (err u104))
(define-constant ERR_INVALID_AMOUNT (err u105))
(define-constant ERR_COOLDOWN_ACTIVE (err u106))
(define-constant ERR_MAX_SUPPLY_REACHED (err u107))
(define-constant ERR_INVALID_MILESTONE (err u108))

(define-data-var token-name (string-ascii 32) "Includa")
(define-data-var token-symbol (string-ascii 10) "INCL")
(define-data-var token-decimals uint u6)
(define-data-var total-supply uint u0)
(define-data-var max-supply uint u1000000000000)
(define-data-var verification-reward uint u100000000)
(define-data-var milestone-reward uint u50000000)
(define-data-var referral-reward uint u25000000)
(define-data-var contract-enabled bool true)

(define-map user-verification principal bool)
(define-map user-milestones principal uint)
(define-map user-last-claim principal uint)
(define-map user-referrer principal principal)
(define-map referral-count principal uint)
(define-map user-total-earned principal uint)
(define-map admin-list principal bool)

(define-read-only (get-name)
    (ok (var-get token-name)))

(define-read-only (get-symbol)
    (ok (var-get token-symbol)))

(define-read-only (get-decimals)
    (ok (var-get token-decimals)))

(define-read-only (get-balance (user principal))
    (ok (ft-get-balance includa-token user)))

(define-read-only (get-total-supply)
    (ok (ft-get-supply includa-token)))

(define-read-only (get-token-uri)
    (ok none))

(define-read-only (get-max-supply)
    (var-get max-supply))

(define-read-only (is-verified (user principal))
    (default-to false (map-get? user-verification user)))

(define-read-only (get-user-milestones (user principal))
    (default-to u0 (map-get? user-milestones user)))

(define-read-only (get-referral-count (user principal))
    (default-to u0 (map-get? referral-count user)))

(define-read-only (get-user-total-earned (user principal))
    (default-to u0 (map-get? user-total-earned user)))

(define-read-only (get-last-claim-block (user principal))
    (default-to u0 (map-get? user-last-claim user)))

(define-read-only (get-cooldown-remaining (user principal))
    (let ((last-claim (get-last-claim-block user))
          (current-block stacks-block-height)
          (cooldown-period u144))
        (if (>= current-block (+ last-claim cooldown-period))
            u0
            (- (+ last-claim cooldown-period) current-block))))

(define-read-only (is-admin (user principal))
    (or (is-eq user CONTRACT_OWNER) 
        (default-to false (map-get? admin-list user))))

(define-public (transfer (amount uint) (sender principal) (recipient principal) (memo (optional (buff 34))))
    (begin
        (asserts! (or (is-eq tx-sender sender) (is-eq contract-caller sender)) ERR_NOT_TOKEN_OWNER)
        (ft-transfer? includa-token amount sender recipient)))

(define-public (verify-new-user)
    (let ((user tx-sender))
        (asserts! (var-get contract-enabled) ERR_OWNER_ONLY)
        (asserts! (not (is-verified user)) ERR_ALREADY_VERIFIED)
        (asserts! (<= (+ (ft-get-supply includa-token) (var-get verification-reward)) (var-get max-supply)) ERR_MAX_SUPPLY_REACHED)
        (try! (ft-mint? includa-token (var-get verification-reward) user))
        (map-set user-verification user true)
        (map-set user-milestones user u1)
        (map-set user-last-claim user stacks-block-height)
        (map-set user-total-earned user (var-get verification-reward))
        (var-set total-supply (+ (var-get total-supply) (var-get verification-reward)))
        (ok true)))

(define-public (verify-with-referral (referrer principal))
    (let ((user tx-sender))
        (asserts! (var-get contract-enabled) ERR_OWNER_ONLY)
        (asserts! (not (is-verified user)) ERR_ALREADY_VERIFIED)
        (asserts! (is-verified referrer) ERR_NOT_VERIFIED)
        (asserts! (not (is-eq user referrer)) ERR_INVALID_AMOUNT)
        (asserts! (<= (+ (ft-get-supply includa-token) (+ (var-get verification-reward) (var-get referral-reward))) (var-get max-supply)) ERR_MAX_SUPPLY_REACHED)
        (try! (ft-mint? includa-token (var-get verification-reward) user))
        (try! (ft-mint? includa-token (var-get referral-reward) referrer))
        (map-set user-verification user true)
        (map-set user-milestones user u1)
        (map-set user-last-claim user stacks-block-height)
        (map-set user-referrer user referrer)
        (map-set referral-count referrer (+ (get-referral-count referrer) u1))
        (map-set user-total-earned user (var-get verification-reward))
        (map-set user-total-earned referrer (+ (get-user-total-earned referrer) (var-get referral-reward)))
        (var-set total-supply (+ (var-get total-supply) (+ (var-get verification-reward) (var-get referral-reward))))
        (ok true)))

(define-public (claim-milestone-reward (milestone uint))
    (let ((user tx-sender)
          (current-milestone (get-user-milestones user))
          (cooldown (get-cooldown-remaining user)))
        (asserts! (var-get contract-enabled) ERR_OWNER_ONLY)
        (asserts! (is-verified user) ERR_NOT_VERIFIED)
        (asserts! (is-eq cooldown u0) ERR_COOLDOWN_ACTIVE)
        (asserts! (is-eq milestone (+ current-milestone u1)) ERR_INVALID_MILESTONE)
        (asserts! (<= milestone u10) ERR_INVALID_MILESTONE)
        (asserts! (<= (+ (ft-get-supply includa-token) (var-get milestone-reward)) (var-get max-supply)) ERR_MAX_SUPPLY_REACHED)
        (try! (ft-mint? includa-token (var-get milestone-reward) user))
        (map-set user-milestones user milestone)
        (map-set user-last-claim user stacks-block-height)
        (map-set user-total-earned user (+ (get-user-total-earned user) (var-get milestone-reward)))
        (var-set total-supply (+ (var-get total-supply) (var-get milestone-reward)))
        (ok true)))

(define-public (daily-engagement-reward)
    (let ((user tx-sender)
          (cooldown (get-cooldown-remaining user))
          (daily-reward u10000000))
        (asserts! (var-get contract-enabled) ERR_OWNER_ONLY)
        (asserts! (is-verified user) ERR_NOT_VERIFIED)
        (asserts! (is-eq cooldown u0) ERR_COOLDOWN_ACTIVE)
        (asserts! (<= (+ (ft-get-supply includa-token) daily-reward) (var-get max-supply)) ERR_MAX_SUPPLY_REACHED)
        (try! (ft-mint? includa-token daily-reward user))
        (map-set user-last-claim user stacks-block-height)
        (map-set user-total-earned user (+ (get-user-total-earned user) daily-reward))
        (var-set total-supply (+ (var-get total-supply) daily-reward))
        (ok true)))

(define-public (set-verification-reward (new-reward uint))
    (begin
        (asserts! (is-admin tx-sender) ERR_OWNER_ONLY)
        (asserts! (> new-reward u0) ERR_INVALID_AMOUNT)
        (var-set verification-reward new-reward)
        (ok true)))

(define-public (set-milestone-reward (new-reward uint))
    (begin
        (asserts! (is-admin tx-sender) ERR_OWNER_ONLY)
        (asserts! (> new-reward u0) ERR_INVALID_AMOUNT)
        (var-set milestone-reward new-reward)
        (ok true)))

(define-public (set-referral-reward (new-reward uint))
    (begin
        (asserts! (is-admin tx-sender) ERR_OWNER_ONLY)
        (asserts! (> new-reward u0) ERR_INVALID_AMOUNT)
        (var-set referral-reward new-reward)
        (ok true)))

(define-public (set-max-supply (new-max uint))
    (begin
        (asserts! (is-admin tx-sender) ERR_OWNER_ONLY)
        (asserts! (>= new-max (ft-get-supply includa-token)) ERR_INVALID_AMOUNT)
        (var-set max-supply new-max)
        (ok true)))

(define-public (toggle-contract (enabled bool))
    (begin
        (asserts! (is-admin tx-sender) ERR_OWNER_ONLY)
        (var-set contract-enabled enabled)
        (ok true)))

(define-public (add-admin (new-admin principal))
    (begin
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_OWNER_ONLY)
        (map-set admin-list new-admin true)
        (ok true)))

(define-public (remove-admin (admin principal))
    (begin
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_OWNER_ONLY)
        (map-delete admin-list admin)
        (ok true)))

(define-public (emergency-mint (recipient principal) (amount uint))
    (begin
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_OWNER_ONLY)
        (asserts! (<= (+ (ft-get-supply includa-token) amount) (var-get max-supply)) ERR_MAX_SUPPLY_REACHED)
        (try! (ft-mint? includa-token amount recipient))
        (var-set total-supply (+ (var-get total-supply) amount))
        (ok true)))

(define-public (bulk-verify-users (users (list 50 principal)))
    (begin
        (asserts! (is-admin tx-sender) ERR_OWNER_ONLY)
        (ok (map verify-user-internal users))))

(define-private (verify-user-internal (user principal))
    (begin
        (map-set user-verification user true)
        (map-set user-milestones user u1)
        (map-set user-last-claim user stacks-block-height)
        true))

(define-read-only (get-contract-stats)
    (ok {
        total-supply: (ft-get-supply includa-token),
        max-supply: (var-get max-supply),
        verification-reward: (var-get verification-reward),
        milestone-reward: (var-get milestone-reward),
        referral-reward: (var-get referral-reward),
        contract-enabled: (var-get contract-enabled)
    }))
