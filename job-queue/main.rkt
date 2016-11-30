#lang racket/base
(require racket/list
         racket/match
         racket/contract
         racket/async-channel)

(define current-worker (make-parameter #f))

(struct job-queue (manager async-channel))
(struct job (paramz thunk))
(struct done ())

(define (make-queue how-many)
  (define jobs-ch (make-async-channel))
  (define work-ch (make-async-channel))
  (define done-ch (make-async-channel))
  (define (working-manager spaces accept-new? jobs continues)
    (if (and (not accept-new?)
             (empty? jobs)
             (empty? continues))
      (first-killing-manager how-many)
      (apply
       sync
       (if (and accept-new?
                (not (zero? spaces)))
         (handle-evt
          jobs-ch
          (match-lambda
            [(? job? the-job)
             (working-manager (sub1 spaces) accept-new? (list* the-job jobs) continues)]
            [(? done?)
             (working-manager spaces #f jobs continues)]))
         never-evt)
       (handle-evt
        done-ch
        (lambda (reply-ch)
          (working-manager spaces accept-new? jobs (list* reply-ch continues))))
       (if (empty? jobs)
         never-evt
         (handle-evt
          (async-channel-put-evt work-ch (first jobs))
          (lambda (_)
            (working-manager spaces accept-new? (rest jobs) continues))))
       (map
        (lambda (reply-ch)
          (handle-evt
           (async-channel-put-evt reply-ch
                                  (if accept-new? 'continue 'stop))
           (lambda (_)
             (working-manager (add1 spaces) accept-new? jobs (remq reply-ch continues)))))
        continues))))
  (define (first-killing-manager left)
    (for ([(i quit-sema) (in-hash worker->quit-sema)])
      (printf "m quit to ~a\n" i)
      (semaphore-post quit-sema))
    (killing-manager left))
  (define (killing-manager left)
    (unless (zero? left)
      (sync
       (handle-evt
        done-ch
        (lambda (reply-ch)
          (printf "m stop at ~a\n" left)
          (async-channel-put reply-ch 'stop)
          (killing-manager (sub1 left)))))))
  (define (worker quit-sema i)
    (printf "~a waiting for job\n" i)
    (sync
     (handle-evt quit-sema void)
     (handle-evt
      work-ch
      (match-lambda
        [(struct job (paramz thunk))
         (with-handlers ([exn?
                          (λ (e)
                            (printf "Caught ~v\n" e)
                            ((error-display-handler) (exn-message e) e)
                            (printf "Printed\n"))])
           (call-with-parameterization
            paramz
            (lambda ()
              (parameterize ([current-worker i])
                (thunk)))))])))
    (define reply-ch (make-async-channel))
    (async-channel-put done-ch reply-ch)
    (printf "~a waiting for reply\n" i)
    (define reply-v (async-channel-get reply-ch))
    (case reply-v
      [(continue) (worker quit-sema i)]
      [(stop) (void)]
      [else
       (error 'worker "Unknown reply command")]))
  (define worker->quit-sema
    (for/hasheq ([i (in-range 0 how-many)])
      (define quit-sema (make-semaphore 0))
      (thread (lambda () (worker quit-sema i)))
      (values i quit-sema)))
  (define the-manager
    (thread (lambda () (working-manager how-many #t empty empty))))
  (job-queue the-manager jobs-ch))

(define (submit-job! jobq thunk)
  (async-channel-put
   (job-queue-async-channel jobq)
   (job (current-parameterization)
             thunk)))

(define (stop-job-queue! jobq)
  (async-channel-put
   (job-queue-async-channel jobq)
   (done))
  (void (sync (job-queue-manager jobq))))

(provide/contract
 [current-worker (parameter/c (or/c false/c exact-nonnegative-integer?))]
 [job-queue? (any/c . -> . boolean?)]
 [rename make-queue make-job-queue (exact-nonnegative-integer? . -> . job-queue?)]
 [submit-job! (job-queue? (-> any) . -> . void)]
 [stop-job-queue! (job-queue? . -> . void)])

(module* test racket/base
  (require (submod ".."))
  (define jq (make-job-queue 4))

  (submit-job! jq (λ () (error 'foo)))
  (submit-job! jq (λ () (error 'bar)))
  (submit-job! jq (λ () (displayln 4)))
  (submit-job! jq (λ () (displayln 5)))

  (stop-job-queue! jq)

  (printf "Done\n"))
