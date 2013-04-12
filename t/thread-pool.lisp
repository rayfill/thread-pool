(in-package :cl-user)
(defpackage thread-pool-test
  (:use :cl
        :thread-pool
        :cl-test-more)
  (:import-from :execute-policy
		:abort-queuing :caller-runs :discard-oldest :discard
		:reject-warning :discard-warning
		:queue-flood))
(in-package :thread-pool-test)

(plan nil)

(let ((tp (make-instance 'thread-pool
			 :exec-policy (make-instance 'abort-queuing)
			 :pool-size 10 :worker-count 10)))
  (let ((count (loop for i from 0
		  while (execute tp (lambda ()
				      (sleep 5)
				      1))
		  finally (return i))))
    (ok count 20)))

(finalize)
