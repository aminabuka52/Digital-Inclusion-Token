# Includa - Digital Inclusion Token

A Clarity smart contract that incentivizes first-time smartphone and web usage through a token reward system.

## Overview

Includa rewards users for digital milestones, encouraging digital literacy and inclusion. Users earn INCL tokens for verification, completing milestones, daily engagement, and referring others.

## Features

- **User Verification**: First-time users get rewarded for initial verification
- **Milestone System**: Earn tokens for reaching digital literacy milestones (1-10)
- **Referral Program**: Bonus rewards for both referrer and new user
- **Daily Engagement**: Daily token rewards for active participation
- **Admin Controls**: Contract management and emergency functions

## Token Details

- **Name**: Includa
- **Symbol**: INCL
- **Decimals**: 6
- **Max Supply**: 1,000,000 INCL tokens
- **Standard**: SIP-010 Fungible Token

## Reward Structure

- **Verification Reward**: 100 INCL tokens
- **Milestone Reward**: 50 INCL tokens per milestone
- **Referral Reward**: 25 INCL tokens for referrer
- **Daily Engagement**: 10 INCL tokens
- **Cooldown Period**: 144 blocks (~24 hours)

## Usage

### For New Users

```clarity
;; Verify as a new user (first-time smartphone/web user)
(contract-call? .includa verify-new-user)

;; Verify with a referral
(contract-call? .includa verify-with-referral 'SP1REFERRER...)
```

### For Verified Users

```clarity
;; Claim milestone reward (milestones 1-10)
(contract-call? .includa claim-milestone-reward u2)

;; Claim daily engagement reward
(contract-call? .includa daily-engagement-reward)

;; Transfer tokens
(contract-call? .includa transfer u100000000 tx-sender 'SP1RECIPIENT... none)
```

### Read-Only Functions

```clarity
;; Check verification status
(contract-call? .includa is-verified 'SP1USER...)

;; Get user's milestone progress
(contract-call? .includa get-user-milestones 'SP1USER...)

;; Check token balance
(contract-call? .includa get-balance 'SP1USER...)

;; Get referral count
(contract-call? .includa get-referral-count 'SP1USER...)

;; Check cooldown remaining
(contract-call? .includa get-cooldown-remaining 'SP1USER...)
```

## Admin Functions

Only contract owner and designated admins can execute:

```clarity
;; Adjust reward amounts
(contract-call? .includa set-verification-reward u150000000)
(contract-call? .includa set-milestone-reward u75000000)
(contract-call? .includa set-referral-reward u30000000)

;; Contract controls
(contract-call? .includa toggle-contract true)
(contract-call? .includa set-max-supply u2000000000000)

;; Admin management
(contract-call? .includa add-admin 'SP1NEWADMIN...)
(contract-call? .includa remove-admin 'SP1OLDADMIN...)

;; Bulk operations
(contract-call? .includa bulk-verify-users (list 'SP1USER1... 'SP1USER2...))

;; Emergency functions
(contract-call? .includa emergency-mint 'SP1RECIPIENT... u1000000000)
```

## Error Codes

- `u100`: Owner only operation
- `u101`: Not token owner
- `u102`: Insufficient balance
- `u103`: Already verified
- `u104`: Not verified
- `u105`: Invalid amount
- `u106`: Cooldown active
- `u107`: Max supply reached
- `u108`: Invalid milestone

## Development

### Prerequisites

- [Clarinet](https://github.com/hirosystems/clarinet)
- Node.js and npm

### Setup

```bash
git clone <repository-url>
cd includa
clarinet check
```

### Testing

```bash
clarinet test
```

### Deployment

```bash
clarinet deploy --testnet
```

## Security Considerations

- Only verified users can claim milestone and daily rewards
- Cooldown periods prevent spam
- Max supply caps prevent inflation
- Admin functions are restricted to authorized principals
- Referral system prevents self-referrals

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests
5. Submit a pull request

## License

MIT License - see LICENSE file for details
