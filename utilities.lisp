;;; -*- Package: de.setf.amqp.implementation; -*-

(in-package :de.setf.amqp.implementation)

(document :file
 (description "This file defines utility operators for the 'de.setf.amqp' library.")
 (copyright
  "Copyright 2010 [james anderson](mailto:james.anderson@setf.de) All Rights Reserved"
  "'de.setf.amqp' is free software: you can redistribute it and/or modify it under the terms of version 3
  of the GNU Affero General Public License as published by the Free Software Foundation.

  'setf.amqp' is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the
  implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
  See the Affero General Public License for more details.

  A copy of the GNU Affero General Public License should be included with 'de.setf.amqp' as `AMQP:agpl.txt`.
  If not, see the GNU [site](http://www.gnu.org/licenses/)."))


;;;
;;; macros

(defmacro assert-condition (form &rest args)
  (let ((format-string nil) (format-arguments nil) (operator nil))
    (when (or (typep (first args) '(and symbol (not keyword)))
              (and (consp (first args)) (eq (caar args) 'setf)))
      (setf operator (pop args)))
    (when (stringp (first args))
      (setf format-string (pop args)
            format-arguments (shiftf args nil)))
    (destructuring-bind (&key (operator operator) (format-string format-string) (format-arguments format-arguments)
                              (type (if (and (consp form) (eq (first form) 'typep)) (third form) `(satisfies ,form))))
                        args
      `(unless ,form
         (error 'simple-type-error
                :expected-type (quote ,type)
                :format-string ,(format nil "~@[~a: ~]condition failed: ~s~:[.~; ~~@?~]"
                                        operator form
                                  format-string)
                :format-arguments ,(when format-string `(list ,format-string ,@format-arguments)))))))

(defmacro def-delegate-slot ((class slot) &rest operators)
  `(progn ,@(mapcar #'(lambda (op)
                        `(progn (defmethod ,op ((instance ,class)) (,op (slot-value instance ',slot)))
                                (defmethod (setf ,op) (value (instance ,class)) (setf (,op (slot-value instance ',slot)) value))))
                    operators)))

(defmacro assert-argument-type (operator variable type &optional (required-p t) (test `(typep ,variable ',type)))
  (let ((form `(assert ,test ()
                       ,(format nil "~s: the ~:[(optional) ~;~] ~a argument must be of type ~a."
                                operator required-p variable type))))
    (if required-p
      form
      `(when ,variable ,form))))

(defmacro assert-argument-types (operator &rest assertions)
  `(progn ,@(loop for assertion in assertions
                  collect `(assert-argument-type ,operator ,@assertion))))

#+mcl
(setf (ccl:assq 'assert-argument-types ccl:*fred-special-indent-alist*) 1)


;;; assorted
(unless (boundp 'directory-pathname-p)
  (defun directory-pathname-p (path)
    (let ((name (pathname-name path))(type (pathname-type path)))
      (and  (or (null name) (eq name :unspecific) (zerop (length name)))
            (or (null type) (eq type :unspecific))))))

;;; logging

(defparameter amqp:*log-level* :warn)

(defparameter *log-levels* '(:debug :verbose :warn :error))

(defparameter *log-stream* *trace-output*)

(defmacro amqp:log (criteria class &rest args)
  (let ((log-op (gensym)))
    `(flet ((,log-op (stream)
              (format stream "~&[~/date::format-iso-time/] ~a ~a: ~@?"
                      (get-universal-time) ',criteria ,class ,@args)))
       (declare (dynamic-extent (function ,log-op)))
       (log-when ',criteria (function ,log-op)))))

(defmacro amqp:log* (criteria class &rest args)
  (let ((log-op (gensym)))
    `(flet ((,log-op (stream)
              (apply #'format stream "~&[~/date::format-iso-time/] ~a ~a: ~@?"
                      (get-universal-time) ',criteria ,class ,@args)))
       (declare (dynamic-extent (function ,log-op)))
       (log-when ',criteria (function ,log-op)))))

(defun write-log-entry (op)
  (let ((*print-readably* nil))
    (when *log-stream* (funcall op *log-stream*))))

(defun log-when (criteria op)
  (when (find criteria (member *log-level* *log-levels*))
    (write-log-entry op)))

;;;
;;; instance tags are just the type and identity

(defun make-instance-tag (instance)
  (with-output-to-string (stream)
    (print-unreadable-object (instance stream :type t :identity t))))

;;;
;;; Version keywords reflect the version information contained in a protocol
;;; header. The symbol name comprises the initial 4-byte protocol identifier 
;;; and the class, instance, and major/minor version numbers, each separated
;;; by a '-'

(defun make-version-keyword (&key (name :amqp)
                                  (class 1) (instance 1)
                                  (major (error "major version number is required."))
                                  (minor (error "minor version number is required."))
                                  (revision 0))
  "Generate the version keyword for the given combination of
 CLASS, INSTANCE, and MAJOR, MINOR, and REVISION numbers.
 By default class and instance default to '1', while the default revision
 is '0'. Both major and minor version number are required."
  (intern (format nil "~:@(~a~)-~d-~d-~d-~d-~d"
                  name
                  class instance major minor revision)
          :keyword))

(defun parse-version-keyword (keyword)
  (labels ((elements (string position)
             (let ((next (position #\- string :start (1+ position))))
               (cons (subseq string position next)
                     (when next (elements string (1+ next)))))))
    (destructuring-bind (name &rest numbers) (elements (string keyword) 0)
      (assert (and (every #'alpha-char-p name)
                   (= (length numbers) 5)))
      (cons (intern name :keyword) (mapcar #'parse-integer numbers)))))


(defun version-lessp (version1 version2)
  "Return TRUE iff VERSION1 is less than VERSION2"
  (map nil #'(lambda (e1 e2)
               (when (and (numberp e1) (numberp e2))
                 (cond ((< e1 e2)
                        (return-from version-lessp t))
                       ((> e1 e2)
                        (return-from version-lessp nil)))))
       version1 version2))



(defun amqp:initialize (&key frame-size timeout force-p)
  (assert-argument-types amqp:initialize
      (frame-size integer nil)
      (timeout integer nil))

  (when (or force-p (null *connection-classes*))
    (labels ((collect-subclasses (class)
               (dolist (class (closer-mop:class-direct-subclasses class))
                 (when (null (closer-mop:class-direct-subclasses class))
                   (push class *connection-classes*)
                   (collect-subclasses class)))))
      
      (when frame-size
        (setq *frame-size* frame-size))
      (when timeout
        (setq *connection-timeout* timeout))
      (setq *connection-classes* '())
      (collect-subclasses (find-class 'amqp:object))
      (setq *connection-classes* (sort *connection-classes* #'version-lessp
                                       :key #'class-protocol-version)))))

        

#+ignore
(defgeneric amqp:find-protocol-class (abstract-class version &key if-does-not-exist)
  (:documentation "GIven an abstract protocol class and a version,
 return the most specialized class with the highest matching version.")

  (:method ((abstract-class symbol) version &rest args)
    (apply #'amqp:find-protocol-class (find-class abstract-class) version args))

  (:method ((instance amqp:object) version &rest args)
    (apply #'amqp:find-protocol-class (class-of instance) version args))

  (:method ((abstract-class class) version &key (if-does-not-exist :error))
    (let ((found nil))
      (labels ((walk-subclasses (class)
                 (when (and (typep class 'amqp:class-class)
                            (null (closer-mop:class-direct-subclasses class)))
                   (unless (version-lessp version (class-protocol-version class))
                     (cond ((null found)
                            (setf found class))
                           ((equalp (class-protocol-version found)
                                    (class-protocol-version class))
                            ;; replace the more abstract with the more specific
                            (unless (subtypep (class-name class) (class-name found))
                              (warn "duplicate protocol implementations for version: ~s"
                                    (class-protocol-version found)))
                            (setf found class))
                           ((version-lessp (class-protocol-version found)
                                           (class-protocol-version class))
                            (setf found class)))))
                 (map nil #'walk-subclasses (closer-mop:class-direct-subclasses class))))
        (walk-subclasses abstract-class)
        (or found
            (ecase if-does-not-exist
              ((nil) nil)
              (:error (error "no protocol implementation for version: ~s" version))))))))



;;; queues
;;; corrected and extended from rhode's paper

(defclass collection ()
  ((if-empty :initform nil :initarg :if-empty :reader collection-if-empty)
   (name :initform nil :initarg :name :reader collection-name)))

(defgeneric collection-empty-p (collection))

(defclass queue (collection)
  ((header :accessor queue-header)
   (pointer :accessor queue-pointer)
   (cache :accessor queue-cache :initform nil)))

(defclass locked-queue (queue)
  ((lock :reader queue-lock
         :initform (bt:make-lock))
   (processor :accessor queue-processor
              :initform nil)))

(defclass stack (collection)
  ((data :reader stack-data)))

(defclass locked-stack (stack)
  ((lock :reader stack-lock
         :initform (bt:make-lock))))


(defmethod initialize-instance ((instance collection) &rest args
                                &key (name (with-output-to-string (stream)
                                             (print-unreadable-object (instance stream :identity t :type t)))))
  (apply #'call-next-method instance
         :name name
         args))

(defmethod print-object ((instance collection) (stream t))
  (print-unreadable-object (instance stream :identity t :type t)
    (format stream "~@[~a~]" (collection-name instance))))

(defmethod initialize-instance :after ((o queue) &key)
  (let ((head (list nil))) 
    (setf (queue-header o) head (queue-pointer o) head)))

(defmethod initialize-instance :after ((instance stack) &key)
  (with-slots (data) instance
    (setf data (make-array 32 :fill-pointer 0 :adjustable t))))

(defmethod collection-empty-p ((queue queue))
  (eq (queue-header queue) (queue-pointer queue)))

(defmethod collection-empty-p ((stack stack))
  (zerop (fill-pointer (stack-data stack))))

(defgeneric collection-content (collection)
  (:method ((collection queue))
    (rest (queue-header collection)))
  (:method ((collection stack))
    (stack-data collection)))

(defgeneric collection-size (collection)
  (:method ((collection collection))
    (length (collection-content collection))))

(defgeneric enqueue (data queue &key if-empty)
  (declare (dynamic-extent if-empty))
  (:argument-precedence-order queue data)

  #+(or) ;; this version caches the released queue cells
  (:method (data (o queue) &key if-empty)
    (declare (dynamic-extent if-empty)) 
    (if (and (eq (queue-pointer o) (queue-header o))
             if-empty)
      (funcall if-empty) 
      (let ((elt nil))
        (cond ((setf elt nil) ;;(queue-cache o))
               (setf (queue-cache o) (rest elt)
                     (car elt) data
                     (cdr elt) nil))
              (t
               (setf elt (list data)))) 
        (setf (cdr (queue-pointer o)) elt
              (queue-pointer o) elt)))
    data)

  (:method (data (o queue) &key if-empty)
    (declare (dynamic-extent if-empty) (ignore if-empty))
    (let ((elt (list data)))
      (setf (cdr (queue-pointer o)) elt
            (queue-pointer o) elt))
    data)

  (:method ((data t) (queue locked-queue) &key (if-empty (collection-if-empty queue)))
    (declare (dynamic-extent if-empty))
    (let ((lock (queue-lock queue))
          (state :released))
      (flet ((acquire-it () 
               (setf state :acquiring)
               (bt:acquire-lock lock)
               (setf state :acquired))
             (release-it ()
               (setf state :releasing)
               (bt:release-lock lock)
               (setf state :released)))
        (unwind-protect
          (loop
            (acquire-it)
            (if (collection-empty-p queue)
              ;; if there's no content, decided whether to prime the process
              ;; or just add to the queue
              (cond ((queue-processor queue)
                     ;; recursive call is allowed, simply enqueue
                     (return (call-next-method)))
                    ((null if-empty)
                     ;; simple enqueue 
                     (return (call-next-method)))
                    (t
                     ;; w/o a processor, but with a if-empty continuation, use it
                     (assert-argument-type dequeue if-empty
                                           (or function (and symbol (satisfies fboundp))))
                     (unwind-protect
                       (progn (setf (queue-processor queue) (bt:current-thread))
                              (call-next-method)
                              (release-it)
                              (return (values (funcall if-empty) t)))
                       (setf (queue-processor queue) nil))))
              ;; if the collection already has content, just enqueue
              (return (call-next-method))))
          (ecase state
            (:released )
            (:acquired (bt:release-lock lock))
            ((:acquiring :releasing)      ; maybe or maybe not
             (ignore-errors (bt:release-lock lock))))))))

  (:method (data (stack stack) &key if-empty)
    (declare (ignore if-empty))
    (vector-push-extend data (stack-data stack))
    data)

  (:method ((data t) (stack locked-stack) &rest args)
    (declare (dynamic-extent args) (ignore args))
    (bt:with-lock-held ((stack-lock stack))
      (call-next-method))))

(defgeneric dequeue (queue &key if-empty test)
  (declare (dynamic-extent if-empty))

  #+(or) ;; this version caches the released queue cells
  (:method ((queue queue) &key test if-empty)
    (declare (ignore if-empty))
    (let ((head (queue-header queue)))
      (cond ((eq head (queue-pointer queue))
             (values nil nil))
            (test
              (assert-argument-type dequeue test
                                    (or function (and symbol (satisfies fboundp))))
              (do ((head head (cdr head))
                   (ptr (cdr head) (cdr ptr)))
                  ((null ptr) (values nil nil))
                (when (funcall test (car ptr))
                  (unless (setf (cdr head) (cdr ptr))
                    (setf (queue-pointer queue) head))
                  (setf (cdr ptr) (queue-cache queue)
                     (queue-cache queue) ptr)
                  (return (values (shiftf (car ptr) nil) t)))))
            (t
             (let ((elt (cdr head)))
               (unless (setf (cdr head) (cdr elt))
                 (setf (queue-pointer queue) head))
               (setf (cdr elt) (queue-cache queue)
                     (queue-cache queue) elt)
               (values (shiftf (car elt) nil) t))))))

  (:method ((queue queue) &key test if-empty)
    (declare (ignore if-empty))
    (let ((head (queue-header queue)))
      (cond ((eq head (queue-pointer queue))
             (values nil nil))
            (test
              (assert-argument-type dequeue test
                                    (or function (and symbol (satisfies fboundp))))
              (do ((head head (cdr head))
                   (ptr (cdr head) (cdr ptr)))
                  ((null ptr) (values nil nil))
                (when (funcall test (car ptr))
                  (unless (setf (cdr head) (cdr ptr))
                    (setf (queue-pointer queue) head))
                  (return (values (car ptr) t)))))
            (t
             (let ((value (cadr head)))
               (unless (setf (cdr head) (cddr head))
                 (setf (queue-pointer queue) head))
               (values value t))))))

  (:method ((queue locked-queue) &key (if-empty (collection-if-empty queue)) test)
    (declare (dynamic-extent if-empty) 
             (ignore test))
    (let ((lock (queue-lock queue))
          (state :released))
      (flet ((acquire-it () 
               (setf state :acquiring)
               (bt:acquire-lock lock)
               (setf state :acquired))
             (release-it ()
               (setf state :releasing)
               (bt:release-lock lock)
               (setf state :released)))
        (unwind-protect
          ;; attempt to dequeue a value. if that succeeds return it. otherwise,
          ;; - if waiting, release the lock and yield in the hope one appears,
          ;;   and repeat the process upon resumption;
          ;; - if suppressed, return nil
          ;; - if provided a continuation, return its result
          (loop
            (acquire-it)
            (multiple-value-bind (value value-p)
                                 (call-next-method)
              (if value-p
                (return (values value t))
                (case if-empty
                  ((nil)
                   (return (values nil nil)))
                  (:wait
                   (when (queue-processor queue)
                     ;; if there is a processor, wait
                     (assert (not (eq (queue-processor queue) (bt:current-thread))) ()
                             "Recursive dequeue: ~s" (queue-processor queue)))
                   (release-it)
                   (loop (if (collection-empty-p queue)
                           (bt:thread-yield)
                           (return))))
                  (t
                   (assert-argument-type dequeue if-empty
                                         (or function (and symbol (satisfies fboundp))))
                   (unwind-protect
                     (progn (setf (queue-processor queue) (bt:current-thread))
                            (release-it)
                            (return (values (funcall if-empty) t)))
                     (setf (queue-processor queue) nil)))))))
          (ecase state
            (:released )
            (:acquired (bt:release-lock lock))
            ((:acquiring :releasing)      ; maybe or maybe not
             (ignore-errors (bt:release-lock lock))))))))

  (:method ((stack stack) &key (if-empty (collection-if-empty stack)) test)
    (declare (dynamic-extent if-empty)
             (ignore test))
    (let ((data (stack-data stack)))
      (if (plusp (fill-pointer data))
        (values (vector-pop data) t)
        (case if-empty
          ((nil)
           (values nil nil))
          (t
           (assert-argument-type dequeue if-empty
                                 (or function (and symbol (satisfies fboundp))))
           (values (funcall if-empty) t))))))

  (:method ((stack locked-stack) &rest args)
    (declare (dynamic-extent args) (ignore args))
    (bt:with-lock-held ((stack-lock stack))
      (call-next-method))))



#+:de.setf.utility.test
(with-test-situation (:define)
  (test:test parse-version-keyword/1 (parse-version-keyword :amqp-1-1-0-8-0)
             '(:AMQP 1 1 0 8 0))

  (test:test version-lessp/1 (version-lessp '(amqp 1 1 0 8 0) '(amqp 1 1 0 9 0)))

  (test:test queue/1 (let ((q (make-instance 'queue)))
                       (list (enqueue 1 q)
                             (dequeue q)
                             (dequeue q)
                             (enqueue 2 q)
                             (dequeue q)))
             '(1 1 NIL 2 2))
  (test:test queue/1 (let ((q (make-instance 'queue)))
                       (list (enqueue 1 q)
                             (enqueue 2 q)
                             (enqueue 1 q)
                             (dequeue q :test 'evenp)
                             (dequeue q)
                             (dequeue q)
                             (dequeue q)))
             '(1 2 1 2 1 1 nil))
  (test:test queue/2 (let ((q (make-instance 'locked-queue :name "test")))
                       (list (enqueue 1 q)
                             (dequeue q)
                             (dequeue q)
                             (enqueue 2 q)
                             (dequeue q)))
             '(1 1 NIL 2 2))
  (test:test stack/1 (let ((q (make-instance 'stack :if-empty (let ((x 0)) #'(lambda () (incf x))))))
                       (list (enqueue 'a q)
                             (dequeue q)
                             (dequeue q)
                             (enqueue 'b q)
                             (dequeue q)
                             (dequeue q)
                             (dequeue q)))
             '(A A 1 B B 2 3))
  (when bt:*supports-threads-p*
    (test:test queue/wait (let ((q (make-instance 'locked-queue :name "test")))
                            (list (enqueue 1 q)
                                  (dequeue q)
                                  (progn (bt:make-thread #'(lambda ()
                                                             (bt:thread-yield)
                                                             (enqueue :foreign q)))
                                         (dequeue q :if-empty :wait))
                                  (enqueue 2 q)
                                  (dequeue q)))))

  )

