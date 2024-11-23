# Decentralized Grant Proposal System (DGP)

The Decentralized Grant Proposal System (DGP) is a Clarity smart contract that enables transparent, milestone-based funding for community projects. It implements a comprehensive system for submitting, voting on, and managing grant proposals with built-in security features and automated fund distribution.

## Features
- **Proposal Management**: Submit and track grant proposals with detailed specifications
- **Milestone-Based Funding**: Break down projects into verifiable milestones
- **Secure Voting System**: Stake-based voting mechanism to prevent spam
- **Automated Fund Distribution**: Milestone-based fund release with proof requirements
- **Transparent Tracking**: Public verification of project progress and fund utilization

## Contract Architecture

### Data Structures
1. **Proposals Map**
   - Stores core proposal information
   - Tracks voting status and milestone progress
   - Maintains vote tallies and proposal status

2. **Milestones Map**
   - Manages milestone-specific information
   - Tracks completion status and proof submissions
   - Controls fund distribution requirements

3. **Votes Map**
   - Records individual voter participation
   - Tracks stake amounts and voting decisions
   - Prevents double voting

### Core Functions

#### Proposal Management
```clarity
(define-public (submit-proposal (title (string-ascii 100)) 
                              (description (string-ascii 500)) 
                              (total-amount uint)
                              (milestone-count uint)))
```
- Creates new grant proposals
- Validates input parameters
- Initializes voting period

#### Milestone Management
```clarity
(define-public (add-milestone (proposal-id uint) 
                            (milestone-id uint)
                            (amount uint)
                            (description (string-ascii 200))))
```
- Adds milestone details to proposals
- Validates milestone parameters
- Sets up funding checkpoints

#### Voting System
```clarity
(define-public (vote (proposal-id uint) (vote-for bool) (stake-amount uint)))
```
- Handles stake-based voting
- Processes vote weights
- Updates proposal status

#### Milestone Completion
```clarity
(define-public (submit-milestone-proof (proposal-id uint)
                                     (milestone-id uint)
                                     (proof (string-ascii 200))))
```
- Submits completion evidence
- Triggers review process
- Enables fund release

## Usage Guide

### 1. Submitting a Proposal
```clarity
;; Example: Submit a new proposal
(contract-call? .dgp submit-proposal 
    "Eco-Tech Innovation" 
    "Development of sustainable technology solutions" 
    u100000 
    u3)
```

### 2. Adding Milestones
```clarity
;; Example: Add a milestone to proposal #1
(contract-call? .dgp add-milestone 
    u1 
    u0 
    u30000 
    "Complete prototype development")
```

### 3. Voting on Proposals
```clarity
;; Example: Vote on proposal #1 with 100 STX stake
(contract-call? .dgp vote 
    u1 
    true 
    u100)
```

### 4. Submitting Milestone Proof
```clarity
;; Example: Submit proof for milestone completion
(contract-call? .dgp submit-milestone-proof 
    u1 
    u0 
    "https://evidence-link.com/proof")
```

## Security Features
1. **Input Validation**
   - String length requirements
   - Amount range checks
   - Proposal ID validation

2. **Access Controls**
   - Owner-only functions
   - Proposer-specific actions
   - Vote manipulation prevention

3. **Fund Safety**
   - Milestone-based release
   - Proof requirements
   - Stake protection

4. **Vote Protection**
   - Minimum stake requirements
   - Single vote per address
   - Time-locked voting periods

## Constants & Configuration
- `MINIMUM_STAKE_AMOUNT`: 100 STX
- `VOTING_PERIOD`: 14 days (1344 blocks)
- `REQUIRED_MAJORITY`: 50% (500/1000)
- `MAX_AMOUNT`: 1,000,000,000 STX
- `MIN_TITLE_LENGTH`: 4 characters
- `MIN_DESCRIPTION_LENGTH`: 10 characters

## Error Handling
The contract includes comprehensive error handling with specific error codes for different scenarios:
- `ERR_UNAUTHORIZED`: Access control violations
- `ERR_INVALID_PROPOSAL`: Invalid proposal operations
- `ERR_ALREADY_VOTED`: Double voting attempts
- `ERR_INSUFFICIENT_STAKE`: Stake requirement not met
- And more...

## Getting Started
1. Deploy the contract to the Stacks blockchain
2. Initialize with appropriate parameters
3. Begin accepting proposals and votes
4. Monitor milestone progress and fund distribution

## Development and Testing
Recommended to test thoroughly using Clarinet:
```bash
clarinet test
clarinet check
```