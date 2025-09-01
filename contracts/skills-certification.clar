;; Digital Skills Assessment & Certification System
;; Provides verifiable digital literacy certifications through on-chain assessments

(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_OWNER_ONLY (err u200))
(define-constant ERR_NOT_VERIFIED (err u201))
(define-constant ERR_INVALID_SKILL (err u202))
(define-constant ERR_ALREADY_CERTIFIED (err u203))
(define-constant ERR_INSUFFICIENT_SCORE (err u204))
(define-constant ERR_ASSESSMENT_NOT_FOUND (err u205))
(define-constant ERR_INVALID_DIFFICULTY (err u206))
(define-constant ERR_COOLDOWN_ACTIVE (err u207))
(define-constant ERR_ASSESSMENT_EXPIRED (err u208))
(define-constant ERR_INVALID_ANSWER_COUNT (err u209))
(define-constant ERR_CONTRACT_DISABLED (err u210))

;; Skill categories
(define-constant SKILL_WEB_NAVIGATION u1)
(define-constant SKILL_MOBILE_APPS u2)
(define-constant SKILL_DIGITAL_SECURITY u3)
(define-constant SKILL_ONLINE_COMMUNICATION u4)
(define-constant SKILL_DIGITAL_PAYMENTS u5)
(define-constant SKILL_CLOUD_STORAGE u6)
(define-constant SKILL_SOCIAL_MEDIA u7)
(define-constant SKILL_ONLINE_LEARNING u8)

;; Difficulty levels
(define-constant DIFFICULTY_BEGINNER u1)
(define-constant DIFFICULTY_INTERMEDIATE u2)
(define-constant DIFFICULTY_ADVANCED u3)

;; Contract state
(define-data-var contract-enabled bool true)
(define-data-var assessment-id-nonce uint u0)
(define-map admin-list principal bool)
(define-data-var certification-cooldown uint u1440) ;; 10 days in blocks
(define-data-var passing-score uint u70) ;; 70% to pass

;; User certification tracking
(define-map user-certifications {user: principal, skill: uint, difficulty: uint} {
    certified: bool,
    score: uint,
    certification-date: uint,
    expiry-date: uint
})

;; Active assessments (temporary session data)
(define-map active-assessments {user: principal, assessment-id: uint} {
    skill: uint,
    difficulty: uint,
    questions-total: uint,
    correct-answers: uint,
    start-block: uint,
    expiry-block: uint
})

;; Assessment templates (questions stored off-chain, only metadata on-chain)
(define-map assessment-templates {skill: uint, difficulty: uint} {
    questions-count: uint,
    time-limit-blocks: uint,
    certification-validity-blocks: uint,
    reward-amount: uint,
    enabled: bool
})

;; User assessment history
(define-map user-assessment-history {user: principal, skill: uint} {
    attempts: uint,
    best-score: uint,
    last-attempt-block: uint
})

;; Skill prerequisites (what skills must be certified before attempting another)
(define-map skill-prerequisites {skill: uint, difficulty: uint} (list 10 {skill: uint, difficulty: uint}))

;; Initialize default assessment templates
(map-set assessment-templates {skill: SKILL_WEB_NAVIGATION, difficulty: DIFFICULTY_BEGINNER}
    {questions-count: u10, time-limit-blocks: u100, certification-validity-blocks: u21600, reward-amount: u75000000, enabled: true})

(map-set assessment-templates {skill: SKILL_MOBILE_APPS, difficulty: DIFFICULTY_BEGINNER}
    {questions-count: u8, time-limit-blocks: u80, certification-validity-blocks: u21600, reward-amount: u60000000, enabled: true})

(map-set assessment-templates {skill: SKILL_DIGITAL_SECURITY, difficulty: DIFFICULTY_INTERMEDIATE}
    {questions-count: u15, time-limit-blocks: u120, certification-validity-blocks: u14400, reward-amount: u100000000, enabled: true})

(map-set assessment-templates {skill: SKILL_ONLINE_COMMUNICATION, difficulty: DIFFICULTY_BEGINNER}
    {questions-count: u12, time-limit-blocks: u90, certification-validity-blocks: u21600, reward-amount: u80000000, enabled: true})

;; Read-only functions
(define-read-only (get-certification-status (user principal) (skill uint) (difficulty uint))
    (match (map-get? user-certifications {user: user, skill: skill, difficulty: difficulty})
        cert-data (let ((current-block stacks-block-height)
                        (expiry (get expiry-date cert-data)))
                    (ok {
                        certified: (and (get certified cert-data) (< current-block expiry)),
                        score: (get score cert-data),
                        certification-date: (get certification-date cert-data),
                        expiry-date: expiry,
                        is-expired: (>= current-block expiry)
                    }))
        (ok {certified: false, score: u0, certification-date: u0, expiry-date: u0, is-expired: false})))

(define-read-only (get-user-certifications (user principal))
    (ok (list 
        (unwrap-panic (get-certification-status user SKILL_WEB_NAVIGATION DIFFICULTY_BEGINNER))
        (unwrap-panic (get-certification-status user SKILL_MOBILE_APPS DIFFICULTY_BEGINNER))
        (unwrap-panic (get-certification-status user SKILL_DIGITAL_SECURITY DIFFICULTY_INTERMEDIATE))
        (unwrap-panic (get-certification-status user SKILL_ONLINE_COMMUNICATION DIFFICULTY_BEGINNER)))))

(define-read-only (get-assessment-template (skill uint) (difficulty uint))
    (map-get? assessment-templates {skill: skill, difficulty: difficulty}))

(define-read-only (get-active-assessment (user principal) (assessment-id uint))
    (map-get? active-assessments {user: user, assessment-id: assessment-id}))

(define-read-only (get-assessment-history (user principal) (skill uint))
    (default-to {attempts: u0, best-score: u0, last-attempt-block: u0}
        (map-get? user-assessment-history {user: user, skill: skill})))

(define-read-only (check-prerequisites (user principal) (skill uint) (difficulty uint))
    (match (map-get? skill-prerequisites {skill: skill, difficulty: difficulty})
        prereq-list (fold check-single-prerequisite prereq-list {user: user, result: true})
        {user: user, result: true}))

(define-read-only (is-admin (user principal))
    (or (is-eq user CONTRACT_OWNER) 
        (default-to false (map-get? admin-list user))))

(define-read-only (can-attempt-assessment (user principal) (skill uint) (difficulty uint))
    (let ((history (get-assessment-history user skill))
          (last-attempt (get last-attempt-block history))
          (cooldown-remaining (if (> last-attempt u0)
                                 (if (>= stacks-block-height (+ last-attempt (var-get certification-cooldown)))
                                     u0
                                     (- (+ last-attempt (var-get certification-cooldown)) stacks-block-height))
                                 u0))
          (prereqs-met (get result (check-prerequisites user skill difficulty))))
        (ok {
            can-attempt: (and prereqs-met (is-eq cooldown-remaining u0)),
            cooldown-remaining: cooldown-remaining,
            prerequisites-met: prereqs-met,
            attempts-made: (get attempts history)
        })))

;; Private helper function for prerequisite checking
(define-private (check-single-prerequisite (prereq {skill: uint, difficulty: uint}) (acc {user: principal, result: bool}))
    (if (get result acc)
        (let ((cert-status (unwrap-panic (get-certification-status (get user acc) (get skill prereq) (get difficulty prereq)))))
            {user: (get user acc), result: (get certified cert-status)})
        acc))

;; Assessment lifecycle functions
(define-public (start-assessment (skill uint) (difficulty uint))
    (let ((user tx-sender)
          (assessment-id (+ (var-get assessment-id-nonce) u1)))
        (asserts! (var-get contract-enabled) ERR_CONTRACT_DISABLED)
        (asserts! (>= skill u1) ERR_INVALID_SKILL)
        (asserts! (<= skill u8) ERR_INVALID_SKILL)
        (asserts! (>= difficulty u1) ERR_INVALID_DIFFICULTY)
        (asserts! (<= difficulty u3) ERR_INVALID_DIFFICULTY)
        
        (match (get-assessment-template skill difficulty)
            template (let ((can-attempt-result (unwrap-panic (can-attempt-assessment user skill difficulty))))
                        (asserts! (get can-attempt can-attempt-result) ERR_COOLDOWN_ACTIVE)
                        (asserts! (get enabled template) ERR_INVALID_SKILL)
                        
                        ;; Create active assessment session
                        (map-set active-assessments {user: user, assessment-id: assessment-id}
                            {
                                skill: skill,
                                difficulty: difficulty,
                                questions-total: (get questions-count template),
                                correct-answers: u0,
                                start-block: stacks-block-height,
                                expiry-block: (+ stacks-block-height (get time-limit-blocks template))
                            })
                        
                        ;; Update assessment ID nonce
                        (var-set assessment-id-nonce assessment-id)
                        
                        ;; Update user history
                        (let ((history (get-assessment-history user skill)))
                            (map-set user-assessment-history {user: user, skill: skill}
                                {
                                    attempts: (+ (get attempts history) u1),
                                    best-score: (get best-score history),
                                    last-attempt-block: stacks-block-height
                                }))
                        
                        (ok assessment-id))
            ERR_ASSESSMENT_NOT_FOUND)))

(define-public (submit-assessment-answers (assessment-id uint) (correct-count uint))
    (let ((user tx-sender))
        (asserts! (var-get contract-enabled) ERR_CONTRACT_DISABLED)
        
        (match (get-active-assessment user assessment-id)
            assessment-data (let ((current-block stacks-block-height)
                                 (expiry-block (get expiry-block assessment-data))
                                 (total-questions (get questions-total assessment-data))
                                 (skill (get skill assessment-data))
                                 (difficulty (get difficulty assessment-data)))
                               
                               (asserts! (< current-block expiry-block) ERR_ASSESSMENT_EXPIRED)
                               (asserts! (<= correct-count total-questions) ERR_INVALID_ANSWER_COUNT)
                               
                               ;; Calculate score percentage
                               (let ((score-percentage (/ (* correct-count u100) total-questions))
                                     (template (unwrap-panic (get-assessment-template skill difficulty))))
                                   
                                   ;; Update assessment history
                                   (let ((history (get-assessment-history user skill)))
                                       (map-set user-assessment-history {user: user, skill: skill}
                                           {
                                               attempts: (get attempts history),
                                               best-score: (if (> score-percentage (get best-score history))
                                                             score-percentage
                                                             (get best-score history)),
                                               last-attempt-block: current-block
                                           }))
                                   
                                   ;; If passed, issue certification
                                   (if (>= score-percentage (var-get passing-score))
                                       (begin
                                           (map-set user-certifications {user: user, skill: skill, difficulty: difficulty}
                                               {
                                                   certified: true,
                                                   score: score-percentage,
                                                   certification-date: current-block,
                                                   expiry-date: (+ current-block (get certification-validity-blocks template))
                                               })
                                           
                                           ;; Mint reward tokens
                                           (match (contract-call? .Includa transfer (get reward-amount template) (as-contract tx-sender) user none)
                                               success-result (begin
                                                   ;; Clean up active assessment
                                                   (map-delete active-assessments {user: user, assessment-id: assessment-id})
                                                   (ok {passed: true, score: score-percentage, certified: true, reward: (get reward-amount template)}))
                                               error-result (ok {passed: true, score: score-percentage, certified: true, reward: u0})))
                                       
                                       (begin
                                           ;; Clean up active assessment
                                           (map-delete active-assessments {user: user, assessment-id: assessment-id})
                                           (ok {passed: false, score: score-percentage, certified: false, reward: u0})))))
            ERR_ASSESSMENT_NOT_FOUND)))

(define-public (renew-certification (skill uint) (difficulty uint))
    (let ((user tx-sender))
        (asserts! (var-get contract-enabled) ERR_CONTRACT_DISABLED)
        
        (match (map-get? user-certifications {user: user, skill: skill, difficulty: difficulty})
            cert-data (let ((current-block stacks-block-height)
                           (expiry-date (get expiry-date cert-data)))
                          (asserts! (and (get certified cert-data) (>= current-block expiry-date)) ERR_ALREADY_CERTIFIED)
                          
                          ;; Check cooldown before renewal
                          (let ((can-attempt-result (unwrap-panic (can-attempt-assessment user skill difficulty))))
                              (asserts! (get can-attempt can-attempt-result) ERR_COOLDOWN_ACTIVE)
                              
                              ;; Start new assessment for renewal
                              (start-assessment skill difficulty)))
            ERR_ASSESSMENT_NOT_FOUND)))

;; Batch certification checking
(define-public (check-multiple-certifications (user principal) (skill-difficulty-pairs (list 20 {skill: uint, difficulty: uint})))
    (ok (map get-cert-status-for-pair skill-difficulty-pairs)))

(define-private (get-cert-status-for-pair (pair {skill: uint, difficulty: uint}))
    (let ((user tx-sender))
        (unwrap-panic (get-certification-status user (get skill pair) (get difficulty pair)))))

;; Admin functions
(define-public (add-assessment-template (skill uint) (difficulty uint) (questions-count uint) 
                                       (time-limit-blocks uint) (validity-blocks uint) (reward-amount uint))
    (begin
        (asserts! (is-admin tx-sender) ERR_OWNER_ONLY)
        (asserts! (>= skill u1) ERR_INVALID_SKILL)
        (asserts! (<= skill u8) ERR_INVALID_SKILL)
        (asserts! (>= difficulty u1) ERR_INVALID_DIFFICULTY)
        (asserts! (<= difficulty u3) ERR_INVALID_DIFFICULTY)
        (asserts! (> questions-count u0) ERR_INVALID_ANSWER_COUNT)
        
        (map-set assessment-templates {skill: skill, difficulty: difficulty}
            {
                questions-count: questions-count,
                time-limit-blocks: time-limit-blocks,
                certification-validity-blocks: validity-blocks,
                reward-amount: reward-amount,
                enabled: true
            })
        (ok true)))

(define-public (toggle-assessment-template (skill uint) (difficulty uint) (enabled bool))
    (begin
        (asserts! (is-admin tx-sender) ERR_OWNER_ONLY)
        
        (match (get-assessment-template skill difficulty)
            template (begin
                        (map-set assessment-templates {skill: skill, difficulty: difficulty}
                            (merge template {enabled: enabled}))
                        (ok true))
            ERR_ASSESSMENT_NOT_FOUND)))

(define-public (set-skill-prerequisites (skill uint) (difficulty uint) (prerequisites (list 10 {skill: uint, difficulty: uint})))
    (begin
        (asserts! (is-admin tx-sender) ERR_OWNER_ONLY)
        (asserts! (>= skill u1) ERR_INVALID_SKILL)
        (asserts! (<= skill u8) ERR_INVALID_SKILL)
        (map-set skill-prerequisites {skill: skill, difficulty: difficulty} prerequisites)
        (ok true)))

(define-public (set-passing-score (new-score uint))
    (begin
        (asserts! (is-admin tx-sender) ERR_OWNER_ONLY)
        (asserts! (>= new-score u1) ERR_INSUFFICIENT_SCORE)
        (asserts! (<= new-score u100) ERR_INSUFFICIENT_SCORE)
        (var-set passing-score new-score)
        (ok true)))

(define-public (set-certification-cooldown (new-cooldown uint))
    (begin
        (asserts! (is-admin tx-sender) ERR_OWNER_ONLY)
        (var-set certification-cooldown new-cooldown)
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

(define-public (toggle-contract (enabled bool))
    (begin
        (asserts! (is-admin tx-sender) ERR_OWNER_ONLY)
        (var-set contract-enabled enabled)
        (ok true)))

;; Emergency function to manually certify users (for migration or special cases)
(define-public (emergency-certify-user (user principal) (skill uint) (difficulty uint) (score uint))
    (begin
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_OWNER_ONLY)
        (asserts! (>= score (var-get passing-score)) ERR_INSUFFICIENT_SCORE)
        (asserts! (<= score u100) ERR_INSUFFICIENT_SCORE)
        
        (match (get-assessment-template skill difficulty)
            template (begin
                        (map-set user-certifications {user: user, skill: skill, difficulty: difficulty}
                            {
                                certified: true,
                                score: score,
                                certification-date: stacks-block-height,
                                expiry-date: (+ stacks-block-height (get certification-validity-blocks template))
                            })
                        (ok true))
            ERR_ASSESSMENT_NOT_FOUND)))

;; Utility functions for skill management
(define-read-only (get-skill-name (skill uint))
    (if (is-eq skill SKILL_WEB_NAVIGATION) (ok "Web Navigation")
    (if (is-eq skill SKILL_MOBILE_APPS) (ok "Mobile Apps")
    (if (is-eq skill SKILL_DIGITAL_SECURITY) (ok "Digital Security")
    (if (is-eq skill SKILL_ONLINE_COMMUNICATION) (ok "Online Communication")
    (if (is-eq skill SKILL_DIGITAL_PAYMENTS) (ok "Digital Payments")
    (if (is-eq skill SKILL_CLOUD_STORAGE) (ok "Cloud Storage")
    (if (is-eq skill SKILL_SOCIAL_MEDIA) (ok "Social Media")
    (if (is-eq skill SKILL_ONLINE_LEARNING) (ok "Online Learning")
        ERR_INVALID_SKILL)))))))))

(define-read-only (get-difficulty-name (difficulty uint))
    (if (is-eq difficulty DIFFICULTY_BEGINNER) (ok "Beginner")
    (if (is-eq difficulty DIFFICULTY_INTERMEDIATE) (ok "Intermediate")
    (if (is-eq difficulty DIFFICULTY_ADVANCED) (ok "Advanced")
        ERR_INVALID_DIFFICULTY))))

(define-read-only (get-contract-stats)
    (ok {
        total-assessments-created: (var-get assessment-id-nonce),
        passing-score: (var-get passing-score),
        certification-cooldown: (var-get certification-cooldown),
        contract-enabled: (var-get contract-enabled)
    }))

;; Get comprehensive user profile including all certifications and assessment history
(define-read-only (get-user-profile (user principal))
    (ok {
        web-navigation-beginner: (unwrap-panic (get-certification-status user SKILL_WEB_NAVIGATION DIFFICULTY_BEGINNER)),
        mobile-apps-beginner: (unwrap-panic (get-certification-status user SKILL_MOBILE_APPS DIFFICULTY_BEGINNER)),
        digital-security-intermediate: (unwrap-panic (get-certification-status user SKILL_DIGITAL_SECURITY DIFFICULTY_INTERMEDIATE)),
        online-communication-beginner: (unwrap-panic (get-certification-status user SKILL_ONLINE_COMMUNICATION DIFFICULTY_BEGINNER)),
        web-nav-history: (get-assessment-history user SKILL_WEB_NAVIGATION),
        mobile-apps-history: (get-assessment-history user SKILL_MOBILE_APPS),
        digital-security-history: (get-assessment-history user SKILL_DIGITAL_SECURITY),
        online-comm-history: (get-assessment-history user SKILL_ONLINE_COMMUNICATION)
    }))

;; Cleanup expired assessments
(define-public (cleanup-expired-assessment (user principal) (assessment-id uint))
    (match (get-active-assessment user assessment-id)
        assessment-data (if (>= stacks-block-height (get expiry-block assessment-data))
                           (begin
                               (map-delete active-assessments {user: user, assessment-id: assessment-id})
                               (ok true))
                           (ok false))
        (ok false)))

;; Bulk operations for efficient management
(define-public (bulk-cleanup-expired-assessments (assessment-sessions (list 20 {user: principal, assessment-id: uint})))
    (begin
        (asserts! (is-admin tx-sender) ERR_OWNER_ONLY)
        (ok (map cleanup-assessment-entry assessment-sessions))))

(define-private (cleanup-assessment-entry (session {user: principal, assessment-id: uint}))
    (unwrap-panic (cleanup-expired-assessment (get user session) (get assessment-id session))))
