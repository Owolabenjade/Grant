;; Decentralized Grant Proposal System (DGP)
;; A system for managing grant proposals with milestone-based funding

;; Constants
(define-constant CONTRACT_OWNER tx-sender)
(define-constant MINIMUM_STAKE_AMOUNT u100)
(define-constant VOTING_PERIOD u1344) ;; ~14 days in blocks (assuming 10 min/block)
(define-constant REQUIRED_MAJORITY u500) ;; 50.0% represented as 500/1000

;; Error codes
(define-constant ERR_UNAUTHORIZED (err u100))
(define-constant ERR_INVALID_PROPOSAL (err u101))
(define-constant ERR_ALREADY_VOTED (err u102))
(define-constant ERR_INSUFFICIENT_STAKE (err u103))
(define-constant ERR_VOTING_CLOSED (err u104))
(define-constant ERR_MILESTONE_INVALID (err u105))
(define-constant ERR_PROPOSAL_NOT_APPROVED (err u106))

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
    ;; Simple 1:1 ratio for voting power to staked amount
    stake-amount
)

;; Public functions
(define-public (submit-proposal (title (string-ascii 100)) 
                              (description (string-ascii 500)) 
                              (total-amount uint)
                              (milestone-count uint))
    (let ((proposal-id (+ (var-get proposal-counter) u1)))
        (if (> milestone-count u0)
            (begin
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
            ERR_INVALID_PROPOSAL
        )
    )
)

(define-public (add-milestone (proposal-id uint) 
                            (milestone-id uint)
                            (amount uint)
                            (description (string-ascii 200)))
    (let ((proposal (unwrap! (map-get? Proposals {proposal-id: proposal-id}) ERR_INVALID_PROPOSAL)))
        (if (and
                (is-eq (get proposer proposal) tx-sender)
                (< milestone-id (get milestone-count proposal))
            )
            (begin
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
            ERR_UNAUTHORIZED
        )
    )
)

(define-public (vote (proposal-id uint) (vote-for bool) (stake-amount uint))
    (let (
        (proposal (unwrap! (map-get? Proposals {proposal-id: proposal-id}) ERR_INVALID_PROPOSAL))
        (current-block block-height)
    )
        (asserts! (>= stake-amount MINIMUM_STAKE_AMOUNT) ERR_INSUFFICIENT_STAKE)
        (asserts! (<= current-block (get end-block proposal)) ERR_VOTING_CLOSED)
        (asserts! (is-none (map-get? Votes {proposal-id: proposal-id, voter: tx-sender})) ERR_ALREADY_VOTED)
        
        (let ((voting-power (calculate-voting-power stake-amount)))
            (try! (stx-transfer? stake-amount tx-sender (as-contract tx-sender)))
            
            (map-set Votes
                {proposal-id: proposal-id, voter: tx-sender}
                {
                    amount: stake-amount,
                    vote: vote-for,
                    staked-amount: stake-amount
                }
            )
            
            (map-set Proposals
                {proposal-id: proposal-id}
                (merge proposal
                    {
                        total-votes-for: (if vote-for 
                            (+ (get total-votes-for proposal) voting-power)
                            (get total-votes-for proposal)
                        ),
                        total-votes-against: (if vote-for
                            (get total-votes-against proposal)
                            (+ (get total-votes-against proposal) voting-power)
                        ),
                        total-voting-power: (+ (get total-voting-power proposal) voting-power)
                    }
                )
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