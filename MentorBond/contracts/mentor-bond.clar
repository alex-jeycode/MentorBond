;; MentorBond - Enhanced Escrow system for mentorship sessions
(define-constant contract-owner tx-sender)
(define-constant err-not-found (err u101))
(define-constant err-unauthorized (err u102))
(define-constant err-session-complete (err u103))
(define-constant err-insufficient-payment (err u104))
(define-constant err-invalid-rating (err u105))
(define-constant err-session-active (err u106))

(define-data-var next-session-id uint u0)
(define-data-var platform-fee-percent uint u5) ;; 5% platform fee

(define-map mentorship-sessions
  { session-id: uint }
  {
    mentor: principal,
    student: principal,
    amount: uint,
    description: (string-ascii 200),
    completed: bool,
    student-confirmed: bool,
    mentor-confirmed: bool,
    created-at: uint,
    expires-at: uint,
    cancelled: bool
  }
)

(define-map mentor-profiles
  { mentor: principal }
  {
    hourly-rate: uint,
    total-sessions: uint,
    rating-sum: uint,
    rating-count: uint,
    is-active: bool,
    bio: (string-ascii 500)
  }
)

(define-map student-profiles
  { student: principal }
  {
    total-sessions: uint,
    total-spent: uint
  }
)

(define-map session-disputes
  { session-id: uint }
  {
    disputed-by: principal,
    reason: (string-ascii 200),
    resolved: bool,
    created-at: uint
  }
)