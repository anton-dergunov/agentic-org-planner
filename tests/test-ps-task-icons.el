;;; test-ps-task-icons.el --- ERT tests for ps-task-icons -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)
(require 'org)
(add-to-list 'load-path "lisp")
(require 'ps-task-icons)

;; Declare special so a `let' binding below is dynamic (org-agenda may be
;; unloaded in batch, leaving the symbol otherwise lexical here).
(defvar org-agenda-finalize-hook)
(defvar my-org-base-directory)

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
          (ps/task-icons--cache-loaded-tag nil)
          ;; No vault, so a cache save writes no vault copy anywhere real.
          (my-org-base-directory nil))
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

;;; -------------------------------------------------------
;;; vault copy (read by Rumbo)
;;; -------------------------------------------------------

(defmacro ps/task-icons-test--with-vault (files &rest body)
  "Run BODY with a temporary vault holding FILES, an alist (NAME . TEXT).
Binds `vault-file' to the vault copy's path.  Buffers visited in the vault are
killed afterwards."
  (declare (indent 1))
  `(let* ((vault (file-name-as-directory (make-temp-file "task-icons-vault" t)))
          (my-org-base-directory vault)
          (ps/org-files-root nil)
          (ps/task-icons-enabled t)
          (ps/task-icons--export-last-failure nil)
          (ps/task-icons--failed-at nil)
          (vault-file (expand-file-name ".ps/task-icons.json" vault)))
     (ignore vault-file)
     (unwind-protect
         (progn
           (pcase-dolist (`(,name . ,text) ,files)
             (let ((file (expand-file-name name vault)))
               (make-directory (file-name-directory file) t)
               (with-temp-file file (insert text))))
           ,@body)
       (dolist (buffer (buffer-list))
         (when (and (buffer-file-name buffer)
                    (string-prefix-p vault (buffer-file-name buffer)))
           (with-current-buffer buffer (set-buffer-modified-p nil))
           (kill-buffer buffer)))
       (delete-directory vault t))))

(defun ps/task-icons-test--read-json (file)
  "FILE parsed as JSON, as hash tables."
  (with-temp-buffer
    (let ((coding-system-for-read 'utf-8-unix)) (insert-file-contents file))
    (json-parse-buffer :object-type 'hash-table)))

(defun ps/task-icons-test--map-keys (file)
  "The sorted keys of FILE's `map'."
  (sort (hash-table-keys (gethash "map" (ps/task-icons-test--read-json file)))
        #'string<))

(defconst ps/task-icons-test--vault-a
  '(("Health.org" . "* Health\n** TODO See the dentist\n** DONE Get a flu shot\n")
    ("Plans/Events.org" . "* Events\n** Concert in the park\n")
    ("Archive/Old.org" . "* Health\n** TODO Archived task\n"))
  "A vault: two scanned files and one archived (excluded) file.")

(defun ps/task-icons-test--put (title parents icon)
  "Cache ICON for the task TITLE under PARENTS (a list); return its key."
  (let ((key (ps/task-icons--key `((title . ,title) (parents . ,(vconcat parents))))))
    (ps/task-icons--cache-put key icon)
    key))

(ert-deftest ps/task-icons--vault-json-format ()
  "One entry per line, sorted by key, \"\" kept, LF-terminated."
  (let ((map (make-hash-table :test 'equal)))
    (puthash "{\"title\":\"B\"}" "" map)
    (puthash "{\"title\":\"A\"}" "savings" map)
    (should (equal (ps/task-icons--vault-json "t" '("title") map)
                   (concat "{\"tag\":\"t\",\"inputs\":[\"title\"],\"map\":{\n"
                           "\"{\\\"title\\\":\\\"A\\\"}\":\"savings\",\n"
                           "\"{\\\"title\\\":\\\"B\\\"}\":\"\"}}\n")))))

(ert-deftest ps/task-icons--vault-json-roundtrips ()
  "The text parses back to the same tag, inputs and map, non-ASCII included."
  (let ((map (make-hash-table :test 'equal))
        (key (ps/task-icons--key ps/task-icons-test--non-ascii)))
    (puthash key "vaccines" map)
    (puthash "{\"title\":\"Nothing fits\"}" "" map)
    (let* ((text (ps/task-icons--vault-json "t" '("title" "parents") map))
           (data (json-parse-string text :object-type 'hash-table)))
      (should (multibyte-string-p text))
      (should (= (length (split-string text "\n" t)) 3))
      (should (equal (gethash "tag" data) "t"))
      (should (equal (gethash "inputs" data) ["title" "parents"]))
      (should (equal (gethash key (gethash "map" data)) "vaccines"))
      (should (equal (gethash "{\"title\":\"Nothing fits\"}" (gethash "map" data)) "")))))

(ert-deftest ps/task-icons--vault-json-empty-map ()
  "An empty map is still valid JSON."
  (let ((text (ps/task-icons--vault-json "t" '("title") (make-hash-table :test 'equal))))
    (should (equal text "{\"tag\":\"t\",\"inputs\":[\"title\"],\"map\":{\n}}\n"))
    (should (= (hash-table-count
                (gethash "map" (json-parse-string text :object-type 'hash-table)))
               0))))

(ert-deftest ps/task-icons--vault-export-only-this-vault ()
  "Only entries for headings in this vault's scanned files are written:
another vault's task, a deleted task, the same title under another parent and
an archived task are all left out; DONE and plain headings stay in."
  (ps/task-icons-test--with-bundle (ps/task-icons-test--manifest "t" "title" "parents")
    (ps/task-icons-test--with-vault ps/task-icons-test--vault-a
      (let ((keep (list (ps/task-icons-test--put "See the dentist" '("Health") "dentistry")
                        (ps/task-icons-test--put "Get a flu shot" '("Health") "vaccines")
                        (ps/task-icons-test--put "Concert in the park" '("Events") ""))))
        (ps/task-icons-test--put "Secret task of another vault" '("Work") "lock")
        (ps/task-icons-test--put "Deleted task" '("Health") "delete")
        (ps/task-icons-test--put "See the dentist" '("Elsewhere") "dentistry")
        (ps/task-icons-test--put "Archived task" '("Health") "archive")
        (should (ps/task-icons-vault-export))
        (should (equal (ps/task-icons-test--map-keys vault-file)
                       (sort (copy-sequence keep) #'string<)))
        (let ((data (ps/task-icons-test--read-json vault-file)))
          (should (equal (gethash "tag" data) "t"))
          (should (equal (gethash "inputs" data) ["title" "parents"]))
          (should (equal (gethash (car (last keep)) (gethash "map" data)) "")))))))

(ert-deftest ps/task-icons--vault-export-keys-match-agenda ()
  "A key in the copy is the key the agenda builds for the same heading."
  (ps/task-icons-test--with-bundle (ps/task-icons-test--manifest "t" "title" "parents")
    (ps/task-icons-test--with-vault
        '(("Teeth.org" . "* Teeth [1/2]\n** TODO [#A] Book a *dentist* appointment   :phone:\n"))
      (let ((key (with-current-buffer
                     (find-file-noselect (expand-file-name "Teeth.org" vault))
                   (goto-char (point-min))
                   (re-search-forward "Book")
                   (ps/task-icons--key
                    (ps/task-icons--task-at-marker (point-marker) '("title" "parents"))))))
        (should (equal key "{\"title\":\"Book a *dentist* appointment\",\"parents\":[\"Teeth\"]}"))
        (ps/task-icons--cache-put key "dentistry")
        (ps/task-icons-vault-export)
        (should (equal (ps/task-icons-test--map-keys vault-file) (list key)))))))

(ert-deftest ps/task-icons--vault-export-skips-unchanged ()
  "Exporting the same content again does not touch the file."
  (ps/task-icons-test--with-bundle (ps/task-icons-test--manifest "t" "title" "parents")
    (ps/task-icons-test--with-vault ps/task-icons-test--vault-a
      (ps/task-icons-test--put "See the dentist" '("Health") "dentistry")
      (should (ps/task-icons-vault-export))
      (set-file-times vault-file (time-subtract (current-time) 1000))
      (let ((before (file-attribute-modification-time (file-attributes vault-file))))
        (should-not (ps/task-icons-vault-export))
        (should (time-equal-p before (file-attribute-modification-time
                                      (file-attributes vault-file)))))
      ;; A changed icon is written.
      (ps/task-icons-test--put "See the dentist" '("Health") "medical_services")
      (should (ps/task-icons-vault-export)))))

(ert-deftest ps/task-icons--vault-export-renames-into-place ()
  "The copy is written to a temporary file in .ps/ and renamed over the old one."
  (ps/task-icons-test--with-bundle (ps/task-icons-test--manifest "t" "title" "parents")
    (ps/task-icons-test--with-vault ps/task-icons-test--vault-a
      (ps/task-icons-test--put "See the dentist" '("Health") "dentistry")
      (let ((rename (symbol-function 'rename-file))
            (renames '()))
        (cl-letf (((symbol-function 'rename-file)
                   (lambda (from to &optional ok)
                     (push (list from to) renames)
                     (funcall rename from to ok))))
          (should (ps/task-icons-vault-export)))
        (should (= (length renames) 1))
        (pcase-let ((`(,from ,to) (car renames)))
          (should (equal to vault-file))
          (should (equal (file-name-directory from) (file-name-directory vault-file)))
          (should-not (file-exists-p from)))
        (should (equal (directory-files (file-name-directory vault-file) nil "\\`[^.]\\|\\`\\.[^.]")
                       '("task-icons.json")))))))

(ert-deftest ps/task-icons--vault-export-failure-is-quiet ()
  "A failed write keeps the old file, leaves no temporary file, never signals,
is reported once, and does not hold back the matcher."
  (ps/task-icons-test--with-bundle (ps/task-icons-test--manifest "t" "title" "parents")
    (ps/task-icons-test--with-vault ps/task-icons-test--vault-a
      (ps/task-icons-test--put "See the dentist" '("Health") "dentistry")
      (ps/task-icons-vault-export)
      (let ((old (with-temp-buffer (insert-file-contents vault-file) (buffer-string)))
            (messages '()))
        (ps/task-icons-test--put "See the dentist" '("Health") "medical_services")
        (cl-letf (((symbol-function 'rename-file)
                   (lambda (&rest _) (error "Disk full")))
                  ((symbol-function 'message)
                   (lambda (fmt &rest args) (push (apply #'format fmt args) messages))))
          (should-not (ps/task-icons-vault-export))
          (should-not (ps/task-icons-vault-export)))
        (should (equal old (with-temp-buffer (insert-file-contents vault-file) (buffer-string))))
        (should (equal (directory-files (file-name-directory vault-file) nil "\\`[^.]\\|\\`\\.[^.]")
                       '("task-icons.json")))
        (should (= (length messages) 1))
        (should (string-match-p "Disk full" (car messages)))
        (should (null ps/task-icons--failed-at))))))

(ert-deftest ps/task-icons--vault-export-needs-a-vault ()
  "Without an open vault, or with the feature off, nothing is written."
  (ps/task-icons-test--with-bundle (ps/task-icons-test--manifest "t")
    (ps/task-icons--cache-put "{\"title\":\"A\"}" "savings")
    (should-not (ps/task-icons-vault-export)))
  (ps/task-icons-test--with-bundle (ps/task-icons-test--manifest "t" "title" "parents")
    (ps/task-icons-test--with-vault ps/task-icons-test--vault-a
      (let ((ps/task-icons-enabled nil))
        (should-not (ps/task-icons-vault-export))
        (should-not (file-exists-p vault-file))))))

(ert-deftest ps/task-icons--cache-save-writes-vault-copy ()
  "Saving the cache also refreshes the vault copy."
  (ps/task-icons-test--with-bundle (ps/task-icons-test--manifest "t" "title" "parents")
    (ps/task-icons-test--with-vault ps/task-icons-test--vault-a
      (ps/task-icons-test--put "See the dentist" '("Health") "dentistry")
      (ps/task-icons--cache-save)
      (should (= (length (ps/task-icons-test--map-keys vault-file)) 1)))))

;;; test-ps-task-icons.el ends here
