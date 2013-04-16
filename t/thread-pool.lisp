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

(let ((sum (make-array 1 :element-type 'sb-ext:word :initial-element 0))
      (out *standard-output*))
  (ok (>= (with-thread-pool (tp :exec-policy (make-instance 'abort-queuing)
				:pool-size 10 :worker-count 10)
	    (let ((count (loop for i from 0
			    while (let ((i i))
				    (execute tp (lambda ()
						  (sleep 3)
						  (format out "call increment.~A~%" i)
						  (sb-ext:atomic-incf (aref sum 0)))))
			    do (format t "queuing...~A~%" i)
			    finally (return i))))
	      count)) 10)) ;; (ok (>= count 10))
  (format t "sum: ~A~%" (aref sum 0))
  (ok (>= (aref sum 0) 10) (format nil "actualy sum is ~A~%" (aref sum 0))))

(finalize)
