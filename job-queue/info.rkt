#lang setup/infotab
(define name "Job Queue")
(define release-notes
  (list '(ul
          (li "Adding identifier for worker"))))
(define repositories
  (list "4.x"))
(define blurb
  (list "A multi-threaded work queue manager"))
(define scribblings '(("job-queue.scrbl" () ("Parallelism"))))
(define primary-file "main.rkt")
(define categories '(misc))
