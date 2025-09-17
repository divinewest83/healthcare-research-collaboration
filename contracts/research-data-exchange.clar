;; Healthcare Research Data Exchange Contract
;; Manages anonymized medical data sharing between research institutions
;; Handles patient consent tracking, data quality verification, and audit logging

;; Error constants
(define-constant ERR-UNAUTHORIZED (err u100))
(define-constant ERR-NOT-FOUND (err u101))
(define-constant ERR-ALREADY-EXISTS (err u102))
(define-constant ERR-INVALID-DATA (err u103))
(define-constant ERR-CONSENT-REQUIRED (err u104))
(define-constant ERR-DATA-EXPIRED (err u105))
(define-constant ERR-INSUFFICIENT-QUALITY (err u106))

;; Contract deployer as admin
(define-constant CONTRACT-ADMIN tx-sender)

;; Data structures for research institutions
(define-map research-institutions
    { institution-id: uint }
    {
        name: (string-ascii 100),
        address: principal,
        verification-status: bool,
        registration-date: uint,
        data-access-level: uint,
        compliance-score: uint
    }
)

;; Data sharing agreements between institutions
(define-map data-agreements
    { agreement-id: uint }
    {
        provider-id: uint,
        receiver-id: uint,
        data-type: (string-ascii 50),
        start-date: uint,
        end-date: uint,
        consent-required: bool,
        quality-threshold: uint,
        is-active: bool
    }
)

;; Patient consent records for data usage
(define-map patient-consents
    { patient-hash: (buff 32), institution-id: uint }
    {
        consent-given: bool,
        consent-date: uint,
        expiry-date: uint,
        data-types-allowed: (list 10 (string-ascii 50)),
        withdrawal-date: (optional uint),
        consent-version: uint
    }
)

;; Anonymized research datasets
(define-map research-datasets
    { dataset-id: uint }
    {
        provider-institution: uint,
        data-type: (string-ascii 50),
        anonymization-level: uint,
        quality-score: uint,
        creation-date: uint,
        patient-count: uint,
        data-hash: (buff 32),
        access-count: uint,
        is-verified: bool
    }
)

;; Data access logs for compliance and auditing
(define-map data-access-logs
    { access-id: uint }
    {
        dataset-id: uint,
        requesting-institution: uint,
        access-date: uint,
        purpose: (string-ascii 100),
        researcher-id: principal,
        approval-status: bool,
        audit-trail: (buff 32)
    }
)

;; Quality verification records
(define-map quality-verifications
    { verification-id: uint }
    {
        dataset-id: uint,
        verifier-institution: uint,
        verification-date: uint,
        quality-metrics: (list 5 uint),
        passed-verification: bool,
        notes: (string-ascii 200),
        verifier-signature: (buff 64)
    }
)

;; Global counters for unique IDs
(define-data-var institution-counter uint u0)
(define-data-var agreement-counter uint u0)
(define-data-var dataset-counter uint u0)
(define-data-var access-counter uint u0)
(define-data-var verification-counter uint u0)

;; Institution registration and management
(define-public (register-institution 
    (name (string-ascii 100))
    (institution-address principal)
    (access-level uint))
    (let 
        (
            (new-id (+ (var-get institution-counter) u1))
        )
        (asserts! (is-eq tx-sender CONTRACT-ADMIN) ERR-UNAUTHORIZED)
        (asserts! (is-none (map-get? research-institutions { institution-id: new-id })) ERR-ALREADY-EXISTS)
        
        (map-set research-institutions 
            { institution-id: new-id }
            {
                name: name,
                address: institution-address,
                verification-status: false,
                registration-date: block-height,
                data-access-level: access-level,
                compliance-score: u0
            }
        )
        (var-set institution-counter new-id)
        (ok new-id)
    )
)

;; Verify institution for data access
(define-public (verify-institution (institution-id uint))
    (let 
        (
            (institution (unwrap! (map-get? research-institutions { institution-id: institution-id }) ERR-NOT-FOUND))
        )
        (asserts! (is-eq tx-sender CONTRACT-ADMIN) ERR-UNAUTHORIZED)
        
        (map-set research-institutions 
            { institution-id: institution-id }
            (merge institution { verification-status: true, compliance-score: u100 })
        )
        (ok true)
    )
)

;; Create data sharing agreement
(define-public (create-data-agreement
    (provider-id uint)
    (receiver-id uint)
    (data-type (string-ascii 50))
    (duration uint)
    (quality-threshold uint))
    (let 
        (
            (new-id (+ (var-get agreement-counter) u1))
            (provider (unwrap! (map-get? research-institutions { institution-id: provider-id }) ERR-NOT-FOUND))
            (receiver (unwrap! (map-get? research-institutions { institution-id: receiver-id }) ERR-NOT-FOUND))
        )
        (asserts! (get verification-status provider) ERR-UNAUTHORIZED)
        (asserts! (get verification-status receiver) ERR-UNAUTHORIZED)
        
        (map-set data-agreements 
            { agreement-id: new-id }
            {
                provider-id: provider-id,
                receiver-id: receiver-id,
                data-type: data-type,
                start-date: block-height,
                end-date: (+ block-height duration),
                consent-required: true,
                quality-threshold: quality-threshold,
                is-active: true
            }
        )
        (var-set agreement-counter new-id)
        (ok new-id)
    )
)

;; Register patient consent
(define-public (register-patient-consent
    (patient-hash (buff 32))
    (institution-id uint)
    (expiry-duration uint)
    (allowed-data-types (list 10 (string-ascii 50))))
    (let 
        (
            (institution (unwrap! (map-get? research-institutions { institution-id: institution-id }) ERR-NOT-FOUND))
        )
        (asserts! (get verification-status institution) ERR-UNAUTHORIZED)
        
        (map-set patient-consents 
            { patient-hash: patient-hash, institution-id: institution-id }
            {
                consent-given: true,
                consent-date: block-height,
                expiry-date: (+ block-height expiry-duration),
                data-types-allowed: allowed-data-types,
                withdrawal-date: none,
                consent-version: u1
            }
        )
        (ok true)
    )
)

;; Submit research dataset
(define-public (submit-dataset
    (provider-institution uint)
    (data-type (string-ascii 50))
    (anonymization-level uint)
    (patient-count uint)
    (data-hash (buff 32)))
    (let 
        (
            (new-id (+ (var-get dataset-counter) u1))
            (institution (unwrap! (map-get? research-institutions { institution-id: provider-institution }) ERR-NOT-FOUND))
        )
        (asserts! (is-eq tx-sender (get address institution)) ERR-UNAUTHORIZED)
        (asserts! (get verification-status institution) ERR-UNAUTHORIZED)
        (asserts! (>= anonymization-level u3) ERR-INVALID-DATA)
        
        (map-set research-datasets 
            { dataset-id: new-id }
            {
                provider-institution: provider-institution,
                data-type: data-type,
                anonymization-level: anonymization-level,
                quality-score: u0,
                creation-date: block-height,
                patient-count: patient-count,
                data-hash: data-hash,
                access-count: u0,
                is-verified: false
            }
        )
        (var-set dataset-counter new-id)
        (ok new-id)
    )
)

;; Verify dataset quality
(define-public (verify-dataset-quality
    (dataset-id uint)
    (verifier-institution uint)
    (quality-metrics (list 5 uint))
    (notes (string-ascii 200))
    (signature (buff 64)))
    (let 
        (
            (new-verification-id (+ (var-get verification-counter) u1))
            (dataset (unwrap! (map-get? research-datasets { dataset-id: dataset-id }) ERR-NOT-FOUND))
            (verifier (unwrap! (map-get? research-institutions { institution-id: verifier-institution }) ERR-NOT-FOUND))
            (quality-avg (/ (fold + quality-metrics u0) u5))
        )
        (asserts! (is-eq tx-sender (get address verifier)) ERR-UNAUTHORIZED)
        (asserts! (get verification-status verifier) ERR-UNAUTHORIZED)
        
        (map-set quality-verifications 
            { verification-id: new-verification-id }
            {
                dataset-id: dataset-id,
                verifier-institution: verifier-institution,
                verification-date: block-height,
                quality-metrics: quality-metrics,
                passed-verification: (>= quality-avg u70),
                notes: notes,
                verifier-signature: signature
            }
        )
        
        (map-set research-datasets 
            { dataset-id: dataset-id }
            (merge dataset { 
                quality-score: quality-avg,
                is-verified: (>= quality-avg u70)
            })
        )
        (var-set verification-counter new-verification-id)
        (ok (>= quality-avg u70))
    )
)

;; Request data access
(define-public (request-data-access
    (dataset-id uint)
    (requesting-institution uint)
    (purpose (string-ascii 100))
    (researcher-id principal))
    (let 
        (
            (new-access-id (+ (var-get access-counter) u1))
            (dataset (unwrap! (map-get? research-datasets { dataset-id: dataset-id }) ERR-NOT-FOUND))
            (requester (unwrap! (map-get? research-institutions { institution-id: requesting-institution }) ERR-NOT-FOUND))
        )
        (asserts! (is-eq tx-sender (get address requester)) ERR-UNAUTHORIZED)
        (asserts! (get verification-status requester) ERR-UNAUTHORIZED)
        (asserts! (get is-verified dataset) ERR-INSUFFICIENT-QUALITY)
        
        (map-set data-access-logs 
            { access-id: new-access-id }
            {
                dataset-id: dataset-id,
                requesting-institution: requesting-institution,
                access-date: block-height,
                purpose: purpose,
                researcher-id: researcher-id,
                approval-status: true,
                audit-trail: (sha256 (concat (get data-hash dataset) (unwrap-panic (to-consensus-buff? purpose))))
            }
        )
        
        (map-set research-datasets 
            { dataset-id: dataset-id }
            (merge dataset { access-count: (+ (get access-count dataset) u1) })
        )
        (var-set access-counter new-access-id)
        (ok new-access-id)
    )
)

;; Withdraw patient consent
(define-public (withdraw-consent
    (patient-hash (buff 32))
    (institution-id uint))
    (let 
        (
            (consent (unwrap! (map-get? patient-consents { patient-hash: patient-hash, institution-id: institution-id }) ERR-NOT-FOUND))
        )
        (asserts! (get consent-given consent) ERR-NOT-FOUND)
        
        (map-set patient-consents 
            { patient-hash: patient-hash, institution-id: institution-id }
            (merge consent { 
                consent-given: false,
                withdrawal-date: (some block-height)
            })
        )
        (ok true)
    )
)

;; Read-only functions for data retrieval
(define-read-only (get-institution (institution-id uint))
    (map-get? research-institutions { institution-id: institution-id })
)

(define-read-only (get-dataset (dataset-id uint))
    (map-get? research-datasets { dataset-id: dataset-id })
)

(define-read-only (get-access-log (access-id uint))
    (map-get? data-access-logs { access-id: access-id })
)

(define-read-only (get-consent-status (patient-hash (buff 32)) (institution-id uint))
    (map-get? patient-consents { patient-hash: patient-hash, institution-id: institution-id })
)

(define-read-only (get-agreement (agreement-id uint))
    (map-get? data-agreements { agreement-id: agreement-id })
)

(define-read-only (get-verification (verification-id uint))
    (map-get? quality-verifications { verification-id: verification-id })
)

;; Check if consent is valid and active
(define-read-only (is-consent-valid (patient-hash (buff 32)) (institution-id uint))
    (match (map-get? patient-consents { patient-hash: patient-hash, institution-id: institution-id })
        consent (and 
            (get consent-given consent)
            (> (get expiry-date consent) block-height)
            (is-none (get withdrawal-date consent))
        )
        false
    )
)

;; Get total counts for statistics
(define-read-only (get-total-institutions)
    (var-get institution-counter)
)

(define-read-only (get-total-datasets)
    (var-get dataset-counter)
)

(define-read-only (get-total-accesses)
    (var-get access-counter)
)
