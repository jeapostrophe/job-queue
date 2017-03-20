#lang scribble/manual
@(require (for-label racket/base
                     racket/contract
                     job-queue))

@title{Job Queue}
@author{@(author+email "Jay McCarthy" "jay@racket-lang.org")}

A multi-threaded job queue.

@defmodule[job-queue]

@defthing[current-worker (parameter/c (or/c false/c exact-nonnegative-integer?))]

An identifier for the current worker, or @scheme[#f] outside a manager.

@defproc[(job-queue? [v any/c]) boolean?]

Returns true if @scheme[v] is a job queue.

@defproc[(make-job-queue [how-many-workers exact-nonnegative-integer?]) job-queue?]

Starts a queue with @scheme[how-many-workers] threads servicing jobs.

@defproc[(submit-job! [jq job-queue?] [job (-> any)]) void]

Runs @scheme[job] by one of @scheme[jq]'s workers. @scheme[job] is run in the same parameterization as the call to @scheme[submit-job!]. This call will never block.

@defproc[(stop-job-queue! [jq job-queue?]) void]

Blocks until all of @scheme[jq]'s current jobs are finished and its workers are dead. Once @scheme[stop-job-queue!] has been called, @scheme[jq] will reject subsequent requests and @scheme[submit-job!] will block indefinitely.
