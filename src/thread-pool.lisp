(in-package :cl-user)
(defpackage thread-pool
  (:use :cl)
  (:import-from :kmrcl :with-gensyms)
  (:import-from :queues :put :offer :take :poll :peek)
  (:import-from :blocking-queue :blocking-queue)
  (:import-from :workers :create-workers :wait-workers
		:kill-workers :workers-count)
  (:import-from :local-time :now :sec-of :nsec-of)
  (:import-from :sb-thread :thread :join-thread
		:make-semaphore :try-semaphore :semaphore-count)
  (:import-from :execute-policy :abort-execute :caller-runs
		:discard-oldest :discard
		:reject-error :discard-condition
		:queue-flood)
  (:export :thread-pool :reject-error
	   :wait-shtudown-complete :shutdown :execute))

(in-package :thread-pool)

(defparameter +nsec-to-sec-factor+ 1000000000)

(defclass thread-pool ()
  (queue workers check-interval check-times policy
	 (is-shutdown
	  :initform (sb-thread:make-semaphore :name "is-shutdown" :count 1))
	 (poison-pill :initform (gensym "POISON"))))

(defmethod initialize-instance :after ((instance thread-pool)
				       &key (worker-count 8)
				       (pool-size nil is-pool-size-set-p)
				       (interval 0)
				       (times 10)
				       (exec-policy 'caller-run))
  (declare (type integer pool-size interval times))
  (with-slots (queue workers poison-pill check-interval check-times policy)
      instance
    (let ((pool-size (if is-pool-size-set-p pool-size (* worker-count 10))))
      (setf queue (make-instance 'blocking-queue :capacity pool-size)
	    workers (create-workers worker-count
				    (lambda ()
				      (loop
					 for job = (queues:take queue)
					 until (eq job poison-pill)
					 do (ignore-errors (funcall job)))))
	    check-interval interval
	    check-times times
	    poison-pill (gensym)
	    policy exec-policy))))

(defgeneric execute (instance work))
;(defmethod execute ((instance thread-pool) work)
;  (with-slots 
  


(defgeneric shutdown (instance &key wait-p))
(defmethod shutdown ((instance thread-pool) &key (wait-p nil))
  (with-slots (queue workers is-shutdown poison-pill)
      instance
    (let ((number-of-threads (workers-count workers)))
      (unless (try-semaphore is-shutdown)
	(error 'simple-error :format-control "shutdown is already started."))
      (loop for i below number-of-threads 
	 do (queues:put queue poison-pill))
      (when wait-p
	  (wait-workers workers)))))

(defun time-to-nsecs (time)
  (let ((secs (sec-of time))
	(nsecs (nsec-of time)))
    (+ nsecs (* secs +nsec-to-sec-factor+))))

(defmacro with-time-count (&body body)
    (with-gensyms (time-start time-end)
      `(let* ((,time-start (time-to-nsecs (now)))
	      (,time-end ,time-start)
	     (result (multiple-value-list
		      (unwind-protect
			   (progn
			     ,@body)
			(setf ,time-end (time-to-nsecs (now)))))))
	 (apply #'values (- ,time-end ,time-start) result))))

(defun thread-p (value)
  (typep value 'sb-thread:thread))

(defun check-workers (workers)
  (loop for i below (length workers)
     do (when (thread-p (svref workers i))
	  (ignore-errors
	    (setf (svref workers i)
		  (sb-thread:join-thread (svref workers i) :timeout 0)))))
  (every #'null (loop for val across workers collect (thread-p val))))

(defgeneric wait-shutdown-complete (instance &key timeout check-interval))
(defmethod wait-shutdown-complete ((instance thread-pool)
				   &key (timeout 0) (check-interval 0))
  (with-slots (workers is-shutdown)
      instance
    (unless (= (semaphore-count is-shutdown) 0)
      (error 'simple-error :format-control "shutdown is not started."))
    (let ((workers (workers::workers workers))
	  (limit-time (* timeout +nsec-to-sec-factor+)))
      (loop
	 do (setf limit-time
		  (- limit-time
		     (with-time-count
		       (if (check-workers workers)
			   (return-from wait-shutdown-complete t)
			   (sleep check-interval)))))
	 when (<= limit-time 0)
	 return nil))))
	  