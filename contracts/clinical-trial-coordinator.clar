;; Clinical Trial Coordinator Contract
;; Coordinates multi-site clinical trials with participant recruitment and tracking
;; Handles funding distribution, protocol compliance, and intellectual property management

;; Error constants
(define-constant ERR-UNAUTHORIZED (err u200))
(define-constant ERR-NOT-FOUND (err u201))
(define-constant ERR-ALREADY-EXISTS (err u202))
(define-constant ERR-INVALID-STATUS (err u203))
(define-constant ERR-INSUFFICIENT-FUNDS (err u204))
(define-constant ERR-TRIAL-COMPLETED (err u205))
(define-constant ERR-COMPLIANCE-FAILED (err u206))
(define-constant ERR-INVALID-MILESTONE (err u207))

;; Contract deployer as admin
(define-constant CONTRACT-ADMIN tx-sender)

;; Trial status constants
(define-constant TRIAL-STATUS-PLANNING u1)
(define-constant TRIAL-STATUS-RECRUITING u2)
(define-constant TRIAL-STATUS-ACTIVE u3)
(define-constant TRIAL-STATUS-COMPLETED u4)
(define-constant TRIAL-STATUS-SUSPENDED u5)

;; Compliance status constants
(define-constant COMPLIANCE-PENDING u1)
(define-constant COMPLIANCE-PASSED u2)
(define-constant COMPLIANCE-FAILED u3)

;; Clinical trial sites
(define-map trial-sites
    { site-id: uint }
    {
        name: (string-ascii 100),
        principal-investigator: principal,
        location: (string-ascii 100),
        capacity: uint,
        certification-level: uint,
        active-trials: (list 10 uint),
        compliance-score: uint,
        registration-date: uint
    }
)

;; Clinical trial protocols
(define-map clinical-trials
    { trial-id: uint }
    {
        title: (string-ascii 200),
        sponsor: principal,
        protocol-hash: (buff 32),
        primary-site: uint,
        participating-sites: (list 20 uint),
        target-enrollment: uint,
        current-enrollment: uint,
        start-date: uint,
        estimated-end-date: uint,
        status: uint,
        total-funding: uint,
        distributed-funding: uint,
        compliance-required: bool
    }
)

;; Trial participants tracking
(define-map trial-participants
    { participant-id: (buff 32), trial-id: uint }
    {
        enrollment-date: uint,
        site-id: uint,
        consent-status: bool,
        completion-status: bool,
        adverse-events: uint,
        protocol-deviations: uint,
        data-quality-score: uint
    }
)

;; Milestone tracking for funding distribution
(define-map trial-milestones
    { milestone-id: uint }
    {
        trial-id: uint,
        site-id: uint,
        milestone-type: (string-ascii 50),
        target-value: uint,
        achieved-value: uint,
        due-date: uint,
        completion-date: (optional uint),
        funding-amount: uint,
        is-completed: bool,
        verification-required: bool
    }
)

;; Compliance monitoring records
(define-map compliance-reports
    { report-id: uint }
    {
        trial-id: uint,
        site-id: uint,
        audit-date: uint,
        auditor: principal,
        compliance-areas: (list 10 (string-ascii 50)),
        scores: (list 10 uint),
        overall-score: uint,
        status: uint,
        findings: (string-ascii 500),
        corrective-actions: (string-ascii 500)
    }
)

;; Intellectual property records
(define-map ip-records
    { ip-id: uint }
    {
        trial-id: uint,
        discovery-type: (string-ascii 100),
        inventors: (list 10 principal),
        discovery-date: uint,
        patent-application: (optional (string-ascii 100)),
        ownership-shares: (list 10 uint),
        commercialization-rights: (string-ascii 200),
        revenue-sharing: (list 10 uint)
    }
)

;; Research publication records
(define-map research-publications
    { publication-id: uint }
    {
        trial-id: uint,
        title: (string-ascii 300),
        authors: (list 20 principal),
        journal: (string-ascii 100),
        publication-date: uint,
        data-transparency: bool,
        open-access: bool,
        citation-count: uint,
        impact-score: uint
    }
)

;; Global counters
(define-data-var site-counter uint u0)
(define-data-var trial-counter uint u0)
(define-data-var milestone-counter uint u0)
(define-data-var report-counter uint u0)
(define-data-var ip-counter uint u0)
(define-data-var publication-counter uint u0)

;; Register clinical trial site
(define-public (register-site
    (name (string-ascii 100))
    (investigator principal)
    (location (string-ascii 100))
    (capacity uint)
    (certification-level uint))
    (let 
        (
            (new-id (+ (var-get site-counter) u1))
        )
        (asserts! (is-eq tx-sender CONTRACT-ADMIN) ERR-UNAUTHORIZED)
        
        (map-set trial-sites 
            { site-id: new-id }
            {
                name: name,
                principal-investigator: investigator,
                location: location,
                capacity: capacity,
                certification-level: certification-level,
                active-trials: (list),
                compliance-score: u100,
                registration-date: block-height
            }
        )
        (var-set site-counter new-id)
        (ok new-id)
    )
)

;; Register new clinical trial
(define-public (register-clinical-trial
    (title (string-ascii 200))
    (protocol-hash (buff 32))
    (primary-site uint)
    (target-enrollment uint)
    (estimated-duration uint)
    (total-funding uint))
    (let 
        (
            (new-id (+ (var-get trial-counter) u1))
            (site (unwrap! (map-get? trial-sites { site-id: primary-site }) ERR-NOT-FOUND))
        )
        (asserts! (or (is-eq tx-sender CONTRACT-ADMIN) 
                     (is-eq tx-sender (get principal-investigator site))) ERR-UNAUTHORIZED)
        
        (map-set clinical-trials 
            { trial-id: new-id }
            {
                title: title,
                sponsor: tx-sender,
                protocol-hash: protocol-hash,
                primary-site: primary-site,
                participating-sites: (list primary-site),
                target-enrollment: target-enrollment,
                current-enrollment: u0,
                start-date: block-height,
                estimated-end-date: (+ block-height estimated-duration),
                status: TRIAL-STATUS-PLANNING,
                total-funding: total-funding,
                distributed-funding: u0,
                compliance-required: true
            }
        )
        (var-set trial-counter new-id)
        (ok new-id)
    )
)

;; Add participating site to trial
(define-public (add-participating-site
    (trial-id uint)
    (site-id uint))
    (let 
        (
            (trial (unwrap! (map-get? clinical-trials { trial-id: trial-id }) ERR-NOT-FOUND))
            (site (unwrap! (map-get? trial-sites { site-id: site-id }) ERR-NOT-FOUND))
            (current-sites (get participating-sites trial))
        )
        (asserts! (is-eq tx-sender (get sponsor trial)) ERR-UNAUTHORIZED)
        (asserts! (< (len current-sites) u20) ERR-INVALID-STATUS)
        
        (map-set clinical-trials 
            { trial-id: trial-id }
            (merge trial { 
                participating-sites: (unwrap-panic (as-max-len? (append current-sites site-id) u20))
            })
        )
        (ok true)
    )
)

;; Enroll participant in trial
(define-public (enroll-participant
    (participant-hash (buff 32))
    (trial-id uint)
    (site-id uint))
    (let 
        (
            (trial (unwrap! (map-get? clinical-trials { trial-id: trial-id }) ERR-NOT-FOUND))
            (site (unwrap! (map-get? trial-sites { site-id: site-id }) ERR-NOT-FOUND))
        )
        (asserts! (is-eq tx-sender (get principal-investigator site)) ERR-UNAUTHORIZED)
        (asserts! (is-eq (get status trial) TRIAL-STATUS-RECRUITING) ERR-INVALID-STATUS)
        (asserts! (< (get current-enrollment trial) (get target-enrollment trial)) ERR-INVALID-STATUS)
        (asserts! (is-none (map-get? trial-participants { participant-id: participant-hash, trial-id: trial-id })) ERR-ALREADY-EXISTS)
        
        (map-set trial-participants 
            { participant-id: participant-hash, trial-id: trial-id }
            {
                enrollment-date: block-height,
                site-id: site-id,
                consent-status: true,
                completion-status: false,
                adverse-events: u0,
                protocol-deviations: u0,
                data-quality-score: u100
            }
        )
        
        (map-set clinical-trials 
            { trial-id: trial-id }
            (merge trial { current-enrollment: (+ (get current-enrollment trial) u1) })
        )
        (ok true)
    )
)

;; Create milestone for funding distribution
(define-public (create-milestone
    (trial-id uint)
    (site-id uint)
    (milestone-type (string-ascii 50))
    (target-value uint)
    (due-date uint)
    (funding-amount uint))
    (let 
        (
            (new-id (+ (var-get milestone-counter) u1))
            (trial (unwrap! (map-get? clinical-trials { trial-id: trial-id }) ERR-NOT-FOUND))
        )
        (asserts! (is-eq tx-sender (get sponsor trial)) ERR-UNAUTHORIZED)
        
        (map-set trial-milestones 
            { milestone-id: new-id }
            {
                trial-id: trial-id,
                site-id: site-id,
                milestone-type: milestone-type,
                target-value: target-value,
                achieved-value: u0,
                due-date: due-date,
                completion-date: none,
                funding-amount: funding-amount,
                is-completed: false,
                verification-required: true
            }
        )
        (var-set milestone-counter new-id)
        (ok new-id)
    )
)

;; Verify milestone completion
(define-public (verify-milestone
    (milestone-id uint)
    (achieved-value uint))
    (let 
        (
            (milestone (unwrap! (map-get? trial-milestones { milestone-id: milestone-id }) ERR-NOT-FOUND))
            (trial (unwrap! (map-get? clinical-trials { trial-id: (get trial-id milestone) }) ERR-NOT-FOUND))
            (site (unwrap! (map-get? trial-sites { site-id: (get site-id milestone) }) ERR-NOT-FOUND))
            (is-milestone-met (>= achieved-value (get target-value milestone)))
        )
        (asserts! (or (is-eq tx-sender (get sponsor trial))
                     (is-eq tx-sender (get principal-investigator site))) ERR-UNAUTHORIZED)
        (asserts! (not (get is-completed milestone)) ERR-INVALID-STATUS)
        
        (map-set trial-milestones 
            { milestone-id: milestone-id }
            (merge milestone {
                achieved-value: achieved-value,
                completion-date: (some block-height),
                is-completed: is-milestone-met
            })
        )
        
        ;; Update distributed funding if milestone met
        (if is-milestone-met
            (map-set clinical-trials 
                { trial-id: (get trial-id milestone) }
                (merge trial { 
                    distributed-funding: (+ (get distributed-funding trial) (get funding-amount milestone))
                })
            )
            true
        )
        (ok is-milestone-met)
    )
)

;; Submit compliance report
(define-public (submit-compliance-report
    (trial-id uint)
    (site-id uint)
    (compliance-areas (list 10 (string-ascii 50)))
    (scores (list 10 uint))
    (findings (string-ascii 500))
    (corrective-actions (string-ascii 500)))
    (let 
        (
            (new-id (+ (var-get report-counter) u1))
            (trial (unwrap! (map-get? clinical-trials { trial-id: trial-id }) ERR-NOT-FOUND))
            (overall-score (/ (fold + scores u0) (len scores)))
        )
        (asserts! (is-eq tx-sender CONTRACT-ADMIN) ERR-UNAUTHORIZED)
        
        (map-set compliance-reports 
            { report-id: new-id }
            {
                trial-id: trial-id,
                site-id: site-id,
                audit-date: block-height,
                auditor: tx-sender,
                compliance-areas: compliance-areas,
                scores: scores,
                overall-score: overall-score,
                status: (if (>= overall-score u70) COMPLIANCE-PASSED COMPLIANCE-FAILED),
                findings: findings,
                corrective-actions: corrective-actions
            }
        )
        (var-set report-counter new-id)
        (ok new-id)
    )
)

;; Record intellectual property discovery
(define-public (record-ip-discovery
    (trial-id uint)
    (discovery-type (string-ascii 100))
    (inventors (list 10 principal))
    (ownership-shares (list 10 uint))
    (commercialization-rights (string-ascii 200)))
    (let 
        (
            (new-id (+ (var-get ip-counter) u1))
            (trial (unwrap! (map-get? clinical-trials { trial-id: trial-id }) ERR-NOT-FOUND))
        )
        (asserts! (is-eq tx-sender (get sponsor trial)) ERR-UNAUTHORIZED)
        
        (map-set ip-records 
            { ip-id: new-id }
            {
                trial-id: trial-id,
                discovery-type: discovery-type,
                inventors: inventors,
                discovery-date: block-height,
                patent-application: none,
                ownership-shares: ownership-shares,
                commercialization-rights: commercialization-rights,
                revenue-sharing: ownership-shares
            }
        )
        (var-set ip-counter new-id)
        (ok new-id)
    )
)

;; Publish trial results
(define-public (publish-results
    (trial-id uint)
    (title (string-ascii 300))
    (authors (list 20 principal))
    (journal (string-ascii 100))
    (data-transparency bool)
    (open-access bool))
    (let 
        (
            (new-id (+ (var-get publication-counter) u1))
            (trial (unwrap! (map-get? clinical-trials { trial-id: trial-id }) ERR-NOT-FOUND))
        )
        (asserts! (is-eq tx-sender (get sponsor trial)) ERR-UNAUTHORIZED)
        (asserts! (is-eq (get status trial) TRIAL-STATUS-COMPLETED) ERR-INVALID-STATUS)
        
        (map-set research-publications 
            { publication-id: new-id }
            {
                trial-id: trial-id,
                title: title,
                authors: authors,
                journal: journal,
                publication-date: block-height,
                data-transparency: data-transparency,
                open-access: open-access,
                citation-count: u0,
                impact-score: u0
            }
        )
        (var-set publication-counter new-id)
        (ok new-id)
    )
)

;; Update trial status
(define-public (update-trial-status
    (trial-id uint)
    (new-status uint))
    (let 
        (
            (trial (unwrap! (map-get? clinical-trials { trial-id: trial-id }) ERR-NOT-FOUND))
        )
        (asserts! (is-eq tx-sender (get sponsor trial)) ERR-UNAUTHORIZED)
        (asserts! (<= new-status u5) ERR-INVALID-STATUS)
        
        (map-set clinical-trials 
            { trial-id: trial-id }
            (merge trial { status: new-status })
        )
        (ok true)
    )
)

;; Read-only functions
(define-read-only (get-trial (trial-id uint))
    (map-get? clinical-trials { trial-id: trial-id })
)

(define-read-only (get-site (site-id uint))
    (map-get? trial-sites { site-id: site-id })
)

(define-read-only (get-participant (participant-hash (buff 32)) (trial-id uint))
    (map-get? trial-participants { participant-id: participant-hash, trial-id: trial-id })
)

(define-read-only (get-milestone (milestone-id uint))
    (map-get? trial-milestones { milestone-id: milestone-id })
)

(define-read-only (get-compliance-report (report-id uint))
    (map-get? compliance-reports { report-id: report-id })
)

(define-read-only (get-ip-record (ip-id uint))
    (map-get? ip-records { ip-id: ip-id })
)

(define-read-only (get-publication (publication-id uint))
    (map-get? research-publications { publication-id: publication-id })
)

;; Get enrollment progress
(define-read-only (get-enrollment-progress (trial-id uint))
    (match (map-get? clinical-trials { trial-id: trial-id })
        trial (some {
            current-enrollment: (get current-enrollment trial),
            target-enrollment: (get target-enrollment trial),
            progress-percentage: (/ (* (get current-enrollment trial) u100) (get target-enrollment trial))
        })
        none
    )
)

;; Get funding distribution status
(define-read-only (get-funding-status (trial-id uint))
    (match (map-get? clinical-trials { trial-id: trial-id })
        trial (some {
            total-funding: (get total-funding trial),
            distributed-funding: (get distributed-funding trial),
            remaining-funding: (- (get total-funding trial) (get distributed-funding trial))
        })
        none
    )
)

;; Get total counts
(define-read-only (get-total-sites)
    (var-get site-counter)
)

(define-read-only (get-total-trials)
    (var-get trial-counter)
)

(define-read-only (get-total-publications)
    (var-get publication-counter)
)
