(in-package :cl-user)
(defpackage execute-policy
  (:use :cl)
  (:import-from :queues :abstract-queue :take)
  (:export :abort-execute :caller-runs :discard-oldest :discard
	   :reject-error :discard-condition :queue-flood))
(in-package :execute-policy)

(defclass abstract-policy ()
  ())

(eval-when (:compile-toplevel :load-toplevel :execute)
  (defmacro gen-class (class-sym)
    `(defclass ,class-sym (abstract-policy)
       ())))

(gen-class abort-execute)
(gen-class caller-runs)
(gen-class discard-oldest)
(gen-class discard)

(define-condition reject-error (simple-error)
  ())

(define-condition discard-condition (simple-condition)
  ())

(defgeneric queue-flood (queue policy))

(defmethod queue-flood ((queue abstract-queue) (policy abort-execute))
  (declare (ignore queue policy))
  (error 'reject-error :format-control "job queue is flood."))

(defmethod queue-flood ((queue abstract-queue) (policy caller-runs))
  (declare (ignore policy))
  (let ((work (take queue)))
    (funcall work)))

(defmethod queue-flood ((queue abstract-queue) (policy discard-oldest))
  (declare (ignore policy))
  (take queue)
  (values))
  
(defmethod queue-flood ((queue abstract-queue) (policy discard))
  (declare (ignore queue policy))
  (signal 'discard-condition))