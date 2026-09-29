;;; test-ps-task-icons.el --- ERT tests for ps-task-icons -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)
(require 'org)
(add-to-list 'load-path "lisp")
(require 'ps-task-icons)

;; Declare special so a `let' binding below is dynamic (org-agenda may be
;; unloaded in batch, leaving the symbol otherwise lexical here).
(defvar org-agenda-finalize-hook)

;;; Helpers

(defmacro ps/task-icons-test--with-bundle (manifest &rest body)
  "Run BODY with a temporary bundle whose manifest.json is MANIFEST (a string).
The cache, its file and the manifest memo are fresh for BODY."
  (declare (indent 1))
  `(let* ((dir (make-temp-file "task-icons-bundle" t))
          (ps/task-icons-bundle-dir dir)
          (ps/task-icons-cache-file (expand-file-name "cache.json" dir))
          (ps/task-icons--manifest nil)
          (ps/task-icons--cache nil)
          (ps/task-icons--cache-loaded-tag nil))
     (unwind-protect
         (progn
           (with-temp-file (expand-file-name "manifest.json" dir) (insert ,manifest))
           ,@body)
       (delete-directory dir t))))

(defun ps/task-icons-test--manifest (tag &rest inputs)
  "A manifest string with TAG and query INPUTS."
  (json-serialize `((tag . ,tag)
                    (query . ((inputs . ,(vconcat (or inputs '("title"))))
                              (body_chars . 400))))))

(defmacro ps/task-icons-test--in-org (text &rest body)
  "Run BODY in an Org buffer holding TEXT, with point on the heading `Target'."
  (declare (indent 1))
  `(with-temp-buffer
     (insert ,text)
     (org-mode)
     (goto-char (point-min))
     (re-search-forward "Target")
     (beginning-of-line)
     ,@body))

;;; -------------------------------------------------------
;;; defcustom / API
;;; -------------------------------------------------------

(ert-deftest ps/task-icons--matcher-path-is-runner ()
  "The matcher path defcustom points at the runner script."
  (should (string-suffix-p "org_task_icon_matcher.py" ps/task-icons-matcher-path)))

(ert-deftest ps/task-icons--setup-adds-hook ()
  "setup registers the scheduler on org-agenda-finalize-hook."
  (let ((org-agenda-finalize-hook nil))
    (ps/task-icons-setup)
    (should (memq 'ps/task-icons--schedule org-agenda-finalize-hook))))

(ert-deftest ps/task-icons--schedule-noop-when-disabled ()
  "With the feature disabled, the finalize hook schedules no work."
  (let ((ps/task-icons-enabled nil)
        (ps/task-icons--timer nil))
    (ps/task-icons--schedule)
    (should (null ps/task-icons--timer))))

(ert-deftest ps/task-icons--schedule-arms-timer-when-enabled ()
  "With the feature enabled, the finalize hook arms the debounce timer."
  (let ((ps/task-icons-enabled t)
        (ps/task-icons--timer nil))
    (unwind-protect
        (progn
          (ps/task-icons--schedule)
          (should (timerp ps/task-icons--timer)))
      (when ps/task-icons--timer
        (cancel-timer ps/task-icons--timer)
        (setq ps/task-icons--timer nil)))))

;;; -------------------------------------------------------
;;; manifest
;;; -------------------------------------------------------

(ert-deftest ps/task-icons--manifest-drives-tag-and-inputs ()
  "The tag and the inputs are read from the bundle's manifest."
  (ps/task-icons-test--with-bundle (ps/task-icons-test--manifest "t1" "title" "body")
    (should (equal (ps/task-icons--tag) "t1"))
    (should (equal (ps/task-icons--inputs) '("title" "body")))))

(ert-deftest ps/task-icons--manifest-reread-when-changed ()
  "A replaced manifest is picked up without restarting."
  (ps/task-icons-test--with-bundle (ps/task-icons-test--manifest "old")
    (should (equal (ps/task-icons--tag) "old"))
    (let ((file (expand-file-name "manifest.json" ps/task-icons-bundle-dir)))
      (with-temp-file file (insert (ps/task-icons-test--manifest "new")))
      (set-file-times file (time-add (current-time) 10)))
    (should (equal (ps/task-icons--tag) "new"))))

(ert-deftest ps/task-icons--no-bundle-means-no-tag ()
  "Without a manifest there is no tag, the inputs default to the title, and
no icon is looked up."
  (let ((ps/task-icons-bundle-dir (make-temp-file "no-bundle" t))
        (ps/task-icons--manifest nil))
    (unwind-protect
        (progn
          (should (null (ps/task-icons--tag)))
          (should (equal (ps/task-icons--inputs) '("title"))))
      (delete-directory ps/task-icons-bundle-dir t))))

;;; -------------------------------------------------------
;;; task fields
;;; -------------------------------------------------------

(defconst ps/task-icons-test--org
  "* Project *Alpha*
** TODO [#A] Read the /Target/ paper [1/3]   :online:
SCHEDULED: <2026-05-21 Thu>
:PROPERTIES:
:ID: 1234
:END:
Reproduce the results.
** TODO Next task
")

(ert-deftest ps/task-icons--task-title-only ()
  "The title keeps its markup and drops keyword, priority and tags."
  (ps/task-icons-test--in-org ps/task-icons-test--org
    (should (equal (ps/task-icons--task-at-marker (point-marker) '("title"))
                   '((title . "Read the /Target/ paper [1/3]"))))))

(ert-deftest ps/task-icons--task-with-parents-and-body ()
  "Parents and body are collected only when asked for; the body skips the
planning line and drawers."
  (ps/task-icons-test--in-org ps/task-icons-test--org
    (let ((task (ps/task-icons--task-at-marker (point-marker)
                                                '("title" "parents" "body"))))
      (should (equal (mapcar #'car task) '(title parents body)))
      (should (equal (alist-get 'parents task) ["Project *Alpha*"]))
      (should (equal (alist-get 'body task) "Reproduce the results.")))))

(ert-deftest ps/task-icons--key-is-json-of-fields ()
  "The cache key is the JSON of the fields, in their fixed order."
  (should (equal (ps/task-icons--key '((title . "A")))
                 "{\"title\":\"A\"}"))
  (should (equal (ps/task-icons--key '((title . "A") (parents . ["P"])))
                 "{\"title\":\"A\",\"parents\":[\"P\"]}")))

(defconst ps/task-icons-test--non-ascii
  '((title . "Hepatitis A: second dose — window lapsed") (parents . ["Здоровье"]))
  "A task whose fields are not plain ASCII.")

(ert-deftest ps/task-icons--key-non-ascii-is-text ()
  "A non-ASCII key is a text string that serializes again for the matcher."
  (let ((key (ps/task-icons--key ps/task-icons-test--non-ascii)))
    (should (multibyte-string-p key))
    (should (string-match-p "—" key))
    (should (json-serialize
             (vector (cons (cons 'key key) ps/task-icons-test--non-ascii))))))

(ert-deftest ps/task-icons--cache-roundtrip-non-ascii ()
  "A non-ASCII key is found again after the cache is saved and reloaded."
  (ps/task-icons-test--with-bundle (ps/task-icons-test--manifest "t")
    (ps/task-icons--cache-put (ps/task-icons--key ps/task-icons-test--non-ascii) "vaccines")
    (ps/task-icons--cache-save)
    (setq ps/task-icons--cache nil)
    (let ((ps/task-icons-enabled t))
      (should (equal (ps/task-icons-lookup ps/task-icons-test--non-ascii) "vaccines")))))

(ert-deftest ps/task-icons--collect-tasks-dedupes ()
  "Repeated tasks (e.g. a task shown in two sections) are sent once."
  (with-temp-buffer
    (insert "A\n\nB\nA\n")
    (cl-letf (((symbol-function 'ps/task-icons--inputs) (lambda () '("title")))
              ((symbol-function 'ps/task-icons--line-task)
               (lambda (&optional _inputs)
                 (let ((s (string-trim (buffer-substring-no-properties
                                        (line-beginning-position) (line-end-position)))))
                   (unless (string-empty-p s) `((title . ,s)))))))
      (should (equal (ps/task-icons--collect-tasks)
                     '(((title . "A")) ((title . "B"))))))))

;;; -------------------------------------------------------
;;; cache
;;; -------------------------------------------------------

(ert-deftest ps/task-icons--missing-counts-no-icon-as-cached ()
  "A cached \"no icon\" answer is not asked for again."
  (ps/task-icons-test--with-bundle (ps/task-icons-test--manifest "t")
    (ps/task-icons--cache-put (ps/task-icons--key '((title . "Known"))) "savings")
    (ps/task-icons--cache-put (ps/task-icons--key '((title . "Nothing fits"))) nil)
    (should (equal (ps/task-icons--missing '(((title . "Known"))
                                             ((title . "Nothing fits"))
                                             ((title . "Fresh"))))
                   '(((title . "Fresh")))))))

(ert-deftest ps/task-icons--cache-roundtrip ()
  "Saving then reloading preserves icons and no-icon answers."
  (ps/task-icons-test--with-bundle (ps/task-icons-test--manifest "t")
    (ps/task-icons--cache-put "k1" "savings")
    (ps/task-icons--cache-put "k2" nil)
    (ps/task-icons--cache-save)
    (setq ps/task-icons--cache nil)
    (let ((cache (ps/task-icons--cache-load)))
      (should (equal (gethash "k1" cache) "savings"))
      (should (equal (gethash "k2" cache) ""))
      (should (null (gethash "k3" cache))))))

(ert-deftest ps/task-icons--new-tag-invalidates-cache ()
  "A bundle with a new tag discards the cached answers."
  (ps/task-icons-test--with-bundle (ps/task-icons-test--manifest "old")
    (ps/task-icons--cache-put "k1" "savings")
    (ps/task-icons--cache-save)
    (let ((file (expand-file-name "manifest.json" ps/task-icons-bundle-dir)))
      (with-temp-file file (insert (ps/task-icons-test--manifest "new")))
      (set-file-times file (time-add (current-time) 10)))
    (should (= (hash-table-count (ps/task-icons--cache-load)) 0))))

;;; -------------------------------------------------------
;;; lookup (consumed by ps-agenda-layout)
;;; -------------------------------------------------------

(ert-deftest ps/task-icons--lookup ()
  "lookup gives the icon name, and nil for no icon, unknown or disabled."
  (ps/task-icons-test--with-bundle (ps/task-icons-test--manifest "t")
    (ps/task-icons--cache-put (ps/task-icons--key '((title . "Known"))) "savings")
    (ps/task-icons--cache-put (ps/task-icons--key '((title . "Nothing fits"))) nil)
    (let ((ps/task-icons-enabled t))
      (should (equal (ps/task-icons-lookup '((title . "Known"))) "savings"))
      (should (null (ps/task-icons-lookup '((title . "Nothing fits")))))
      (should (null (ps/task-icons-lookup '((title . "Absent"))))))
    (let ((ps/task-icons-enabled nil))
      (should (null (ps/task-icons-lookup '((title . "Known"))))))))

;;; -------------------------------------------------------
;;; failure handling
;;; -------------------------------------------------------

(ert-deftest ps/task-icons--no-python-fails-quietly ()
  "Without Python the run does not signal, backs off, and says why once."
  (let ((ps/task-icons--failed-at nil)
        (ps/task-icons--last-failure nil)
        (messages '()))
    (cl-letf (((symbol-function 'ps/task-icons--python) #'ignore)
              ((symbol-function 'message)
               (lambda (fmt &rest args) (push (apply #'format fmt args) messages))))
      (ps/task-icons--run-matcher '(((title . "A"))) #'ignore)
      (ps/task-icons--run-matcher '(((title . "A"))) #'ignore))
    (should ps/task-icons--failed-at)
    (should-not (ps/task-icons--may-run-p))
    (should (= (length messages) 1))
    (should (string-match-p "no Python 3 found" (car messages)))))

(ert-deftest ps/task-icons--failed-start-cleans-up ()
  "A matcher that cannot start leaves no process behind and is reported."
  (let ((ps/task-icons--failed-at nil)
        (ps/task-icons--last-failure nil)
        (ps/task-icons--process nil)
        (before (length (process-list))))
    (cl-letf (((symbol-function 'ps/task-icons--python) (lambda () "/nonexistent/python3"))
              ((symbol-function 'message) #'ignore))
      (ps/task-icons--run-matcher '(((title . "A"))) #'ignore))
    (should ps/task-icons--failed-at)
    (should (null ps/task-icons--process))
    (should (= (length (process-list)) before))))

;;; test-ps-task-icons.el ends here
