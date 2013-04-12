(in-package :cl-user)
(defpackage execute-policy
  (:use :cl)
  (:import-from :queues :abstract-queue :take)
  (:export :abort-queuing :caller-runs :discard-oldest :discard
	   :reject-warning :discard-warning :queue-flood))
(in-package :execute-policy)

(defclass abstract-policy ()
  ())

(eval-when (:compile-toplevel :load-toplevel :execute)
  (defmacro gen-class (class-sym)
    `(defclass ,class-sym (abstract-policy)
       ())))

(gen-class abort-queuing)
(gen-class caller-runs)
(gen-class discard-oldest)
(gen-class discard)

(define-condition reject-warning (simple-warning)
  ())

(define-condition discard-warning (simple-warning)
  ())

(defgeneric queue-flood (queue policy))

(defmethod queue-flood ((queue abstract-queue) (policy abort-queuing))
  (declare (ignore queue policy))
  (warn 'reject-warning :format-control "job queue is flood."))

(defmethod queue-flood ((queue abstract-queue) (policy caller-runs))
  (declare (ignore policy))
  (let ((work (take queue)))
    (funcall work))
  t)

(defmethod queue-flood ((queue abstract-queue) (policy discard-oldest))
  (declare (ignore policy))
  (take queue)
  t)
  
(defmethod queue-flood ((queue abstract-queue) (policy discard))
  (declare (ignore queue policy))
  (warn 'discard-warning :format-control "job is discarded.")
  nil)