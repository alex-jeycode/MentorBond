# MentorBond

An escrow-based mentorship platform where payments are held in smart contracts and released when both mentor and student confirm session completion.

## Features

- **Escrow Payments**: Secure payment holding until session confirmation
- **Dual Confirmation**: Both parties must confirm session completion
- **Mentor Ratings**: Students can rate mentors (1-5 scale)
- **Automatic Refunds**: Students can claim refunds if sessions expire unconfirmed

## Contract Functions

### Public Functions
- `create-session(mentor, amount, description, duration-blocks)` - Create and fund a mentorship session
- `confirm-session(session-id, rating)` - Confirm session completion (both parties)
- `claim-refund(session-id)` - Claim refund for expired sessions

### Read-Only Functions
- `get-session(session-id)` - Get session details
- `get-mentor-profile(mentor)` - Get mentor's profile and statistics
- `calculate-mentor-rating(mentor)` - Get mentor's average rating

## Usage

1. Student creates session with escrowed payment
2. Mentor and student conduct mentorship session
3. Both parties confirm completion
4. Payment automatically releases to mentor
5. Optional: Student provides rating for mentor