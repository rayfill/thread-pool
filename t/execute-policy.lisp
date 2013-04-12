(in-package :cl-user)
(defpackage execute-policy-test
  (:use :cl
        :execute-policy
	:queues
        :cl-test-more))
(in-package :execute-policy-test)

(plan nil)

(defun exec-test (class &rest values)
  (let ((q (queues:create-queue 'queues:blocking-queue)))
    (loop for i in values do (queues:put q i))
    (queue-flood q (make-instance class))
    q))

(let (cought-error)
  (handler-case 
      (exec-test 'abort-execute)
    (reject-error (e) (setf cought-error e)))
  (is (class-of cought-error) (find-class 'reject-error)))

(defparameter *result* nil)
(let ((*result* nil))
  (let ((q (exec-test 'caller-runs (lambda () (setf *result* t)))))
    (multiple-value-bind (val suc)
	(queues:poll q)
      (is val nil)
      (is suc nil)
      (is *result* t))))

(let ((q (exec-test 'discard-oldest (lambda () (error 'simple-error)))))
  (multiple-value-bind (val suc)
      (queues:poll q)
    (is val nil)
    (is suc nil)))

(let ((result nil))
  (handler-case
      (exec-test 'discard (lambda () (error 'simple-error)))
    (execute-policy:discard-condition (e) (setf result e)))
  (isnt result nil)
  (is (class-of result) (find-class 'execute-policy:discard-condition)))
	


(finalize)
