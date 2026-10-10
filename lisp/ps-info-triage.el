;;; ps-info-triage.el --- Work the info-triage inbox from Emacs -*- lexical-binding: t; -*-

;;; Commentary:
;; The daily loop for the separate `agent-context-pipeline' project (its
;; checkout is named by `ps/info-triage-sync-script'): material forwarded to
;; Telegram is extracted on a NAS, `sync.sh' pulls it to ~/info-triage-inbox/
;; as one directory per item,
;; and two generated views describe them -- `triage.md' for the routing agent
;; and `triage.org' for the person.  This module is the person's half: sync,
;; read the queue, follow an item into its artifacts, drop what is not worth
;; keeping, and repeat.
;;
;; Three things here are load-bearing.
;;
;; The queue is READ-ONLY, and not out of caution: `triage.org' is regenerated
;; wholesale on every sync, so anything typed into it is lost.  Making that
;; explicit also frees the single-key bindings below, which is what makes the
;; buffer feel like Dired rather than like a file that must not be touched.
;;
;; The item's directory is parsed back out of its `directory' link.  That link
;; is the only place the id appears now that the property drawer is gone (see
;; `render_org' in the project's info_triage/sync.py), so its shape is a
;; contract between the two repositories and `ps/info-triage--item-directory'
;; is the one place this side depends on it.  The queue's outline shape is part
;; of the same contract: a level-one heading per day, items under it at level
;; two, and the number in an item's heading global across the days.
;;
;; Dropping an item regenerates BOTH views before reverting.  `triage.md' and
;; `triage.org' number their items positionally and independently, and the whole
;; interface between the two halves is that the numbers agree: the user reads a
;; number here and quotes it to an agent that reads the other file.  Removing a
;; directory renumbers everything after it, so the views must be rebuilt
;; together -- which is what `sync.sh --regenerate' exists for.
;;
;; A sync is watched by reading the script's own output, which makes two more
;; line shapes part of the contract with info_triage/sync.py: `==> Stage' opens
;; a stage (`synchronize' and the annotation passes print these), and
;; `    [3/12] label' counts through one (`_progress', which prints a line per
;; item when its output is not a terminal -- so the process must stay on a pipe,
;; never a pty).  `ps/info-triage--parse-progress' is the one place that reads
;; them.  The state they build is drawn twice from one label function: in full
;; on the queue's header line, and as a marker of a few characters in the file
;; tree's mode line, which is on screen whatever buffer is selected.  The echo
;; area is not enough on its own -- the next keystroke wipes it, and a sync
;; outlasts that by minutes.
;;
;; On macOS the script's `ssh' to the server is attributed to Emacs, so it is
;; Emacs that needs Local Network access (System Settings, Privacy & Security).
;; Without it the connection fails with "No route to host" while the very same
;; command works from a terminal, and the grant is lost whenever Emacs is
;; rebuilt, since it is tied to the code signature.
;; `ps/info-triage--failure-hint' turns that message into the thing to do.

;;; Code:

(require 'seq)
;; A real require, not a declaration: the keymap below is built at load time
;; and `ps/open-bind-click' has to exist by then.
(require 'ps-open)

(declare-function ps/window-replace-here "ps-window")
(declare-function ps/window-show-here "ps-window")
(declare-function ps/window-visit-here "ps-window")
(declare-function ps/window--select-main "ps-window")
(declare-function ps/nav-back "ps-nav")
(declare-function ps/nav-forward "ps-nav")
(declare-function org-back-to-heading "org")
(declare-function org-open-at-point "org")
(declare-function org-link-display-format "ol")
(declare-function org-element-context "org-element")
(declare-function org-element-lineage "org-element-ast")
(declare-function org-element-property "org-element-ast")

(defgroup ps/info-triage nil
  "Review the info-triage capture inbox."
  :group 'ps)

(defcustom ps/info-triage-directory (expand-file-name "~/info-triage-inbox/info/")
  "Directory holding the capture queue this feature works.

The sync script pulls each of its routes into its own subdirectory of
~/info-triage-inbox/, and each is a self-contained queue: its own items, its
own `triage.org' beside them, its own numbering from 1.  This points at the
default route, which is the only one triaged by hand -- job, clip and lang are
consumed by scripts.  Point it at another route's directory to work that one
instead; nothing else here needs to change, because an item's `directory' link
is relative to the queue that lists it.

Everything in this feature is hidden when it does not exist and no sync
script is set either, so a machine without the info-triage project never sees
a menu for it."
  :type 'directory
  :group 'ps/info-triage)

(defcustom ps/info-triage-sync-script nil
  "The pipeline's synchronization script: `sync.sh' in its checkout.

There is no default, because where that project is checked out differs from
machine to machine.  Set it in local.el.  Reading and dropping items work
without it; only the two sync commands need it."
  :type '(choice (const :tag "Not set" nil) file)
  :group 'ps/info-triage)

(defcustom ps/info-triage-open-beside t
  "Whether an item opens beside the queue rather than in its window.

With this on -- the default -- the queue keeps its window for good: the first
item you open splits and takes the other pane, and every item after that lands
in that same pane.  The list is read down over and over, so an item opening
into it would take the list away every time.

Turn it off for one window at a time: the item replaces the queue and `‹'
brings it back."
  :type 'boolean
  :group 'ps/info-triage)

(defcustom ps/info-triage-external-command "code"
  "Program that opens an item's directory outside Emacs.
The escape hatch for a mixed-media item Emacs is the wrong tool for."
  :type 'string
  :group 'ps/info-triage)

(defconst ps/info-triage-queue-name "triage.org"
  "The generated navigation view, inside `ps/info-triage-directory'.")

(defconst ps/info-triage--directory-link-re
  "\\[\\[file:\\([^]/]+\\)/\\]\\[directory\\]\\]"
  "Matches the queue's `directory' link, capturing the item's directory name.
Generated by `render_org' in the info-triage project; the only place an
item's id still appears.")

(defconst ps/info-triage--heading-re "^\\*\\* \\([0-9]+\\) "
  "Matches a queue item's heading, capturing the item number.
Level two: the queue groups its items under a level-one heading per day.  The
number is still global across the days -- it is what a routing agent is quoted
and it has to keep meaning the same item in both views.")

(defconst ps/info-triage--any-heading-re "^\\*+ "
  "Matches any queue heading, an item's or a day's.
Used to bound a search inside one item: the *next* heading may be the day
after this one rather than another item.")

;;; Where things are

(defun ps/info-triage-queue-file ()
  "Return the path of the generated queue."
  (expand-file-name ps/info-triage-queue-name ps/info-triage-directory))

;;;###autoload
(defun ps/info-triage-available-p ()
  "Non-nil when this machine has an info-triage inbox to work with.
Either the inbox is there, or `ps/info-triage-sync-script' says where to get
one from: the first sync creates the inbox, so requiring it up front would
hide the only command that can make it."
  (or (file-directory-p ps/info-triage-directory)
      (and ps/info-triage-sync-script t)))

(defun ps/info-triage-queue-buffer-p (&optional buffer)
  "Non-nil when BUFFER (default current) is visiting the generated queue."
  (with-current-buffer (or buffer (current-buffer))
    (and buffer-file-name
         (equal (file-truename buffer-file-name)
                (file-truename (ps/info-triage-queue-file))))))

;;; Reading the item at point

(defun ps/info-triage--item-directory ()
  "Return the directory name of the item at point, or nil.

Read out of the heading's `directory' link rather than a property, because
the queue no longer carries a drawer -- see this file's Commentary."
  (save-excursion
    (when (ignore-errors (org-back-to-heading t) t)
      ;; Bounded by the NEXT heading of any level, searched for from the line
      ;; below this one -- from the heading itself the search matches this
      ;; heading and the bound collapses to nothing, which reads as an item with
      ;; no links at all.  Any level, because the last item of a day is followed
      ;; by the next day rather than by another item.
      (let ((end (save-excursion
                   (forward-line 1)
                   (if (re-search-forward ps/info-triage--any-heading-re nil t)
                       (match-beginning 0)
                     (point-max)))))
        (when (re-search-forward ps/info-triage--directory-link-re end t)
          (match-string-no-properties 1))))))

(defun ps/info-triage--item-number ()
  "Return the number of the item at point as a string, or nil."
  (save-excursion
    (when (ignore-errors (org-back-to-heading t) t)
      (when (looking-at ps/info-triage--heading-re)
        (match-string-no-properties 1)))))

(defun ps/info-triage--item-path ()
  "Return the absolute path of the item at point, or signal."
  (let ((name (or (ps/info-triage--item-directory)
                  (user-error "Point is not on an item"))))
    (expand-file-name name ps/info-triage-directory)))

(defun ps/info-triage--item-label ()
  "Return the item at point's heading without what the prompt already says.
The number is repeated by the caller, and the kind tag is Org markup rather
than something to read back at someone.  The title is a link to the item's
index, so it is reduced to the text that is actually on screen."
  (save-excursion
    (org-back-to-heading t)
    (let ((heading (buffer-substring-no-properties (pos-bol) (pos-eol))))
      (string-trim
       (org-link-display-format
        (replace-regexp-in-string
         "\\s-+:[[:alnum:]_@#%:]+:\\s-*\\'" ""
         (replace-regexp-in-string "\\`\\*+ +[0-9]+ · " "" heading)))))))

(defun ps/info-triage--item-size (path)
  "Return a short description of what PATH holds, for a confirmation prompt."
  (let ((files (and (file-directory-p path)
                    (directory-files-recursively path "" nil))))
    (format "%d file%s" (length files) (if (= (length files) 1) "" "s"))))

;;; Sync status

(defconst ps/info-triage--log-buffer "*info-triage sync*"
  "Name of the buffer holding the sync script's output.")

(defvar ps/info-triage--status '(:state idle)
  "What the sync script is doing or last did, as a plist.
`:state' is `idle', `running', `done' or `failed'; `:action' is `sync' or
`regenerate'.  While running, `:stage' names the stage and `:done'/`:total'
count through it.  Afterwards `:finished' is the time, `:new' the number of
items that arrived, `:seen' whether the queue has been looked at since, and
`:detail' the reason for a failure.")

(defvar ps/info-triage--process nil
  "The running sync process, if any.")

(defun ps/info-triage--busy-p ()
  "Non-nil while the sync script is running."
  (process-live-p ps/info-triage--process))

(defun ps/info-triage--parse-progress (line)
  "Return what LINE of the sync script's output reports, or nil.
A stage line gives (:stage NAME), a counted line (:done N :total M).  The
stage is cut at its first dash: what follows is commentary for someone
reading the whole log."
  (cond
   ((string-match "\\`==> \\(.+\\)" line)
    (list :stage (string-trim (car (split-string (match-string 1 line) " — ")))))
   ((string-match "\\` +\\[ *\\([0-9]+\\)/\\([0-9]+\\)\\]" line)
    (list :done (string-to-number (match-string 1 line))
          :total (string-to-number (match-string 2 line))))))

(defun ps/info-triage--status-after-line (status line)
  "Return STATUS updated by LINE of the sync script's output.
A new stage starts its own count."
  (let ((progress (ps/info-triage--parse-progress line)))
    (cond
     ((plist-member progress :stage)
      (list :state 'running :action (plist-get status :action)
            :stage (plist-get progress :stage)))
     (progress
      (plist-put (plist-put (copy-sequence status)
                            :done (plist-get progress :done))
                 :total (plist-get progress :total)))
     (t status))))

(defun ps/info-triage--failure-hint (output &optional system)
  "Return what to do about the failure in OUTPUT, or nil when it is not known.
SYSTEM defaults to `system-type'.  See this file's Commentary for why a
network failure on macOS is usually a missing permission."
  (when (and (eq (or system system-type) 'darwin)
             (string-match-p "No route to host" output))
    "Emacs may lack Local Network access (System Settings → Privacy & Security → Local Network)"))

(defun ps/info-triage--failure-detail (output)
  "Return one line saying why the sync that printed OUTPUT failed."
  (or (ps/info-triage--failure-hint output)
      (car (last (split-string output "[\n\r]+" t "[ \t]+")))
      "no output"))

(defun ps/info-triage--format-time (time)
  "Return TIME as a clock time, with the date when it is not today."
  (format-time-string
   (if (equal (format-time-string "%F" time) (format-time-string "%F"))
       "%H:%M"
     "%-d %b %H:%M")
   time))

(defun ps/info-triage--status-label (status &optional compact)
  "Return the text describing STATUS, or nil when there is nothing to say.
In full it is a sentence for the queue's header line.  COMPACT is the marker
for the file tree's mode line, which has room for a few characters: an arrow
while running, the arrow and the number of new items once they have arrived
and until the queue is looked at, the arrow and `!' after a failure."
  (let ((state (plist-get status :state))
        (syncing (not (eq (plist-get status :action) 'regenerate)))
        (new (or (plist-get status :new) 0)))
    (if compact
        (pcase state
          ('running "⇣")
          ('failed "⇣!")
          ('done (and (> new 0) (not (plist-get status :seen))
                      (format "⇣%d" new))))
      (pcase state
        ('running
         (concat (if syncing "Syncing" "Rebuilding the list")
                 (when-let* ((stage (plist-get status :stage)))
                   (concat " · " stage))
                 (when-let* ((total (plist-get status :total)))
                   (format " · %d/%d" (plist-get status :done) total))))
        ('failed
         (format "%s failed · %s" (if syncing "Sync" "Rebuild")
                 (plist-get status :detail)))
        ('done
         (concat (if syncing "Synced " "Rebuilt ")
                 (ps/info-triage--format-time (plist-get status :finished))
                 (when syncing
                   (if (> new 0) (format " · %d new" new) " · nothing new"))))))))

(defun ps/info-triage--item-names ()
  "Return the names of the item directories in the inbox."
  (when (file-directory-p ps/info-triage-directory)
    (seq-filter (lambda (name)
                  (file-directory-p
                   (expand-file-name name ps/info-triage-directory)))
                (directory-files ps/info-triage-directory nil "\\`[^.]"))))

(defun ps/info-triage--set-status (status)
  "Make STATUS current and redraw everything that shows it."
  (setq ps/info-triage--status status)
  (force-mode-line-update t))

(defun ps/info-triage--mark-seen (&rest _)
  "Record that the queue has been looked at since the last sync.
That is what takes the new-items marker off the file tree's mode line."
  (when (and (eq (plist-get ps/info-triage--status :state) 'done)
             (not (plist-get ps/info-triage--status :seen)))
    (ps/info-triage--set-status
     (plist-put (copy-sequence ps/info-triage--status) :seen t))))

;;;###autoload
(defun ps/info-triage-show-log ()
  "Show the sync script's output."
  (interactive)
  (display-buffer (get-buffer-create ps/info-triage--log-buffer)))

(defun ps/info-triage--button (label command help)
  "Return LABEL as a header-line button running COMMAND, with tooltip HELP."
  (propertize label
              'face 'link
              'mouse-face 'header-line-highlight
              'help-echo (concat "mouse-1: " help)
              'local-map (let ((map (make-sparse-keymap)))
                           (define-key map [header-line mouse-1] command)
                           map)))

(defun ps/info-triage--header-line ()
  "Return the queue's header line: the sync status, and what can be done next."
  (let* ((status ps/info-triage--status)
         (state (plist-get status :state))
         (label (or (ps/info-triage--status-label status)
                    ;; Nothing has run in this session; the file still says
                    ;; when the list was last written.
                    (if-let* ((attributes (file-attributes (ps/info-triage-queue-file))))
                        (concat "Updated "
                                (ps/info-triage--format-time
                                 (file-attribute-modification-time attributes)))
                      "Not synced yet")))
         (log (ps/info-triage--button "Log" #'ps/info-triage-show-log
                                      "show the sync script's output"))
         (sync (lambda (text)
                 (ps/info-triage--button text #'ps/info-triage-sync
                                         "fetch new captures"))))
    (concat " "
            ;; A `%' in the script's output is not a mode-line construct.
            (replace-regexp-in-string "%" "%%" label t t)
            "   "
            (pcase state
              ('running log)
              ('failed (concat log "  " (funcall sync "Retry")))
              (_ (funcall sync "Sync"))))))

(defvar ps/info-triage--modeline-map
  (let ((map (make-sparse-keymap)))
    ;; mouse-1 only, like the git-sync indicator beside it.
    (define-key map [mode-line mouse-1] #'ps/info-triage-modeline-click)
    map)
  "Keymap on the sync marker in the file tree's mode line.")

(defun ps/info-triage-modeline-click ()
  "Go to what the sync marker is about: the log after a failure, else the queue."
  (interactive)
  (if (or (eq (plist-get ps/info-triage--status :state) 'failed)
          (not (file-exists-p (ps/info-triage-queue-file))))
      (ps/info-triage-show-log)
    (ps/info-triage-open)))

(defun ps/info-triage--modeline ()
  "Return the sync marker for the file tree's mode line, or nil.
Rendered by `ps/file-tree--modeline'.  The words are in the tooltip: that
mode line is as narrow as the tree."
  (when-let* ((label (ps/info-triage--status-label ps/info-triage--status t)))
    (let ((face (pcase (plist-get ps/info-triage--status :state)
                  ('failed 'warning)
                  ('done 'mode-line-emphasis))))
      (apply #'propertize label
             'help-echo (concat "Info Triage: "
                                (ps/info-triage--status-label ps/info-triage--status)
                                "\nmouse-1: open")
             'mouse-face 'mode-line-highlight
             'local-map ps/info-triage--modeline-map
             (when face (list 'face face))))))

;;; Commands

;;;###autoload
(defun ps/info-triage-open ()
  "Open the capture queue in this window."
  (interactive)
  (unless (ps/info-triage-available-p)
    (user-error "No info-triage inbox at %s" ps/info-triage-directory))
  (let ((file (ps/info-triage-queue-file)))
    (cond
     ((file-exists-p file) (ps/window-visit-here file))
     ;; The first run: there is nothing to open until a sync has made it, and
     ;; that sync opens the queue itself when it lands.
     ((and ps/info-triage-sync-script
           (y-or-n-p (format "No %s yet -- synchronize now? "
                             ps/info-triage-queue-name)))
      (ps/info-triage-sync))
     (t (user-error "No %s yet -- synchronize first"
                    ps/info-triage-queue-name)))))

(defun ps/info-triage--revert-queue ()
  "Reload the queue buffer if it is open, keeping the item you were reading.

The file is regenerated wholesale and carries no state, so reverting can
never lose anything: removing an item's directory is the only signal that it
was processed."
  (when-let* ((buffer (find-buffer-visiting (ps/info-triage-queue-file))))
    (with-current-buffer buffer
      (let ((number (ps/info-triage--item-number))
            (inhibit-read-only t))
        (revert-buffer :ignore-auto :noconfirm)
        ;; Numbers shift when an item is dropped, so this lands on whatever now
        ;; holds that position -- which is the next item, and is what you want.
        (when number
          (goto-char (point-min))
          (re-search-forward (format "^\\*\\* %s " (regexp-quote number)) nil t)
          (beginning-of-line))))))

(defun ps/info-triage--filter (process chunk)
  "Append CHUNK of PROCESS's output to the log and read its progress lines."
  (when (buffer-live-p (process-buffer process))
    (with-current-buffer (process-buffer process)
      (let ((inhibit-read-only t))
        (save-excursion
          (goto-char (process-mark process))
          (insert chunk)
          (set-marker (process-mark process) (point))))
      ;; A log being watched follows the output.
      (dolist (window (get-buffer-window-list nil nil t))
        (set-window-point window (process-mark process)))))
  ;; Output arrives in arbitrary pieces, so the unfinished last line waits for
  ;; the rest of itself.
  (let ((lines (split-string (concat (process-get process 'partial) chunk) "\n"))
        (status ps/info-triage--status))
    (process-put process 'partial (car (last lines)))
    (dolist (line (butlast lines))
      (setq status (ps/info-triage--status-after-line status line)))
    (unless (eq status ps/info-triage--status)
      (ps/info-triage--set-status status))))

(defun ps/info-triage--run (arguments on-success)
  "Run the sync script with ARGUMENTS, then call ON-SUCCESS.
Asynchronous and quiet: progress goes to `ps/info-triage--status', and the
output buffer is only shown when the script fails, so a routine sync does not
take a window away from what you were reading."
  (unless ps/info-triage-sync-script
    (user-error "Set `ps/info-triage-sync-script' in local.el to the pipeline's sync.sh"))
  (unless (file-executable-p ps/info-triage-sync-script)
    (user-error "Not executable: %s" ps/info-triage-sync-script))
  (when (ps/info-triage--busy-p)
    (user-error "Info Triage is already running -- see the queue's header line"))
  (let ((output (get-buffer-create ps/info-triage--log-buffer))
        (action (if arguments 'regenerate 'sync))
        (before (ps/info-triage--item-names))
        ;; Python buffers a pipe by the block, which would hold every stage
        ;; line back until the script exits.
        (process-environment (cons "PYTHONUNBUFFERED=1" process-environment)))
    (with-current-buffer output
      (let ((inhibit-read-only t)) (erase-buffer)))
    (ps/info-triage--set-status (list :state 'running :action action))
    (setq ps/info-triage--process
          (make-process
           :name "ps-info-triage-sync"
           :buffer output
           :noquery t
           ;; A pipe, not a pty: on a terminal the script rewrites one progress
           ;; line in place instead of printing a line per item.
           :connection-type 'pipe
           ;; Through a login shell, not directly: the script runs `uv', and a
           ;; Finder-launched Emacs inherits a PATH that does not have it.
           :command (list shell-file-name "-lc"
                          (mapconcat #'shell-quote-argument
                                     (cons ps/info-triage-sync-script arguments) " "))
           :filter #'ps/info-triage--filter
           :sentinel
           (lambda (process _event)
             (when (memq (process-status process) '(exit signal))
               (if (zerop (process-exit-status process))
                   (let ((new (seq-difference (ps/info-triage--item-names) before)))
                     (ps/info-triage--set-status
                      (list :state 'done :action action
                            :finished (current-time)
                            :new (if (eq action 'sync) (length new) 0)))
                     (funcall on-success)
                     (message "Info Triage: %s"
                              (ps/info-triage--status-label ps/info-triage--status)))
                 (let ((detail (ps/info-triage--failure-detail
                                (with-current-buffer output (buffer-string)))))
                   (ps/info-triage--set-status
                    (list :state 'failed :action action :detail detail))
                   (display-buffer output)
                   (message "Info Triage: %s"
                            (ps/info-triage--status-label
                             ps/info-triage--status))))))))))

;;;###autoload
(defun ps/info-triage-sync ()
  "Fetch new captures from the NAS and propagate anything dropped here.
The queue is brought up to watch it from: its header line shows the progress.
On the first run there is no queue to bring up, so it opens when it lands."
  (interactive)
  (let* ((file (ps/info-triage-queue-file))
         (first-run (not (file-exists-p file))))
    (ps/info-triage--run
     nil
     (lambda ()
       (ps/info-triage--revert-queue)
       (when (and first-run (file-exists-p file))
         (ps/info-triage-open))))
    (unless (or first-run
                (when-let* ((buffer (find-buffer-visiting file)))
                  (get-buffer-window buffer)))
      (ps/info-triage-open))))

;;;###autoload
(defun ps/info-triage-regenerate ()
  "Rebuild both views from the item directories present, without the network.
Both are renumbered together, which is what keeps the number shown here and
the number a routing agent reads naming the same item."
  (interactive)
  (ps/info-triage--run '("--regenerate") #'ps/info-triage--revert-queue))

;;;###autoload
(defun ps/info-triage-drop ()
  "Drop the item at point: move its directory to the Trash and renumber.

Deleting the directory is the project's own signal that an item was
processed, so the next synchronization removes the NAS copy too.  It goes to
the Trash rather than being unlinked because the decision is a judgement made
at a glance, and a glance is sometimes wrong."
  (interactive)
  ;; Before anything is removed, not after: the renumbering below is the same
  ;; script, and a directory deleted without it leaves the two views disagreeing.
  (when (ps/info-triage--busy-p)
    (user-error "Info Triage is still running -- drop the item when it finishes"))
  (let* ((path (ps/info-triage--item-path))
         (number (ps/info-triage--item-number))
         (label (ps/info-triage--item-label)))
    (unless (file-directory-p path)
      (user-error "No such item directory: %s" path))
    (when (yes-or-no-p (format "Drop item %s (%s) — %s? "
                               (or number "?")
                               (ps/info-triage--item-size path)
                               label))
      (let ((delete-by-moving-to-trash t))
        (delete-directory path :recursive :trash))
      (ps/info-triage-regenerate))))

;;;###autoload
(defun ps/info-triage-open-externally ()
  "Open the item at point's directory outside Emacs.
The escape hatch: an item whose payload is twenty images and a video is one
a file browser shows better than this does."
  (interactive)
  (let ((path (if (ps/info-triage-queue-buffer-p)
                  (ps/info-triage--item-path)
                (expand-file-name ps/info-triage-directory))))
    (let ((program (executable-find ps/info-triage-external-command)))
      (unless program
        (user-error "No `%s' on PATH" ps/info-triage-external-command))
      (call-process program nil 0 nil path)
      (message "Opened %s outside Emacs" (abbreviate-file-name path)))))

(defun ps/info-triage--move-item (count)
  "Move point COUNT items forward, or backward when COUNT is negative.
Returns non-nil when it moved.  Days are headings too, so stepping with
`org-next-visible-heading' would stop on a date -- a stop where none of the
single keys mean anything."
  (let ((start (point))
        (search (if (> count 0) #'re-search-forward #'re-search-backward)))
    (when (> count 0) (end-of-line))
    (when (< count 0) (beginning-of-line))
    (if (funcall search ps/info-triage--heading-re nil t (abs count))
        (progn (beginning-of-line) t)
      (goto-char start)
      nil)))

;;;###autoload
(defun ps/info-triage-next-item ()
  "Move to the next item in the queue."
  (interactive)
  (unless (ps/info-triage--move-item 1)
    (message "Last item")))

;;;###autoload
(defun ps/info-triage-previous-item ()
  "Move to the previous item in the queue."
  (interactive)
  (unless (ps/info-triage--move-item -1)
    (message "First item")))

(defun ps/info-triage-follow ()
  "Follow the link at point, or open the item's index when point is not on one.

Bound over `org-open-at-point' rather than replacing Org's file handling,
because the whole point is that a `.md' link renders, a `.pdf' link goes to
Preview and a `.mp4' link goes to the system player -- which is
`ps/open-file's job, and Org would visit all three as text."
  (interactive)
  (let ((link (org-element-lineage (org-element-context) '(link) t)))
    (if (null link)
        (ps/open-file (expand-file-name "index.md" (ps/info-triage--item-path)))
      (let ((type (org-element-property :type link))
            (path (org-element-property :path link)))
        (cond
         ((equal type "file") (ps/open-file (expand-file-name path default-directory)))
         ((member type '("http" "https")) (browse-url (format "%s:%s" type path)))
         (t (org-open-at-point)))))))

(defun ps/info-triage-follow-at-mouse (event)
  "Follow whatever EVENT clicked on.
Point is normally already at the click by the time a mouse-2 binding runs, but
a middle click arrives with no preceding drag -- which is why the command this
replaces, `org-open-at-mouse', sets point itself."
  (interactive "e")
  (mouse-set-point event)
  (ps/info-triage-follow))

;;; The queue buffer

(defvar ps/info-triage-mode-map
  (let ((map (make-sparse-keymap)))
    ;; A remap rather than a key: Org puts its own keymap on a link as a text
    ;; property, which outranks a minor-mode map, so binding RET and mouse-1
    ;; alone would leave clicking a link going somewhere else entirely.
    ;;
    ;; BOTH remaps are needed, and the second is the one that was missing.
    ;; `org-mouse-map' binds mouse-2 to `org-open-at-mouse', a *separate*
    ;; command that ends in a plain `(org-open-at-point)' function call --
    ;; and remapping rewrites command dispatch, never a funcall.  So with only
    ;; the first line here, every mouse click went through stock Org file
    ;; handling and opened the item in another window.
    (define-key map [remap org-open-at-point] #'ps/info-triage-follow)
    (define-key map [remap org-open-at-mouse] #'ps/info-triage-follow-at-mouse)
    ;; And the mouse directly, because even that pair is not enough: a click
    ;; that reaches Org at all has already moved point into the link, which
    ;; `org-appear' answers by revealing its raw syntax -- the line grows under
    ;; the pointer and the release lands somewhere else.  `ps/open-bind-click'
    ;; follows on the *press* and never moves point.  See `ps/open-down-click'.
    (ps/open-bind-click map)
    (define-key map (kbd "RET") #'ps/info-triage-follow)
    (define-key map (kbd "n")   #'ps/info-triage-next-item)
    (define-key map (kbd "p")   #'ps/info-triage-previous-item)
    (define-key map (kbd "d")   #'ps/info-triage-drop)
    (define-key map (kbd "s")   #'ps/info-triage-sync)
    (define-key map (kbd "g")   #'ps/info-triage-regenerate)
    (define-key map (kbd "e")   #'ps/info-triage-open-externally)
    (define-key map (kbd "b")   #'ps/nav-back)
    (define-key map (kbd "f")   #'ps/nav-forward)
    (define-key map (kbd "q")   #'bury-buffer)
    map)
  "Keymap for `ps/info-triage-mode'.
Single keys, Dired-style, which the buffer being read-only is what allows.")

(define-minor-mode ps/info-triage-mode
  "Minor mode for the generated info-triage queue.

The buffer is read-only because it is regenerated on every sync: anything
typed here is lost, and saying so up front is also what frees the single-key
bindings."
  :lighter " Triage"
  :keymap ps/info-triage-mode-map
  (setq buffer-read-only (and ps/info-triage-mode t))
  ;; The sync status, and the buttons that go with it.
  (setq header-line-format
        (and ps/info-triage-mode '(:eval (ps/info-triage--header-line))))
  ;; Buffer-local, so it runs when a window starts showing *this* buffer.
  (if ps/info-triage-mode
      (add-hook 'window-buffer-change-functions #'ps/info-triage--mark-seen nil t)
    (remove-hook 'window-buffer-change-functions #'ps/info-triage--mark-seen t))
  ;; A click here follows a link and nothing else -- the RET behaviour of
  ;; opening the item at point when there is no link would mean clicking
  ;; anywhere at all opened something.
  (if ps/info-triage-mode
      (ps/open-setup-click #'ps/info-triage-follow)
    (setq-local ps/open-follow-function nil))
  ;; The queue stays where it is and items open beside it; see
  ;; `ps/info-triage-open-beside'.
  (setq-local ps/open-keep-window
              (and ps/info-triage-mode ps/info-triage-open-beside))
  ;; Org buffers get a line-number gutter here because plan files are worth
  ;; citing by line.  A generated queue is not: its items are addressed by the
  ;; number printed in each heading, and a second, different set of numbers
  ;; running down the left margin is the one thing guaranteed to be misread.
  (display-line-numbers-mode (if ps/info-triage-mode 0 1)))

(defun ps/info-triage--maybe-enable ()
  "Turn on `ps/info-triage-mode' when this buffer is the queue."
  (when (ps/info-triage-queue-buffer-p)
    (ps/info-triage-mode 1)))

;;;###autoload
(defun ps/info-triage-setup ()
  "Recognise the info-triage queue whenever it is opened."
  (add-hook 'org-mode-hook #'ps/info-triage--maybe-enable))

(provide 'ps-info-triage)
;;; ps-info-triage.el ends here
