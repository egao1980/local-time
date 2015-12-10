(in-package #:local-time.test)

(defsuite* (simple :in test))

(eval-when (:compile-toplevel :load-toplevel :execute)
  (local-time::define-timezone amsterdam-tz
      (merge-pathnames #p"Europe/Amsterdam" local-time::*default-timezone-repository-path*)))

(deftest test/simple/make-timestamp ()
  (let ((timestamp (make-timestamp :nsec 1 :sec 2 :day 3)))
    (is (= (nsec-of timestamp) 1))
    (is (= (sec-of timestamp) 2))
    (is (= (day-of timestamp) 3))))

(deftest test/simple/read-binary-integer ()
  (let ((tmp-file-path #p"/tmp/local-time-test"))
    (with-open-file (ouf tmp-file-path
                         :direction :output
                         :element-type 'unsigned-byte
                         :if-exists :supersede)
      (dotimes (i 14)
        (write-byte 200 ouf)))
  (with-open-file (inf tmp-file-path :element-type 'unsigned-byte)
    (is (eql (local-time::%read-binary-integer inf 1) 200))
    (is (eql (local-time::%read-binary-integer inf 1 t) -56))
    (is (eql (local-time::%read-binary-integer inf 2) 51400))
    (is (eql (local-time::%read-binary-integer inf 2 t) -14136))
    (is (eql (local-time::%read-binary-integer inf 4) 3368601800))
    (is (eql (local-time::%read-binary-integer inf 4 t) -926365496)))))

(deftest test/simple/encode-timestamp ()
  (macrolet ((entry ((&rest encode-timestamp-args)
                     day sec nsec)
               `(let ((timestamp (encode-timestamp ,@encode-timestamp-args)))
                  (is (= (day-of timestamp) ,day))
                  (is (= (sec-of timestamp) ,sec))
                  (is (= (nsec-of timestamp) ,nsec)))))
    (entry (0 0 0 0 1 3 2000 :offset 0)
           0 0 0)
    (entry (0 0 0 0 29 2 2000 :offset 0)
           -1 0 0)
    (entry (0 0 0 0 2 3 2000 :offset 0)
           1 0 0)
    (entry (0 0 0 0 1 1 2000 :offset 0)
           -60 0 0)
    (entry (0 0 0 0 1 3 2001 :offset 0)
           365 0 0)))

(defmacro encode-decode-test (args &body body)
  `(let ((timestamp (encode-timestamp ,@(subseq args 0 7) :offset 0)))
    (is (equal '(,@args ,@(let ((stars nil))
                               (dotimes (n (- 7 (length args)))
                                 (push '* stars))
                               stars))
               (multiple-value-list
                (decode-timestamp timestamp :timezone local-time:+utc-zone+))))
    ,@body))

(deftest test/simple/encode-decode-consistency/1 ()
  (encode-decode-test (5 5 5 5 5 5 1990 6 nil 0 "UTC"))
  (encode-decode-test (0 0 0 0 1 3 2001 4 nil 0 "UTC"))
  (encode-decode-test (0 0 0 0 1 3 1998 0 nil 0 "UTC"))
  (encode-decode-test (1 2 3 4 5 6 2008 4 nil 0 "UTC"))
  (encode-decode-test (0 0 0 0 1 1 1 1 nil 0 "UTC")))

(deftest test/simple/encode-decode-consistency/random ()
  (loop :repeat 1000 :do
    (let ((timestamp (make-timestamp :day (- (random 65535) 36767)
                                     :sec (random 86400)
                                     :nsec (random 1000000000))))
      (multiple-value-bind (ns ss mm hh day month year)
          (decode-timestamp timestamp :timezone local-time:+utc-zone+)
        (is (timestamp= timestamp
                        (encode-timestamp ns ss mm hh day month year :offset 0)))))))

;;;;;;
;;; TODO the rest is uncategorized, just simply converted from the old 5am suite

(deftest test/timestamp-conversions ()
  (is (eql 0 (timestamp-to-unix
              (encode-timestamp 0 0 0 0 1 1 1970 :offset 0))))
  (is (equal (values 2 3 4 5 6 2008 3 * *)
             (decode-universal-time
              (timestamp-to-universal
               (encode-timestamp 1 2 3 4 5 6 2008 :offset 0)) 0)))
  (let ((now (now)))
    (setf (nsec-of now) 0)
    (is (timestamp= now
                     (unix-to-timestamp (timestamp-to-unix now)))))
  (let ((now (get-universal-time)))
    (is (equal now
               (timestamp-to-universal (universal-to-timestamp now))))))

(deftest test/year-difference ()
  (let ((a (parse-timestring "2006-01-01T00:00:00"))
        (b (parse-timestring "2001-01-01T00:00:00")))
    (is (= 5 (timestamp-whole-year-difference a b))))

  (let ((a (parse-timestring "2006-01-01T00:00:00"))
        (b (parse-timestring "2001-01-02T00:00:00")))
    (is (= 4 (timestamp-whole-year-difference a b))))
  
  (let* ((local-time::*default-timezone* amsterdam-tz)
         (a (parse-timestring "1978-10-01")))
    (is (= 0 (timestamp-whole-year-difference a a)))))

(deftest test/adjust-timestamp/bug1 ()
  (let* ((timestamp (parse-timestring "2006-01-01T00:00:00Z"))
         (modified-timestamp (adjust-timestamp timestamp (timezone +utc-zone+) (offset :year 1))))
    (is (timestamp= (parse-timestring "2007-01-01T00:00:00Z") modified-timestamp))))

(deftest test/adjust-timestamp/bug2 ()
  (let* ((timestamp (parse-timestring "2009-03-01T01:00:00.000000+00:00"))
         (modified-timestamp (adjust-timestamp timestamp (timezone +utc-zone+) (offset :month 1))))
    (is (timestamp= (parse-timestring "2009-04-01T01:00:00.000000+00:00") modified-timestamp))))

(deftest test/adjust-timestamp/bug3 ()
  (let* ((timestamp (parse-timestring "2009-03-01T01:00:00.000000+00:00"))
         (modified-timestamp (adjust-timestamp timestamp (timezone +utc-zone+) (offset :day-of-week :monday))))
    (is (timestamp= (parse-timestring "2009-02-23T01:00:00.000000+00:00") modified-timestamp)))
  (let* ((timestamp (parse-timestring "2009-03-04T01:00:00.000000+00:00"))
         (modified-timestamp (adjust-timestamp timestamp (timezone +utc-zone+) (offset :day-of-week :monday))))
    (is (timestamp= (parse-timestring "2009-03-02T01:00:00.000000+00:00") modified-timestamp))))

(deftest test/adjust-timestamp/bug4 ()
  (let* ((timestamp (parse-timestring "2013-04-30T00:00:00.000000+00:00"))
         (modified-timestamp (adjust-timestamp timestamp (timezone +utc-zone+) (offset :day-of-week :wednesday))))
    (is (timestamp= (parse-timestring "2013-05-01T00:00:00.000000+00:00") modified-timestamp)))
  (let* ((timestamp (parse-timestring "2013-12-31T00:00:00.000000+00:00"))
         (modified-timestamp (adjust-timestamp timestamp (timezone +utc-zone+) (offset :day-of-week :wednesday))))
    (is (timestamp= (parse-timestring "2014-01-01T00:00:00.000000+00:00") modified-timestamp))))

#+nil
(deftest test/adjust-days ()
  (let ((sunday (parse-timestring "2006-12-17T01:02:03Z")))
    (is (timestamp= (parse-timestring "2006-12-11T01:02:03Z")
                     (adjust-timestamp sunday (offset :day-of-week :monday))))
    (is (timestamp= (parse-timestring "2006-12-20T01:02:03Z")
                     (adjust-timestamp sunday (offset :day 3))))))

(deftest test/decode-date ()
  (loop
    :for (total-day year month day) :in '((-1 2000 02 29)
                                          (0 2000 03 01)
                                          (1 2000 03 02)
                                          (364 2001 02 28)
                                          (365 2001 03 01)
                                          (366 2001 03 02)
                                          (#.(* 2 365) 2002 03 01)
                                          (#.(* 4 365) 2004 02 29)
                                          (#.(1+ (* 4 365)) 2004 03 01))
    :do (multiple-value-bind (year* month* day*)
            (local-time::%timestamp-decode-date total-day)
          (is (= year year*))
          (is (= month month*))
          (is (= day day*)))))

(deftest test/timestamp-decoding-readers ()
  (let ((*default-timezone* +utc-zone+))
    (dolist (year '(1900 1975 1999 2000 2001 2002 2003 2004 2005 2006 2007 2008 2009 2010))
      (dolist (month '(1 2 3 4 5 6 7 8 9 10 11 12))
        (dolist (day '(1 2 3 27 28 29 30 31))
          (when (valid-date-tuple? year month day)
            (let ((hour (random 24))
                  (min (random 60))
                  (sec (random 60))
                  (nsec (random 1000000000)))
              (let ((time (encode-timestamp nsec sec min hour day month year :offset 0)))
                (is (= (floor year 10) (timestamp-decade time)))
                (is (= year (timestamp-year time)))
                (is (= month (timestamp-month time)))
                (is (= day (timestamp-day time)))
                (is (= hour (timestamp-hour time)))
                (is (= min (timestamp-minute time)))
                (is (= sec (timestamp-second time)))
                (is (= (floor nsec 1000000)
                       (timestamp-millisecond time)))
                (is (= (floor nsec 1000)
                       (timestamp-microsecond time)))))))))))

(deftest test/timestamp-century ()
  (let ((*default-timezone* +utc-zone+))
    (dolist (year-data '((-101 -2)
                         (-100 -1)
                         (-1 -1)
                         (1 1)
                         (100 1)
                         (101 2)
                         (1999 20)
                         (2000 20)
                         (2001 21)))
      (let ((time (encode-timestamp 0 0 0 0 1 1 (first year-data) :offset 0)))
        (is (= (second year-data) (timestamp-century time)))))))

(deftest test/timestamp-millennium ()
  (let ((*default-timezone* +utc-zone+))
    (dolist (year-data '((-101 -1)
                         (-100 -1)
                         (-1 -1)
                         (1 1)
                         (100 1)
                         (101 1)
                         (1001 2)
                         (1999 2)
                         (2000 2)
                         (2001 3)))
      (let ((time (encode-timestamp 0 0 0 0 1 1 (first year-data) :offset 0)))
        (is (= (second year-data) (timestamp-millennium time)))))))

(defun valid-date-tuple? (year month day)
  ;; it works only on the gregorian calendar
  (let ((month-days #(31 28 31 30 31 30 31 31 30 31 30 31)))
    (and (<= 1 month 12)
         (<= 1 day (+ (aref month-days (1- month))
                      (if (and (= month 2)
                               (zerop (mod year 4))
                               (not (zerop (mod year 100)))
                               (zerop (mod year 400)))
                          1
                          0))))))

(deftest test/encode-decode-timestamp ()
  (let ((*default-timezone* +utc-zone+))
    (loop for year :in '(1900 1975 1999 2000 2001 2002 2003 2004 2005 2006 2007 2008 2009 2010) do
          (loop for month :from 1 :to 12 do
                (loop for day :in '(1 2 3 27 28 29 30 31) do
                      (when (valid-date-tuple? year month day)
                        (multiple-value-bind (nsec sec minute hour day* month* year* day-of-week)
                            (decode-timestamp (encode-timestamp 0 0 0 0 day month year :offset 0))
                          (declare (ignore nsec sec minute day-of-week))
                          (is (= hour 0))
                          (is (= year year*))
                          (is (= month month*))
                          (is (= day day*)))))))))

(deftest test/timestamp-maximize-part ()
  (timestamp= (timestamp-maximize-part
               (encode-timestamp 0 49 26 13 9 12 2010 :offset -18000)
               :min)
              (encode-timestamp 999999999 59 59 13 9 12 2010 :offset -18000)))

(deftest test/timestamp-minimize-part ()
  (timestamp= (timestamp-minimize-part
               (encode-timestamp 0 49 26 13 9 12 2010 :offset -18000)
               :min)
              (encode-timestamp 0 0 0 13 9 12 2010 :offset -18000)))
