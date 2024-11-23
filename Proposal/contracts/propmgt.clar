;; Decentralized Grant Proposal System (DGP)
;; A system for managing grant proposals with milestone-based funding

;; Constants
(define-constant CONTRACT_OWNER tx-sender)
(define-constant MINIMUM_STAKE_AMOUNT u100)
(define-constant VOTING_PERIOD u1344) ;; ~14 days in blocks (assuming 10 min/block)
(define-constant REQUIRED_MAJORITY u500) ;; 50.0% represented as 500/1000
(define-constant MAX_AMOUNT u1000000000) ;; Maximum amount allowed for proposals
(define-constant MIN_TITLE_LENGTH u4)
(define-constant MIN_DESCRIPTION_LENGTH u10)

;; Error codes
(define-constant ERR_UNAUTHORIZED (err u100))
(define-constant ERR_INVALID_PROPOSAL (err u101))
(define-constant ERR_ALREADY_VOTED (err u102))
(define-constant ERR_INSUFFICIENT_STAKE (err u103))
(define-constant ERR_VOTING_CLOSED (err u104))
(define-constant ERR_MILESTONE_INVALID (err u105))
(define-constant ERR_PROPOSAL_NOT_APPROVED (err u106))
(define-constant ERR_INVALID_AMOUNT (err u107))
(define-constant ERR_INVALID_MILESTONE_COUNT (err u108))
(define-constant ERR_INVALID_TITLE (err u109))
(define-constant ERR_INVALID_DESCRIPTION (err u110))

;; Data Maps and Variables
(define-map Proposals
    { proposal-id: uint }
    {
        proposer: principal,
        title: (string-ascii 100),
        description: (string-ascii 500),
        total-amount: uint,
        milestone-count: uint,
        current-milestone: uint,
        start-block: uint,
        end-block: uint,
        status: (string-ascii 20),
        total-votes-for: uint,
        total-votes-against: uint,
        total-voting-power: uint
    }
)

(define-map Milestones
    { proposal-id: uint, milestone-id: uint }
    {
        amount: uint,
        description: (string-ascii 200),
        status: (string-ascii 20),
        completion-proof: (optional (string-ascii 200))
    }
)

(define-map Votes
    { proposal-id: uint, voter: principal }
    {
        amount: uint,
        vote: bool,
        staked-amount: uint
    }
)

(define-map UserStakes
    { user: principal }
    { total-staked: uint }
)

(define-data-var proposal-counter uint u0)

;; Private functions
(define-private (is-contract-owner)
    (is-eq tx-sender CONTRACT_OWNER)
)

(define-private (calculate-voting-power (stake-amount uint))
    stake-amount
)

(define-private (is-valid-proposal-id (proposal-id uint))
    (<= proposal-id (var-get proposal-counter))
)

(define-private (is-valid-milestone-id (milestone-id uint) (milestone-count uint))
    (< milestone-id milestone-count)
)

(define-private (is-valid-amount (amount uint))
    (and (> amount u0) (<= amount MAX_AMOUNT))
)

(define-private (is-valid-title (title (string-ascii 100)))
    (>= (len title) MIN_TITLE_LENGTH)
)

(define-private (is-valid-description (description (string-ascii 500)))
    (>= (len description) MIN_DESCRIPTION_LENGTH)
)

(define-private (validate-and-process-vote (vote-direction bool) (voting-power uint) (proposal-data (tuple (total-votes-for uint) (total-votes-against uint) (total-voting-power uint))))
    (let (
        (safe-vote (validate-vote-bool vote-direction))
        (current-votes-for (get total-votes-for proposal-data))
        (current-votes-against (get total-votes-against proposal-data))
        (current-total-power (get total-voting-power proposal-data))
    )
        {
            total-votes-for: (if safe-vote 
                (+ current-votes-for voting-power)
                current-votes-for
            ),
            total-votes-against: (if safe-vote
                current-votes-against
                (+ current-votes-against voting-power)
            ),
            total-voting-power: (+ current-total-power voting-power)
        }
    )
)

(define-private (validate-vote-bool (vote-direction bool))
    (if vote-direction
        true
        false
    )
)

(define-private (safe-merge-proposal-votes (proposal-map {
        proposer: principal,
        title: (string-ascii 100),
        description: (string-ascii 500),
        total-amount: uint,
        milestone-count: uint,
        current-milestone: uint,
        start-block: uint,
        end-block: uint,
        status: (string-ascii 20),
        total-votes-for: uint,
        total-votes-against: uint,
        total-voting-power: uint
    }) 
    (vote-updates {
        total-votes-for: uint,
        total-votes-against: uint,
        total-voting-power: uint
    }))
    (merge proposal-map
        {
            total-votes-for: (get total-votes-for vote-updates),
            total-votes-against: (get total-votes-against vote-updates),
            total-voting-power: (get total-voting-power vote-updates)
        }
    )
)

;; Public functions
(define-public (submit-proposal (title (string-ascii 100)) 
                              (description (string-ascii 500)) 
                              (total-amount uint)
                              (milestone-count uint))
    (begin
        (asserts! (is-valid-title title) ERR_INVALID_TITLE)
        (asserts! (is-valid-description description) ERR_INVALID_DESCRIPTION)
        (asserts! (is-valid-amount total-amount) ERR_INVALID_AMOUNT)
        (asserts! (and (> milestone-count u0) (<= milestone-count u10)) ERR_INVALID_MILESTONE_COUNT)
        
        (let ((proposal-id (+ (var-get proposal-counter) u1)))
            (map-set Proposals
                { proposal-id: proposal-id }
                {
                    proposer: tx-sender,
                    title: title,
                    description: description,
                    total-amount: total-amount,
                    milestone-count: milestone-count,
                    current-milestone: u0,
                    start-block: block-height,
                    end-block: (+ block-height VOTING_PERIOD),
                    status: "ACTIVE",
                    total-votes-for: u0,
                    total-votes-against: u0,
                    total-voting-power: u0
                }
            )
            (var-set proposal-counter proposal-id)
            (ok proposal-id)
        )
    )
)

(define-public (add-milestone (proposal-id uint) 
                            (milestone-id uint)
                            (amount uint)
                            (description (string-ascii 200)))
    (begin
        (asserts! (is-valid-description description) ERR_INVALID_DESCRIPTION)
        (let ((proposal (unwrap! (map-get? Proposals {proposal-id: proposal-id}) ERR_INVALID_PROPOSAL)))
            (asserts! (is-valid-proposal-id proposal-id) ERR_INVALID_PROPOSAL)
            (asserts! (is-valid-amount amount) ERR_INVALID_AMOUNT)
            (asserts! (is-valid-milestone-id milestone-id (get milestone-count proposal)) ERR_MILESTONE_INVALID)
            (asserts! (is-eq (get proposer proposal) tx-sender) ERR_UNAUTHORIZED)
            
            (map-set Milestones
                { proposal-id: proposal-id, milestone-id: milestone-id }
                {
                    amount: amount,
                    description: description,
                    status: "PENDING",
                    completion-proof: none
                }
            )
            (ok true)
        )
    )
)

(define-public (vote (proposal-id uint) (vote-for bool) (stake-amount uint))
    (let (
        (proposal (unwrap! (map-get? Proposals {proposal-id: proposal-id}) ERR_INVALID_PROPOSAL))
        (current-block block-height)
        (voting-power (calculate-voting-power stake-amount))
        (safe-vote (validate-vote-bool vote-for))
    )
        (asserts! (is-valid-proposal-id proposal-id) ERR_INVALID_PROPOSAL)
        (asserts! (>= stake-amount MINIMUM_STAKE_AMOUNT) ERR_INSUFFICIENT_STAKE)
        (asserts! (<= current-block (get end-block proposal)) ERR_VOTING_CLOSED)
        (asserts! (is-none (map-get? Votes {proposal-id: proposal-id, voter: tx-sender})) ERR_ALREADY_VOTED)
        
        (try! (stx-transfer? stake-amount tx-sender (as-contract tx-sender)))
        
        ;; Record vote with validated boolean
        (map-set Votes
            {proposal-id: proposal-id, voter: tx-sender}
            {
                amount: stake-amount,
                vote: safe-vote,
                staked-amount: stake-amount
            }
        )
        
        ;; Process vote and update proposal
        (let (
            (updated-votes (validate-and-process-vote 
                safe-vote
                voting-power
                {
                    total-votes-for: (get total-votes-for proposal),
                    total-votes-against: (get total-votes-against proposal),
                    total-voting-power: (get total-voting-power proposal)
                }
            ))
        )
            (map-set Proposals
                {proposal-id: proposal-id}
                (safe-merge-proposal-votes proposal updated-votes)
            )
            (ok true)
        )
    )
)

(define-public (submit-milestone-proof 
    (proposal-id uint)
    (milestone-id uint)
    (proof (string-ascii 200)))
    
    (let (
        (proposal (unwrap! (map-get? Proposals {proposal-id: proposal-id}) ERR_INVALID_PROPOSAL))
        (milestone (unwrap! (map-get? Milestones {proposal-id: proposal-id, milestone-id: milestone-id}) ERR_MILESTONE_INVALID))
    )
        (asserts! (is-valid-proposal-id proposal-id) ERR_INVALID_PROPOSAL)
        (asserts! (is-valid-milestone-id milestone-id (get milestone-count proposal)) ERR_MILESTONE_INVALID)
        (asserts! (is-eq (get proposer proposal) tx-sender) ERR_UNAUTHORIZED)
        (asserts! (is-eq milestone-id (get current-milestone proposal)) ERR_MILESTONE_INVALID)
        
        (map-set Milestones
            {proposal-id: proposal-id, milestone-id: milestone-id}
            (merge milestone
                {
                    status: "PENDING_REVIEW",
                    completion-proof: (some proof)
                }
            )
        )
        (ok true)
    )
)

(define-public (approve-milestone (proposal-id uint) (milestone-id uint))
    (let (
        (proposal (unwrap! (map-get? Proposals {proposal-id: proposal-id}) ERR_INVALID_PROPOSAL))
        (milestone (unwrap! (map-get? Milestones {proposal-id: proposal-id, milestone-id: milestone-id}) ERR_MILESTONE_INVALID))
    )
        (asserts! (is-valid-proposal-id proposal-id) ERR_INVALID_PROPOSAL)
        (asserts! (is-valid-milestone-id milestone-id (get milestone-count proposal)) ERR_MILESTONE_INVALID)
        (asserts! (is-contract-owner) ERR_UNAUTHORIZED)
        
        ;; Transfer milestone amount to proposer
        (try! (as-contract (stx-transfer? (get amount milestone) tx-sender (get proposer proposal))))
        
        ;; Update milestone status
        (map-set Milestones
            {proposal-id: proposal-id, milestone-id: milestone-id}
            (merge milestone {status: "COMPLETED"})
        )
        
        ;; Update proposal current milestone
        (map-set Proposals
            {proposal-id: proposal-id}
            (merge proposal
                {
                    current-milestone: (+ milestone-id u1),
                    status: (if (>= (+ milestone-id u1) (get milestone-count proposal))
                        "COMPLETED"
                        "ACTIVE"
                    )
                }
            )
        )
        (ok true)
    )
)

;; Read-only functions
(define-read-only (get-proposal (proposal-id uint))
    (map-get? Proposals {proposal-id: proposal-id})
)

(define-read-only (get-milestone (proposal-id uint) (milestone-id uint))
    (map-get? Milestones {proposal-id: proposal-id, milestone-id: milestone-id})
)

(define-read-only (get-vote (proposal-id uint) (voter principal))
    (map-get? Votes {proposal-id: proposal-id, voter: voter})
)

(define-read-only (get-proposal-result (proposal-id uint))
    (let ((proposal (unwrap! (map-get? Proposals {proposal-id: proposal-id}) ERR_INVALID_PROPOSAL)))
        (asserts! (is-valid-proposal-id proposal-id) ERR_INVALID_PROPOSAL)
        (if (>= block-height (get end-block proposal))
            (let (
                (total-votes (get total-voting-power proposal))
                (votes-for (get total-votes-for proposal))
            )
                (if (and
                    (> total-votes u0)
                    (>= (* votes-for u1000) (* total-votes REQUIRED_MAJORITY))
                )
                    (ok "APPROVED")
                    (ok "REJECTED")
                )
            )
            (ok "VOTING_ACTIVE")
        )
    )
)