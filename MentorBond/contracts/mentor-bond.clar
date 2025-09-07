;; MentorBond - Escrow system for mentorship sessions
(define-constant contract-owner tx-sender)
(define-constant err-not-found (err u101))
(define-constant err-unauthorized (err u102))
(define-constant err-session-complete (err u103))
(define-constant err-insufficient-payment (err u104))
(define-constant err-invalid-rating (err u105))
(define-constant err-session-active (err u106))

(define-data-var next-session-id uint u0)
(define-data-var platform-fee-rate uint u50) ;; 5% fee (50/1000)
(define-data-var total-platform-fees uint u0)

(define-map mentorship-sessions
  { session-id: uint }
  {
    mentor: principal,
    student: principal,
    amount: uint,
    platform-fee: uint,
    description: (string-ascii 200),
    subject: (string-ascii 50),
    completed: bool,
    student-confirmed: bool,
    mentor-confirmed: bool,
    disputed: bool,
    created-at: uint,
    expires-at: uint
  }
)

(define-map mentor-profiles
  { mentor: principal }
  {
    hourly-rate: uint,
    total-sessions: uint,
    rating-sum: uint,
    rating-count: uint,
    subjects: (list 10 (string-ascii 50)),
    active: bool,
    bio: (string-ascii 300)
  }
)

(define-map student-profiles
  { student: principal }
  {
    total-sessions: uint,
    total-spent: uint,
    subjects-learned: (list 10 (string-ascii 50))
  }
)

(define-map session-reviews
  { session-id: uint }
  {
    student-review: (string-ascii 200),
    mentor-review: (string-ascii 200),
    rating: uint,
    helpful-votes: uint
  }
)

(define-map dispute-cases
  { session-id: uint }
  {
    raised-by: principal,
    reason: (string-ascii 300),
    resolved: bool,
    resolution: (string-ascii 200)
  }
)

(define-public (register-mentor (hourly-rate uint) (bio (string-ascii 300)) (subjects (list 10 (string-ascii 50))))
  (begin
    (map-set mentor-profiles
      { mentor: tx-sender }
      {
        hourly-rate: hourly-rate,
        total-sessions: u0,
        rating-sum: u0,
        rating-count: u0,
        subjects: subjects,
        active: true,
        bio: bio
      }
    )
    (ok true)
  )
)

(define-public (create-session (mentor principal) (amount uint) (description (string-ascii 200)) (subject (string-ascii 50)) (duration-blocks uint))
  (let (
    (session-id (var-get next-session-id))
    (platform-fee (/ (* amount (var-get platform-fee-rate)) u1000))
    (total-cost (+ amount platform-fee))
  )
    (asserts! (is-some (map-get? mentor-profiles { mentor: mentor })) err-not-found)
    (try! (stx-transfer? total-cost tx-sender (as-contract tx-sender)))
    (map-set mentorship-sessions
      { session-id: session-id }
      {
        mentor: mentor,
        student: tx-sender,
        amount: amount,
        platform-fee: platform-fee,
        description: description,
        subject: subject,
        completed: false,
        student-confirmed: false,
        mentor-confirmed: false,
        disputed: false,
        created-at: stacks-block-height,
        expires-at: (+ stacks-block-height duration-blocks)
      }
    )
    (var-set next-session-id (+ session-id u1))
    (var-set total-platform-fees (+ (var-get total-platform-fees) platform-fee))
    (ok session-id)
  )
)

(define-public (confirm-session (session-id uint))
  (let ((session (unwrap! (map-get? mentorship-sessions { session-id: session-id }) err-not-found)))
    (asserts! (not (get completed session)) err-session-complete)
    (asserts! (not (get disputed session)) err-session-active)
    (asserts! (or (is-eq tx-sender (get student session)) (is-eq tx-sender (get mentor session))) err-unauthorized)
    
    (if (is-eq tx-sender (get student session))
      (map-set mentorship-sessions
        { session-id: session-id }
        (merge session { student-confirmed: true })
      )
      (map-set mentorship-sessions
        { session-id: session-id }
        (merge session { mentor-confirmed: true })
      )
    )
    
    (let ((updated-session (unwrap-panic (map-get? mentorship-sessions { session-id: session-id }))))
      (if (and (get student-confirmed updated-session) (get mentor-confirmed updated-session))
        (begin
          (try! (as-contract (stx-transfer? (get amount updated-session) tx-sender (get mentor updated-session))))
          (map-set mentorship-sessions
            { session-id: session-id }
            (merge updated-session { completed: true })
          )
          (let ((mentor-profile (unwrap-panic (map-get? mentor-profiles { mentor: (get mentor updated-session) }))))
            (map-set mentor-profiles
              { mentor: (get mentor updated-session) }
              (merge mentor-profile { total-sessions: (+ (get total-sessions mentor-profile) u1) })
            )
          )
          (let ((student-profile (default-to { total-sessions: u0, total-spent: u0, subjects-learned: (list) }
                                            (map-get? student-profiles { student: (get student updated-session) }))))
            (map-set student-profiles
              { student: (get student updated-session) }
              (merge student-profile { 
                total-sessions: (+ (get total-sessions student-profile) u1),
                total-spent: (+ (get total-spent student-profile) (get amount updated-session))
              })
            )
          )
        )
        true
      )
    )
    (ok true)
  )
)

(define-public (submit-review (session-id uint) (rating uint) (review (string-ascii 200)))
  (let ((session (unwrap! (map-get? mentorship-sessions { session-id: session-id }) err-not-found)))
    (asserts! (get completed session) err-session-active)
    (asserts! (is-eq tx-sender (get student session)) err-unauthorized)
    (asserts! (and (>= rating u1) (<= rating u5)) err-invalid-rating)
    
    (map-set session-reviews
      { session-id: session-id }
      {
        student-review: review,
        mentor-review: "",
        rating: rating,
        helpful-votes: u0
      }
    )
    
    (let ((mentor-profile (unwrap-panic (map-get? mentor-profiles { mentor: (get mentor session) }))))
      (map-set mentor-profiles
        { mentor: (get mentor session) }
        (merge mentor-profile {
          rating-sum: (+ (get rating-sum mentor-profile) rating),
          rating-count: (+ (get rating-count mentor-profile) u1)
        })
      )
    )
    (ok true)
  )
)

(define-public (raise-dispute (session-id uint) (reason (string-ascii 300)))
  (let ((session (unwrap! (map-get? mentorship-sessions { session-id: session-id }) err-not-found)))
    (asserts! (not (get completed session)) err-session-complete)
    (asserts! (or (is-eq tx-sender (get student session)) (is-eq tx-sender (get mentor session))) err-unauthorized)
    
    (map-set mentorship-sessions
      { session-id: session-id }
      (merge session { disputed: true })
    )
    
    (map-set dispute-cases
      { session-id: session-id }
      {
        raised-by: tx-sender,
        reason: reason,
        resolved: false,
        resolution: ""
      }
    )
    (ok true)
  )
)

(define-public (claim-refund (session-id uint))
  (let ((session (unwrap! (map-get? mentorship-sessions { session-id: session-id }) err-not-found)))
    (asserts! (is-eq tx-sender (get student session)) err-unauthorized)
    (asserts! (> stacks-block-height (get expires-at session)) err-unauthorized)
    (asserts! (not (get completed session)) err-session-complete)
    (asserts! (not (get disputed session)) err-session-active)
    
    (try! (as-contract (stx-transfer? (+ (get amount session) (get platform-fee session)) tx-sender (get student session))))
    (map-set mentorship-sessions
      { session-id: session-id }
      (merge session { completed: true })
    )
    (var-set total-platform-fees (- (var-get total-platform-fees) (get platform-fee session)))
    (ok true)
  )
)

(define-public (resolve-dispute (session-id uint) (favor-student bool) (resolution (string-ascii 200)))
  (let ((session (unwrap! (map-get? mentorship-sessions { session-id: session-id }) err-not-found)))
    (asserts! (is-eq tx-sender contract-owner) err-unauthorized)
    (asserts! (get disputed session) err-not-found)
    
    (if favor-student
      (try! (as-contract (stx-transfer? (+ (get amount session) (get platform-fee session)) tx-sender (get student session))))
      (try! (as-contract (stx-transfer? (get amount session) tx-sender (get mentor session))))
    )
    
    (map-set mentorship-sessions
      { session-id: session-id }
      (merge session { completed: true, disputed: false })
    )
    
    (map-set dispute-cases
      { session-id: session-id }
      (merge (unwrap-panic (map-get? dispute-cases { session-id: session-id }))
             { resolved: true, resolution: resolution })
    )
    (ok true)
  )
)

(define-public (update-mentor-status (active bool))
  (let ((profile (unwrap! (map-get? mentor-profiles { mentor: tx-sender }) err-not-found)))
    (map-set mentor-profiles
      { mentor: tx-sender }
      (merge profile { active: active })
    )
    (ok true)
  )
)

(define-read-only (get-session (session-id uint))
  (map-get? mentorship-sessions { session-id: session-id })
)

(define-read-only (get-mentor-profile (mentor principal))
  (map-get? mentor-profiles { mentor: mentor })
)

(define-read-only (get-student-profile (student principal))
  (map-get? student-profiles { student: student })
)

(define-read-only (get-session-review (session-id uint))
  (map-get? session-reviews { session-id: session-id })
)

(define-read-only (calculate-mentor-rating (mentor principal))
  (let ((profile (map-get? mentor-profiles { mentor: mentor })))
    (if (is-some profile)
      (let ((p (unwrap-panic profile)))
        (if (> (get rating-count p) u0)
          (some (/ (get rating-sum p) (get rating-count p)))
          none
        )
      )
      none
    )
  )
)

(define-read-only (get-platform-stats)
  {
    total-sessions: (var-get next-session-id),
    total-platform-fees: (var-get total-platform-fees),
    platform-fee-rate: (var-get platform-fee-rate)
  }
)