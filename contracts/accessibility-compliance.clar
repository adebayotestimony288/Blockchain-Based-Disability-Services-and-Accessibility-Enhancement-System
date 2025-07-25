;; Accessibility Compliance Monitoring Contract
;; Ensures public spaces and services meet disability access requirements

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-INVALID-INPUT (err u101))
(define-constant ERR-NOT-FOUND (err u102))
(define-constant ERR-ALREADY-EXISTS (err u103))
(define-constant ERR-INSUFFICIENT-FUNDS (err u104))

;; Data Variables
(define-data-var next-location-id uint u1)
(define-data-var next-report-id uint u1)
(define-data-var contract-paused bool false)

;; Data Maps
(define-map locations
  { location-id: uint }
  {
    name: (string-ascii 100),
    address: (string-ascii 200),
    owner: principal,
    compliance-score: uint,
    last-inspection: uint,
    verified: bool,
    created-at: uint
  }
)

(define-map compliance-reports
  { report-id: uint }
  {
    location-id: uint,
    reporter: principal,
    violation-type: (string-ascii 50),
    description: (string-ascii 500),
    severity: uint,
    status: (string-ascii 20),
    created-at: uint,
    resolved-at: (optional uint)
  }
)

(define-map location-inspectors
  { location-id: uint, inspector: principal }
  { authorized: bool, assigned-at: uint }
)

(define-map user-reports-count
  { user: principal }
  { count: uint }
)

;; Public Functions

;; Register a new location for compliance monitoring
(define-public (register-location (name (string-ascii 100)) (address (string-ascii 200)))
  (let
    (
      (location-id (var-get next-location-id))
    )
    (asserts! (not (var-get contract-paused)) ERR-NOT-AUTHORIZED)
    (asserts! (> (len name) u0) ERR-INVALID-INPUT)
    (asserts! (> (len address) u0) ERR-INVALID-INPUT)

    (map-set locations
      { location-id: location-id }
      {
        name: name,
        address: address,
        owner: tx-sender,
        compliance-score: u50,
        last-inspection: u0,
        verified: false,
        created-at: block-height
      }
    )

    (var-set next-location-id (+ location-id u1))
    (ok location-id)
  )
)

;; Submit a compliance report
(define-public (submit-report
  (location-id uint)
  (violation-type (string-ascii 50))
  (description (string-ascii 500))
  (severity uint))
  (let
    (
      (report-id (var-get next-report-id))
      (location (unwrap! (map-get? locations { location-id: location-id }) ERR-NOT-FOUND))
      (current-count (default-to u0 (get count (map-get? user-reports-count { user: tx-sender }))))
    )
    (asserts! (not (var-get contract-paused)) ERR-NOT-AUTHORIZED)
    (asserts! (> (len violation-type) u0) ERR-INVALID-INPUT)
    (asserts! (> (len description) u0) ERR-INVALID-INPUT)
    (asserts! (and (>= severity u1) (<= severity u5)) ERR-INVALID-INPUT)

    (map-set compliance-reports
      { report-id: report-id }
      {
        location-id: location-id,
        reporter: tx-sender,
        violation-type: violation-type,
        description: description,
        severity: severity,
        status: "pending",
        created-at: block-height,
        resolved-at: none
      }
    )

    (map-set user-reports-count
      { user: tx-sender }
      { count: (+ current-count u1) }
    )

    (var-set next-report-id (+ report-id u1))
    (ok report-id)
  )
)

;; Update compliance score after inspection
(define-public (update-compliance-score (location-id uint) (new-score uint))
  (let
    (
      (location (unwrap! (map-get? locations { location-id: location-id }) ERR-NOT-FOUND))
      (inspector-auth (map-get? location-inspectors { location-id: location-id, inspector: tx-sender }))
    )
    (asserts! (not (var-get contract-paused)) ERR-NOT-AUTHORIZED)
    (asserts! (<= new-score u100) ERR-INVALID-INPUT)
    (asserts! (or
      (is-eq tx-sender (get owner location))
      (and (is-some inspector-auth) (get authorized (unwrap-panic inspector-auth)))
      (is-eq tx-sender CONTRACT-OWNER)
    ) ERR-NOT-AUTHORIZED)

    (map-set locations
      { location-id: location-id }
      (merge location {
        compliance-score: new-score,
        last-inspection: block-height
      })
    )

    (ok true)
  )
)

;; Resolve a compliance report
(define-public (resolve-report (report-id uint))
  (let
    (
      (report (unwrap! (map-get? compliance-reports { report-id: report-id }) ERR-NOT-FOUND))
      (location (unwrap! (map-get? locations { location-id: (get location-id report) }) ERR-NOT-FOUND))
    )
    (asserts! (not (var-get contract-paused)) ERR-NOT-AUTHORIZED)
    (asserts! (or
      (is-eq tx-sender (get owner location))
      (is-eq tx-sender CONTRACT-OWNER)
    ) ERR-NOT-AUTHORIZED)
    (asserts! (is-eq (get status report) "pending") ERR-INVALID-INPUT)

    (map-set compliance-reports
      { report-id: report-id }
      (merge report {
        status: "resolved",
        resolved-at: (some block-height)
      })
    )

    (ok true)
  )
)

;; Authorize inspector for a location
(define-public (authorize-inspector (location-id uint) (inspector principal))
  (let
    (
      (location (unwrap! (map-get? locations { location-id: location-id }) ERR-NOT-FOUND))
    )
    (asserts! (not (var-get contract-paused)) ERR-NOT-AUTHORIZED)
    (asserts! (or
      (is-eq tx-sender (get owner location))
      (is-eq tx-sender CONTRACT-OWNER)
    ) ERR-NOT-AUTHORIZED)

    (map-set location-inspectors
      { location-id: location-id, inspector: inspector }
      { authorized: true, assigned-at: block-height }
    )

    (ok true)
  )
)

;; Verify location compliance
(define-public (verify-location (location-id uint))
  (let
    (
      (location (unwrap! (map-get? locations { location-id: location-id }) ERR-NOT-FOUND))
    )
    (asserts! (not (var-get contract-paused)) ERR-NOT-AUTHORIZED)
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (asserts! (>= (get compliance-score location) u80) ERR-INVALID-INPUT)

    (map-set locations
      { location-id: location-id }
      (merge location { verified: true })
    )

    (ok true)
  )
)

;; Read-only Functions

(define-read-only (get-location (location-id uint))
  (map-get? locations { location-id: location-id })
)

(define-read-only (get-report (report-id uint))
  (map-get? compliance-reports { report-id: report-id })
)

(define-read-only (get-user-report-count (user principal))
  (default-to u0 (get count (map-get? user-reports-count { user: user })))
)

(define-read-only (is-inspector-authorized (location-id uint) (inspector principal))
  (default-to false (get authorized (map-get? location-inspectors { location-id: location-id, inspector: inspector })))
)

(define-read-only (get-next-location-id)
  (var-get next-location-id)
)

(define-read-only (get-next-report-id)
  (var-get next-report-id)
)

;; Admin Functions

(define-public (pause-contract)
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (var-set contract-paused true)
    (ok true)
  )
)

(define-public (unpause-contract)
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (var-set contract-paused false)
    (ok true)
  )
)
