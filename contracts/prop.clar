;; PropChain: Fractional Real Estate Investment Platform
;; A blockchain-based system for fractional real estate ownership and investment
;; Features:
;; - Property tokenization with fractional ownership shares
;; - Investment pool management and dividend distribution
;; - Secure property transfers and ownership tracking
;; - Investment withdrawal and liquidity management

(define-non-fungible-token property-share (string-ascii 100))

;; Contract Configuration
(define-constant platform-manager tx-sender)
(define-constant ERR-MANAGER-ONLY (err u300))
(define-constant ERR-PROPERTY-EXISTS (err u301))
(define-constant ERR-PROPERTY-NOT-FOUND (err u302))
(define-constant ERR-INVALID-SHAREHOLDER (err u303))
(define-constant ERR-PARAMETER-INVALID (err u304))
(define-constant ERR-SHARES-UNAVAILABLE (err u305))
(define-constant ERR-PROPERTY-WITHDRAWN (err u306))
(define-constant ERR-PAYMENT-ERROR (err u307))
(define-constant ERR-ACTIVE-INVESTMENTS (err u308))
(define-constant ERR-INVALID-INVESTOR (err u309))
(define-constant ERR-PROPERTY-ACTIVE (err u310))

;; Input Validation Functions
(define-private (is-property-address-valid (property-address (string-ascii 100)))
  (and 
    (> (len property-address) u0) 
    (<= (len property-address) u100)
  )
)

(define-private (is-location-valid (property-location (string-ascii 50)))
  (and 
    (> (len property-location) u0) 
    (<= (len property-location) u50)
  )
)

(define-private (is-investment-valid (share-price uint))
  (> share-price u0)
)

(define-private (is-supply-valid (total-shares uint))
  (> total-shares u0)
)

;; Identity Validation
(define-private (is-investor-valid (investor-address principal))
  (not (is-eq investor-address platform-manager))
)

;; Data Storage
(define-map property-portfolio 
  {property-id: (string-ascii 100)} 
  {
    property-address: (string-ascii 100),
    property-location: (string-ascii 50),
    share-price: uint,
    total-shares: uint,
    shares-issued: uint,
    property-withdrawn: bool
  }
)

;; Investment Registry
(define-map property-investors
  {property-id: (string-ascii 100), investor-address: principal} 
  bool
)

;; Public Query Functions
(define-read-only (get-share-owner (property-id (string-ascii 100)))
  (nft-get-owner? property-share property-id)
)

(define-read-only (get-property-info (property-id (string-ascii 100)))
  (map-get? property-portfolio {property-id: property-id})
)

;; List New Property
(define-public (list-property 
  (property-id (string-ascii 100))
  (property-address (string-ascii 100))
  (property-location (string-ascii 50))
  (share-price uint)
  (total-shares uint)
)
  (begin
    ;; Validate inputs
    (asserts! (is-property-address-valid property-address) ERR-PARAMETER-INVALID)
    (asserts! (is-location-valid property-location) ERR-PARAMETER-INVALID)
    (asserts! (is-investment-valid share-price) ERR-PARAMETER-INVALID)
    (asserts! (is-supply-valid total-shares) ERR-PARAMETER-INVALID)
    
    ;; Ensure property hasn't been listed before
    (asserts! (is-none (get-property-info property-id)) ERR-PROPERTY-EXISTS)
    
    ;; Initialize property data
    (map-set property-portfolio 
      {property-id: property-id}
      {
        property-address: property-address,
        property-location: property-location,
        share-price: share-price,
        total-shares: total-shares,
        shares-issued: u0,
        property-withdrawn: false
      }
    )
    
    ;; Register property in the system
    (nft-mint? property-share property-id platform-manager)
  )
)

;; Update Property Details
(define-public (update-property-listing
  (property-id (string-ascii 100))
  (updated-address (string-ascii 100))
  (updated-location (string-ascii 50))
  (updated-price uint)
)
  (let ((property-data (unwrap! (get-property-info property-id) ERR-PROPERTY-NOT-FOUND)))
    (begin
      ;; Security check
      (asserts! (is-eq tx-sender platform-manager) ERR-MANAGER-ONLY)
      
      ;; Prevent updates after investments
      (asserts! (is-eq (get shares-issued property-data) u0) ERR-ACTIVE-INVESTMENTS)
      
      ;; Validate new parameters
      (asserts! (is-property-address-valid updated-address) ERR-PARAMETER-INVALID)
      (asserts! (is-location-valid updated-location) ERR-PARAMETER-INVALID)
      (asserts! (is-investment-valid updated-price) ERR-PARAMETER-INVALID)
      
      ;; Update property information
      (map-set property-portfolio 
        {property-id: property-id}
        (merge property-data {
          property-address: updated-address,
          property-location: updated-location,
          share-price: updated-price
        })
      )
      
      (ok true)
    )
  )
)

;; Invest in Property
(define-public (invest-in-property (property-id (string-ascii 100)))
  (let ((property-data (unwrap! (get-property-info property-id) ERR-PROPERTY-NOT-FOUND)))
    (begin
      ;; Check property status
      (asserts! (not (get property-withdrawn property-data)) ERR-PROPERTY-WITHDRAWN)
      
      ;; Check share availability
      (asserts! 
        (< (get shares-issued property-data) (get total-shares property-data)) 
        ERR-SHARES-UNAVAILABLE
      )
      
      ;; Process investment payment
      (try! (stx-transfer? (get share-price property-data) tx-sender platform-manager))
      
      ;; Update shares counter
      (map-set property-portfolio 
        {property-id: property-id}
        (merge property-data {shares-issued: (+ (get shares-issued property-data) u1)})
      )
      
      ;; Register investor
      (map-set property-investors
        {property-id: property-id, investor-address: tx-sender} 
        true
      )
      
      ;; Issue share to investor
      (nft-mint? property-share property-id tx-sender)
    )
  )
)

;; Transfer Property Share
(define-public (transfer-share 
  (property-id (string-ascii 100)) 
  (new-investor principal)
)
  (begin
    ;; Validate recipient
    (asserts! (is-investor-valid new-investor) ERR-INVALID-INVESTOR)
    
    ;; Verify ownership
    (asserts! 
      (is-eq tx-sender (unwrap! (nft-get-owner? property-share property-id) ERR-PROPERTY-NOT-FOUND)) 
      ERR-INVALID-SHAREHOLDER
    )
    
    ;; Update investor records
    (map-delete property-investors {property-id: property-id, investor-address: tx-sender})
    (map-set property-investors
      {property-id: property-id, investor-address: new-investor} 
      true
    )
    
    ;; Transfer NFT share
    (nft-transfer? property-share property-id tx-sender new-investor)
  )
)

;; Withdraw Property from Market
(define-public (withdraw-property (property-id (string-ascii 100)))
  (let ((property-data (unwrap! (get-property-info property-id) ERR-PROPERTY-NOT-FOUND)))
    (begin
      ;; Manager-only operation
      (asserts! (is-eq tx-sender platform-manager) ERR-MANAGER-ONLY)
      
      ;; Prevent duplicate withdrawal
      (asserts! (not (get property-withdrawn property-data)) ERR-PROPERTY-WITHDRAWN)
      
      ;; Mark property as withdrawn
      (map-set property-portfolio
        {property-id: property-id}
        (merge property-data {property-withdrawn: true})
      )
      
      (ok true)
    )
  )
)

;; Claim Investment Refund
(define-public (claim-investment-refund (property-id (string-ascii 100)))
  (let (
    (property-data (unwrap! (get-property-info property-id) ERR-PROPERTY-NOT-FOUND))
    (share-holder (unwrap! (nft-get-owner? property-share property-id) ERR-PROPERTY-NOT-FOUND))
  )
    (begin
      ;; Verify property is withdrawn
      (asserts! (get property-withdrawn property-data) ERR-PROPERTY-ACTIVE)
      
      ;; Verify share ownership
      (asserts! (is-eq tx-sender share-holder) ERR-INVALID-SHAREHOLDER)
      
      ;; Burn property share
      (try! (nft-burn? property-share property-id tx-sender))
      
      ;; Process refund
      (try! (stx-transfer? (get share-price property-data) platform-manager tx-sender))
      
      ;; Remove from investor list
      (map-delete property-investors
        {property-id: property-id, investor-address: tx-sender}
      )
      
      (ok true)
    )
  )
)