;;; ps-task-icons.el --- A Material Symbols icon for each agenda task -*- lexical-binding: t; -*-

;;; Commentary:
;; Picks a Material Symbols icon that conveys what each agenda task is about,
;; so a glance at the icon column says what the task is without reading it.
;; The match comes from `scripts/org_task_icon_matcher.py', which runs a
;; *bundle* (`icons/task-matcher/': precomputed icon matrices plus a manifest)
;; produced by the separate task-concept-retrieval research project.  The
;; runner may answer "no icon" -- a wrong icon is worse than none.
;;
;; The manifest drives this module rather than settings here:
;;   - `query.inputs' says which task fields the model reads (the title now;
;;     parent headings and the body later), so only those are collected and
;;     sent, and a new model needs no change here;
;;   - `tag' is the cache identity: results are cached on disk keyed by the
;;     fields sent, and a bundle with a new tag discards them.
;; The title is sent with its org markup; the TODO keyword, priority and tags
;; are dropped, as they describe the task's state, not its idea.
;;
;; A warm agenda render reads only the cache and never starts Python.  After a
;; render, uncached tasks are sent to the runner asynchronously and the layout
;; is refreshed when the answers arrive.  This module owns the icon *names*;
;; `ps-agenda-layout' draws them (`ps/task-icons-name-at-point').
;;
;; Design: design/planning/task-icons.md.

;;; Code:

(require 'seq)
(require 'subr-x)

(declare-function org-get-at-bol "org" (property))
(declare-function org-get-heading "org" (&optional no-tags no-todo no-priority no-comment))
(declare-function org-get-outline-path "org" (&optional with-self use-cache))
(declare-function org-end-of-meta-data "org" (&optional full))
(declare-function org-back-to-heading "org" (&optional invisible-ok))
(declare-function org-with-point-at "org-macs" (pom &rest body))
(declare-function outline-next-heading "outline" ())
(declare-function ps/agenda-layout-refresh "ps-agenda-layout" ())
(defvar org-agenda-finalize-hook)

;;; Customization

(defgroup ps-task-icons nil
  "A Material Symbols icon for each agenda task."
  :group 'ps)

(defcustom ps/task-icons-enabled t
  "When non-nil, show an icon for each agenda task."
  :type 'boolean
  :group 'ps-task-icons)

(defcustom ps/task-icons-matcher-path
  (expand-file-name "scripts/org_task_icon_matcher.py" user-emacs-directory)
  "Path to the org_task_icon_matcher.py runner."
  :type 'file
  :group 'ps-task-icons)

(defcustom ps/task-icons-bundle-dir
  (expand-file-name "icons/task-matcher" user-emacs-directory)
  "Directory holding the matcher bundle (manifest.json and its matrices)."
  :type 'directory
  :group 'ps-task-icons)

(defcustom ps/task-icons-cache-file
  (expand-file-name "ps-task-icons/task_cache.json"
                    (expand-file-name ".cache" "~"))
  "File holding the persistent task -> icon cache."
  :type 'file
  :group 'ps-task-icons)

;;; Internal state

(defvar ps/task-icons--timer nil
  "Idle timer used to debounce icon updates in the agenda.")

(defvar ps/task-icons--process nil
  "The running matcher process, or nil.")

(defvar ps/task-icons--failed-at nil
  "Time of the last failed matcher run, or nil.
Within `ps/task-icons--retry-after' seconds of it the matcher is not restarted,
so a missing Python dependency does not respawn it on every agenda render.")

(defvar ps/task-icons--last-failure nil
  "The reason last reported for a failed run, so it is reported only once.")

(defconst ps/task-icons--retry-after 600
  "Seconds to wait after a failed matcher run before trying again.")

(defvar ps/task-icons--manifest nil
  "Cons (FILE-ATTRIBUTES-MTIME . MANIFEST) for the bundle's manifest, or nil.")

(defvar ps/task-icons--cache nil
  "Hash table mapping a task key to an icon name, or \"\" for no icon.
Nil until loaded from `ps/task-icons-cache-file'.")

(defvar ps/task-icons--cache-loaded-tag nil
  "The manifest tag `ps/task-icons--cache' was built for.")

;;; Manifest

(defun ps/task-icons--manifest ()
  "Return the bundle manifest as a hash table, or nil when there is none.
Re-read whenever the file changes, so a new bundle takes effect at once."
  (let* ((file (expand-file-name "manifest.json" ps/task-icons-bundle-dir))
         (mtime (file-attribute-modification-time (file-attributes file))))
    (cond
     ((null mtime) nil)
     ((equal mtime (car ps/task-icons--manifest)) (cdr ps/task-icons--manifest))
     (t (let ((m (ignore-errors
                   (with-temp-buffer
                     (insert-file-contents file)
                     (json-parse-buffer :object-type 'hash-table :null-object nil)))))
          (setq ps/task-icons--manifest (cons mtime m))
          m)))))

(defun ps/task-icons--tag ()
  "The bundle's cache identity, or nil."
  (when-let ((m (ps/task-icons--manifest)))
    (gethash "tag" m)))

(defun ps/task-icons--query-spec (key)
  "Value of KEY in the manifest's `query' object, or nil."
  (when-let* ((m (ps/task-icons--manifest))
              (q (gethash "query" m)))
    (gethash key q)))

(defun ps/task-icons--inputs ()
  "The task fields the model reads, as strings (default: just the title)."
  (let ((inputs (ps/task-icons--query-spec "inputs")))
    (if (and inputs (> (length inputs) 0)) (append inputs nil) '("title"))))

;;; Task fields

(defun ps/task-icons--entry-body (limit)
  "Text of the entry at point after its planning lines and drawers.
At most LIMIT characters; the runner cuts it further after normalizing."
  (save-excursion
    (org-end-of-meta-data t)
    (let ((start (point))
          (end (save-excursion (if (outline-next-heading) (point) (point-max)))))
      (string-trim
       (buffer-substring-no-properties start (min end (+ start limit)))))))

(defun ps/task-icons--task-at-marker (marker inputs)
  "The fields of the heading at MARKER that INPUTS asks for, as an alist.
Symbol keys, in a fixed order (title, parents, body), so the alist serializes
to the same JSON -- the cache key -- every time.  Nil for an empty title."
  (org-with-point-at marker
    (org-back-to-heading t)
    (let ((title (org-get-heading t t t t)))
      (when (and (stringp title) (not (string-empty-p (string-trim title))))
        (let ((task (list (cons 'title (string-trim (substring-no-properties title))))))
          (when (member "parents" inputs)
            (push (cons 'parents (vconcat (mapcar #'substring-no-properties
                                                  (org-get-outline-path))))
                  task))
          (when (member "body" inputs)
            (let ((body (ps/task-icons--entry-body
                         (* 2 (or (ps/task-icons--query-spec "body_chars") 400)))))
              (unless (string-empty-p body)
                (push (cons 'body body) task))))
          (nreverse task))))))

(defun ps/task-icons--line-task (&optional inputs)
  "The task fields for the agenda line at point, or nil for a non-task line.
INPUTS defaults to the manifest's."
  (let ((marker (or (org-get-at-bol 'org-hd-marker) (org-get-at-bol 'org-marker))))
    (when (and (markerp marker) (marker-buffer marker))
      (ps/task-icons--task-at-marker marker (or inputs (ps/task-icons--inputs))))))

(defun ps/task-icons--key (task)
  "The cache key for TASK: its fields as JSON."
  (json-serialize task))

(defun ps/task-icons--collect-tasks ()
  "The distinct tasks on the lines of the current buffer, in order."
  (let ((inputs (ps/task-icons--inputs))
        (seen (make-hash-table :test 'equal))
        tasks)
    (save-excursion
      (goto-char (point-min))
      (while (not (eobp))
        (when-let ((task (ps/task-icons--line-task inputs)))
          (let ((key (ps/task-icons--key task)))
            (unless (gethash key seen)
              (puthash key t seen)
              (push task tasks))))
        (forward-line 1)))
    (nreverse tasks)))

;;; Persistent cache

(defun ps/task-icons--cache-load ()
  "Return the key -> icon cache, loading it from disk on first use.
The cache is discarded when the bundle's tag differs from the one it was
built for."
  (let ((tag (ps/task-icons--tag)))
    (unless (and ps/task-icons--cache
                 (equal ps/task-icons--cache-loaded-tag tag))
      (setq ps/task-icons--cache-loaded-tag tag
            ps/task-icons--cache
            (let ((data (and tag (file-exists-p ps/task-icons-cache-file)
                             (ignore-errors
                               (with-temp-buffer
                                 (insert-file-contents ps/task-icons-cache-file)
                                 (json-parse-buffer :object-type 'hash-table))))))
              (if (and (hash-table-p data)
                       (equal (gethash "tag" data) tag)
                       (hash-table-p (gethash "map" data)))
                  (gethash "map" data)
                (make-hash-table :test 'equal)))))
    ps/task-icons--cache))

(defun ps/task-icons--cache-save ()
  "Persist the in-memory cache to `ps/task-icons-cache-file'."
  (when (and ps/task-icons--cache ps/task-icons--cache-loaded-tag)
    (ignore-errors
      (make-directory (file-name-directory ps/task-icons-cache-file) t)
      (let ((data (make-hash-table :test 'equal)))
        (puthash "tag" ps/task-icons--cache-loaded-tag data)
        (puthash "map" ps/task-icons--cache data)
        (with-temp-file ps/task-icons-cache-file
          (insert (json-serialize data)))))))

(defun ps/task-icons--missing (tasks)
  "The members of TASKS with no cached answer (a cached \"no icon\" counts)."
  (let ((cache (ps/task-icons--cache-load)))
    (seq-remove (lambda (task) (gethash (ps/task-icons--key task) cache)) tasks)))

(defun ps/task-icons--cache-put (key icon)
  "Cache ICON (a name, or nil for no icon) for task KEY."
  (puthash key (or icon "") (ps/task-icons--cache-load)))

;;; Lookup (consumed by ps-agenda-layout)

(defun ps/task-icons-lookup (task)
  "The cached icon name for TASK (an alist of fields), or nil."
  (when (and ps/task-icons-enabled task)
    (let ((icon (gethash (ps/task-icons--key task) (ps/task-icons--cache-load))))
      (and (stringp icon) (not (string-empty-p icon)) icon))))

(defun ps/task-icons-name-at-point ()
  "The cached icon name for the agenda line at point, or nil."
  (when (and ps/task-icons-enabled (ps/task-icons--tag))
    (ps/task-icons-lookup (ps/task-icons--line-task))))

;;; Async matcher process

(defun ps/task-icons--python ()
  "The Python 3 interpreter to run the matcher with, or nil if there is none."
  (or (executable-find "python3") (executable-find "python")))

(defun ps/task-icons--fail (reason)
  "Record a failed run because of REASON, and report it once per reason.
Tasks keep showing no icon; the matcher is retried after
`ps/task-icons--retry-after' seconds, quietly unless the reason changes."
  (setq ps/task-icons--failed-at (float-time))
  (unless (equal reason ps/task-icons--last-failure)
    (setq ps/task-icons--last-failure reason)
    (message "[task-icons] No task icons: %s" reason)))

(defun ps/task-icons--run-matcher (tasks callback)
  "Send TASKS to the matcher asynchronously; call CALLBACK with its answer.
CALLBACK receives a hash table mapping each task key to an icon name or nil.
Progress lines the runner prints (the one-time encoder download) are echoed;
when it fails, its last stderr line says why.  Never signals: a missing
interpreter or a failed start is reported through `ps/task-icons--fail'."
  (if-let ((python (ps/task-icons--python)))
      (let* ((out (generate-new-buffer " *task-icons-output*"))
             (last-error "the matcher exited without an answer")
             (stderr (make-pipe-process
                      :name "task-icons-stderr" :noquery t
                      :filter (lambda (_p text)
                                (dolist (line (split-string text "\n" t))
                                  (setq last-error line)
                                  (when (string-prefix-p "[task-icons]" line)
                                    (message "%s" line)))))))
        (condition-case err
            (ps/task-icons--start python tasks out stderr
                                  (lambda (answer)
                                    (if (hash-table-p answer)
                                        (progn (setq ps/task-icons--last-failure nil)
                                               (funcall callback answer))
                                      (ps/task-icons--fail last-error))))
          (error
           (when (buffer-live-p out) (kill-buffer out))
           (delete-process stderr)
           (setq ps/task-icons--process nil)
           (ps/task-icons--fail (error-message-string err)))))
    (ps/task-icons--fail
     "no Python 3 found (see Installation, \"Install the task-icon matcher\")")))

(defun ps/task-icons--start (python tasks out stderr done)
  "Start the matcher with PYTHON on TASKS, answering into buffer OUT.
STDERR is the pipe for its stderr.  DONE is called with the parsed answer, or
nil when the run failed."
  (setq ps/task-icons--process
        (make-process
         :name "task-icons-matcher"
         :buffer out
         :stderr stderr
         :command (list python ps/task-icons-matcher-path ps/task-icons-bundle-dir)
         :noquery t
         :connection-type 'pipe
         :sentinel
         (lambda (p _event)
           (unless (process-live-p p)
             (setq ps/task-icons--process nil)
             (let ((answer (and (zerop (process-exit-status p))
                                (buffer-live-p out)
                                (with-current-buffer out
                                  (ignore-errors
                                    (json-parse-string (buffer-string)
                                                       :object-type 'hash-table
                                                       :null-object nil))))))
               (when (buffer-live-p out) (kill-buffer out))
               ;; Let the stderr filter see the last lines before reading them.
               (accept-process-output stderr 0.1)
               (delete-process stderr)
               (funcall done answer))))))
    (process-send-string
     ps/task-icons--process
     (json-serialize
      (vconcat (mapcar (lambda (task)
                         (cons (cons 'key (ps/task-icons--key task)) task))
                       tasks))))
    (process-send-eof ps/task-icons--process))

;;; Agenda integration

(defun ps/task-icons--refresh-layout ()
  "Ask the agenda layout to redraw, so newly cached icons fill their column."
  (when (fboundp 'ps/agenda-layout-refresh)
    (ps/agenda-layout-refresh)))

(defun ps/task-icons--may-run-p ()
  "Non-nil when the matcher may be started now."
  (and (ps/task-icons--tag)
       (not (process-live-p ps/task-icons--process))
       (or (null ps/task-icons--failed-at)
           (> (- (float-time) ps/task-icons--failed-at) ps/task-icons--retry-after))))

(defun ps/task-icons--ensure ()
  "Match any uncached agenda tasks, then refresh the layout.
Cached icons are already drawn by the layout's own render; this only starts
the matcher for what is missing, and re-renders once the answers arrive."
  (when-let ((buffer (get-buffer "*Org Agenda*")))
    (with-current-buffer buffer
      (when (and ps/task-icons-enabled (ps/task-icons--may-run-p))
        (let ((missing (ps/task-icons--missing (ps/task-icons--collect-tasks))))
          (when missing
            (ps/task-icons--run-matcher
             missing
             (lambda (answer)
               (dolist (task missing)
                 (let ((key (ps/task-icons--key task)))
                   (ps/task-icons--cache-put key (gethash key answer))))
               (ps/task-icons--cache-save)
               (ps/task-icons--refresh-layout)))))))))

(defun ps/task-icons--schedule (&rest _)
  "Debounce matching any uncached tasks after the agenda renders."
  (when ps/task-icons-enabled
    (when ps/task-icons--timer
      (cancel-timer ps/task-icons--timer))
    (setq ps/task-icons--timer
          (run-with-idle-timer
           0.4 nil
           (lambda ()
             (setq ps/task-icons--timer nil)
             (ps/task-icons--ensure))))))

;;; Public API

(defun ps/task-icons-setup ()
  "Match uncached agenda tasks after each agenda render.
The layout draws the icons; this only keeps the cache warm and triggers a
refresh once new icons are available."
  (add-hook 'org-agenda-finalize-hook #'ps/task-icons--schedule))

(provide 'ps-task-icons)
;;; ps-task-icons.el ends here
