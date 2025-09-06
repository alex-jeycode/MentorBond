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

;; Create mentorship session
(define-public (create-session (mentor principal) (amount uint) (description (string-ascii 200)) (duration-blocks uint))
  (let ((session-id (var-get next-session-id)))
    (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
    (map-set mentorship-sessions
      { session-id: session-id }
      {
        mentor: mentor,
        student: tx-sender,
        amount: amount,
        description: description,
        completed: false,
        student-confirmed: false,
        mentor-confirmed: false,
        created-at: block-height,
        expires-at: (+ block-height duration-blocks),
        cancelled: false
      }
    )
    (var-set next-session-id (+ session-id u1))
    (ok session-id)
  )
)

;; Confirm session completion with rating
(define-public (confirm-session (session-id uint) (rating uint))
  (let ((session (unwrap! (map-get? mentorship-sessions { session-id: session-id }) err-not-found)))
    (asserts! (not (get completed session)) err-session-complete)
    (asserts! (not (get cancelled session)) err-session-active)
    (asserts! (or (is-eq tx-sender (get student session)) (is-eq tx-sender (get mentor session))) err-unauthorized)
    
    (if (is-eq tx-sender (get student session))
      (begin
        (map-set mentorship-sessions
          { session-id: session-id }
          (merge session { student-confirmed: true })
        )
        (if (and (is-some rating) (<= (unwrap-panic rating) u5) (>= (unwrap-panic rating) u1))
          (try! (update-mentor-rating (get mentor session) (unwrap-panic rating)))
          true
        )
      )
      (map-set mentorship-sessions
        { session-id: session-id }
        (merge session { mentor-confirmed: true })
      )
    )
    
    (let ((updated-session (unwrap-panic (map-get? mentorship-sessions { session-id: session-id }))))
      (if (and (get student-confirmed updated-session) (get mentor-confirmed updated-session))
        (try! (complete-session session-id))
        true
      )
    )
    (ok true)
  )
)

;; Complete session and transfer funds
(define-private (complete-session (session-id uint))
  (let ((session (unwrap-panic (map-get? mentorship-sessions { session-id: session-id })))
        (fee (/ (* (get amount session) (var-get platform-fee-percent)) u100))
        (mentor-payout (- (get amount session) fee)))
    (try! (as-contract (stx-transfer? mentor-payout tx-sender (get mentor session))))
    (try! (as-contract (stx-transfer? fee tx-sender contract-owner)))
    (map-set mentorship-sessions
      { session-id: session-id }
      (merge session { completed: true })
    )
    (try! (update-mentor-session-count (get mentor session)))
    (try! (update-student-stats (get student session) (get amount session)))
    (ok true)
  )
)

;; Cancel session (only before confirmation)
(define-public (cancel-session (session-id uint))
  (let ((session (unwrap! (map-get? mentorship-sessions { session-id: session-id }) err-not-found)))
    (asserts! (or (is-eq tx-sender (get student session)) (is-eq tx-sender (get mentor session))) err-unauthorized)
    (asserts! (not (get completed session)) err-session-complete)
    (asserts! (not (or (get student-confirmed session) (get mentor-confirmed session))) err-session-active)
    
    (try! (as-contract (stx-transfer? (get amount session) tx-sender (get student session))))
    (map-set mentorship-sessions
      { session-id: session-id }
      (merge session { cancelled: true })
    )
    (ok true)
  )
)

;; Claim refund for expired sessions
(define-public (claim-refund (session-id uint))
  (let ((session (unwrap! (map-get? mentorship-sessions { session-id: session-id }) err-not-found)))
    (asserts! (is-eq tx-sender (get student session)) err-unauthorized)
    (asserts! (> block-height (get expires-at session)) err-unauthorized)
    (asserts! (not (get completed session)) err-session-complete)
    (asserts! (not (get cancelled session)) err-session-active)
    
    (try! (as-contract (stx-transfer? (get amount session) tx-sender (get student session))))
    (map-set mentorship-sessions
      { session-id: session-id }
      (merge session { completed: true })
    )
    (ok true)
  )
)

;; Update mentor rating
(define-private (update-mentor-rating (mentor principal) (rating uint))
  (let ((mentor-profile (default-to { hourly-rate: u0, total-sessions: u0, rating-sum: u0, rating-count: u0, is-active: false, bio: "" }
                                   (map-get? mentor-profiles { mentor: mentor }))))
    (map-set mentor-profiles
      { mentor: mentor }
      (merge mentor-profile {
        rating-sum: (+ (get rating-sum mentor-profile) rating),
        rating-count: (+ (get rating-count mentor-profile) u1)
      })
    )
    (ok true)
  )
)

;; Update mentor session count
(define-private (update-mentor-session-count (mentor principal))
  (let ((mentor-profile (default-to { hourly-rate: u0, total-sessions: u0, rating-sum: u0, rating-count: u0, is-active: false, bio: "" }
                                   (map-get? mentor-profiles { mentor: mentor }))))
    (map-set mentor-profiles
      { mentor: mentor }
      (merge mentor-profile { total-sessions: (+ (get total-sessions mentor-profile) u1) })
    )
    (ok true)
  )
)

;; Update student statistics
(define-private (update-student-stats (student principal) (amount uint))
  (let ((student-profile (default-to { total-sessions: u0, total-spent: u0 }
                                    (map-get? student-profiles { student: student }))))
    (map-set student-profiles
      { student: student }
      {
        total-sessions: (+ (get total-sessions student-profile) u1),
        total-spent: (+ (get total-spent student-profile) amount)
      }
    )
    (ok true)
  )
)

;; Register as mentor
(define-public (register-mentor (hourly-rate uint) (bio (string-ascii 500)))
  (map-set mentor-profiles
    { mentor: tx-sender }
    {
      hourly-rate: hourly-rate,
      total-sessions: u0,
      rating-sum: u0,
      rating-count: u0,
      is-active: true,
      bio: bio
    }
  )
  (ok true)
)

;; Update mentor profile
(define-public (update-mentor-profile (hourly-rate uint) (bio (string-ascii 500)) (is-active bool))
  (let ((existing-profile (unwrap! (map-get? mentor-profiles { mentor: tx-sender }) err-not-found)))
    (map-set mentor-profiles
      { mentor: tx-sender }
      (merge existing-profile {
        hourly-rate: hourly-rate,
        bio: bio,
        is-active: is-active
      })
    )
    (ok true)
  )
)