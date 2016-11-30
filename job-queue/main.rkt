#lang racket/base
(require racket/list
         racket/match
         racket/contract
         racket/async-channel)

(define current-worker (make-parameter #f))

(struct job-queue (manager-t))
(struct job (paramz thunk))

(define (make-queue how-many)
  (define work-ch (make-async-channel))
  (define count-sema (make-semaphore 0))
  
  (define (worker quit-sema i)
    (sync
     ;; Die when this semaphore is signaled
     (handle-evt quit-sema void)
     ;; Otherwise handle a job
     (handle-evt
      work-ch
      (match-lambda
        [(struct job (paramz thunk))
         (with-handlers ([exn?
                          (λ (e)
                            ((error-display-handler) (exn-message e) e))])
           (call-with-parameterization
            paramz
            (lambda ()
              (parameterize ([current-worker i])
                (thunk)))))
         ;; Record that the job was successful
         (semaphore-post count-sema)
         (worker quit-sema i)]))))
  (define worker->quit-sema
    (for/hasheq ([i (in-range 0 how-many)])
      (define quit-sema (make-semaphore 0))
      (define worker-t (thread (lambda () (worker quit-sema i))))
      (values worker-t quit-sema)))

  (define (manager how-many)
    (match (thread-receive)
      ['stop
       (killing-manager how-many)]
      [(? job? j)
       (async-channel-put work-ch j)
       (manager (add1 how-many))]))
  (define (killing-manager how-many)
    ;; Wait for all outstanding jobs to finish
    (for ([i (in-range how-many)])
      (semaphore-wait count-sema))
    ;; Tell all workers to die
    (for ([quit-sema (in-hash-values worker->quit-sema)])
      (semaphore-post quit-sema))
    ;; Wait for them to die
    (for ([worker-t (in-hash-keys worker->quit-sema)])
      (sync worker-t)))
  (define manager-t
    (thread (λ () (manager 0))))

  (job-queue manager-t))

(define (submit-job! jobq thunk)
  (match-define (job-queue t) jobq)
  (define j (job (current-parameterization) thunk))
  ;; XXX If the jobq is in the process of dying, then this will
  ;; silently throw-away the job
  (thread-send t j))

(define (stop-job-queue! jobq)
  (match-define (job-queue t) jobq)
  (thread-send t 'stop)
  (void (sync t)))

(provide/contract
 [current-worker (parameter/c (or/c false/c exact-nonnegative-integer?))]
 [job-queue? (any/c . -> . boolean?)]
 [rename make-queue make-job-queue (exact-nonnegative-integer? . -> . job-queue?)]
 [submit-job! (job-queue? (-> any) . -> . void)]
 [stop-job-queue! (job-queue? . -> . void)])

(module* test racket/base
  (require (submod ".."))
  (define jq (make-job-queue 4))

  (for ([i (in-range 100)])
    (submit-job! jq
                 (λ ()
                   ((if (zero? (random 2))
                      error
                      displayln)
                    (number->string i)))))

  (stop-job-queue! jq)

  (printf "Done\n"))
