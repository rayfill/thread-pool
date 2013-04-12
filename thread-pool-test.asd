(in-package :cl-user)
(defpackage thread-pool-test-asd
  (:use :cl :asdf))
(in-package :thread-pool-test-asd)

(defsystem thread-pool-test
  :author ""
  :license ""
  :depends-on (:thread-pool
               :cl-test-more)
  :components ((:module "t"
                :components
                ((:file "execute-policy")
		 (:file "thread-pool"))))
  :perform (load-op :after (op c) (asdf:clear-system c)))
