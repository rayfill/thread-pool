#|
  This file is a part of thread-pool project.
|#

(in-package :cl-user)
(defpackage thread-pool-asd
  (:use :cl :asdf))
(in-package :thread-pool-asd)

(defsystem thread-pool
  :version "0.1"
  :author ""
  :license ""
  :depends-on (:queues :workers :local-time)
  :components ((:module "src"
                :components
                ((:file "execute-policy")
		 (:file "thread-pool"))))
  :description ""
  :long-description
  #.(with-open-file (stream (merge-pathnames
                             #p"README.markdown"
                             (or *load-pathname* *compile-file-pathname*))
                            :if-does-not-exist nil
                            :direction :input)
      (when stream
        (let ((seq (make-array (file-length stream)
                               :element-type 'character
                               :fill-pointer t)))
          (setf (fill-pointer seq) (read-sequence seq stream))
          seq)))
  :in-order-to ((test-op (load-op thread-pool-test))))
