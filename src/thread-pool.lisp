(in-package :cl-user)
(defpackage thread-pool
  (:use :cl)
  (:import-from :kmrcl :with-gensyms)
  (:import-from :queues :put :offer :take :poll :peek :blocking-queue)
  (:import-from :workers :create-workers :wait-workers
		:kill-workers :workers-count :workers-start-p)
  (:import-from :local-time :now :sec-of :nsec-of)
  (:import-from :sb-thread :thread :join-thread
		:make-semaphore :try-semaphore :semaphore-count)
  (:import-from :execute-policy :abstract-policy
		:abort-queuing :caller-runs
		:discard-oldest :discard
		:queue-flood)
  (:export :thread-pool :start
	   :wait-shtudown-complete :shutdown :execute :with-thread-pool
	   :abort-queuing :caller-runs :discard-oldest :discard
	   :*default-thread-pool*))

(in-package :thread-pool)

(defparameter +nsec-to-sec-factor+ 1000000000)

(defclass thread-pool ()
  (queue workers check-interval check-times policy
	 (is-shutdown
	  :initform (sb-thread:make-semaphore :name "is-shutdown" :count 1))
	 (poison-pill :initform (gensym "POISON"))))

(defmethod initialize-instance :after ((instance thread-pool)
				       &key
				       (autostart-p nil)
				       (worker-count 8)
				       (pool-size nil is-pool-size-set-p)
				       (interval 0)
				       (times 10)
				       (exec-policy 'caller-runs))
  (declare (type integer worker-count interval times)
	   (type (or integer null) pool-size)
	   (type (or abstract-policy symbol) exec-policy))
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
	    policy (if (typep exec-policy 'execute-policy::abstract-policy)
		       exec-policy (make-instance exec-policy)))))
  (when autostart-p
    (start instance)))

(defun is-shutdown (instance)
  (with-slots (is-shutdown)
      instance
    (= (semaphore-count is-shutdown) 0)))

(defgeneric start (instance))
(defmethod start ((instance thread-pool))
  (when (is-shutdown instance)
    (error 'simple-error :format-control "already shutdown started."))
  (with-slots (workers)
      instance
    (workers:start-workers workers)))

(defgeneric execute (instance work))
(defmethod execute ((instance thread-pool) work)
  (unless (functionp work)
    (error 'simple-error :format-control "invalid argument: work, not a function."))
  (when (is-shutdown instance)
    (error 'simple-error :format-control "thread-pool is already shutdown progress."))
  (with-slots (check-interval check-times policy queue workers)
      instance
    (loop
       for rest-times from check-times downto 1
       when (offer queue work)
       return work
       end
       when (queue-flood queue policy)
       do (sleep check-interval)
       end)))

(defgeneric shutdown (instance &optional wait-p))
(defmethod shutdown ((instance thread-pool) &optional wait-p)
  (with-slots (queue workers is-shutdown poison-pill)
      instance
    (let ((number-of-threads (workers-count workers)))
      (unless (try-semaphore is-shutdown)
	(error 'simple-error :format-control "shutdown is already started."))
      (unless (workers-start-p workers)
	(loop
	   for (nil suc) = (multiple-value-list (queues:poll queue))
	   while suc
	   finally (workers:start-workers workers)))
      (loop for i below number-of-threads 
	 do (queues:put queue poison-pill))
      (when wait-p
	  (wait-workers workers)
	  (values)))))

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

(defmacro with-thread-pool ((sym &rest key-values) &body body)
  `(let ((,sym (make-instance 'thread-pool ,@key-values)))
     (unwind-protect
	  (progn
	    (start ,sym)
	    ,@body)
       (shutdown ,sym t))))

(defvar *default-thread-pool* (make-instance 'thread-pool :autostart-p t))