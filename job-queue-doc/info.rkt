#lang info
(define version "1.0")
(define deps '("base"
               "job-queue-lib"))
(define build-deps '("racket-doc"
                     "scribble-lib"
                     ))
(define update-implies '("job-queue-lib"))
(define collection "job-queue")
(define scribblings '(("job-queue.scrbl" () ("Parallelism"))))
