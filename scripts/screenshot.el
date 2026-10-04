;;; screenshot.el --- Capture the running frame as a README picture -*- lexical-binding: t; -*-

;; Loaded into a dev session AFTER the normal config, against the throwaway
;; notes from scripts/make_screenshot_vault.py:
;;
;;   scripts/make_screenshot_vault.py
;;   PS_ORG_BASE=$TMPDIR/ps-screenshot/notes ./scripts/run_emacs_dev.sh \
;;     -l "$PWD/scripts/screenshot.el"
;;
;; It sets nothing up on its own: each scene in screenshots/README.md is built
;; by hand (or by an agent through `emacsclient -s ps-shots --eval ...'), and
;; `M-x ps/screenshot-frame' saves it.  The shot list, not a script, is what a
;; retake starts from -- the scenes depend on a live Claude Code conversation,
;; which no script can replay.
;;
;; What it does fix is everything that must not vary between shots: the frame
;; is 1067x667 points (16:10; 1200x750 for the scenes with the Claude panel),
;; every picture is scaled to 1920x1200 and quantized, like the pictures of the
;; agent-context-pipeline project they sit beside on the blog, and the window
;; is captured by its id, so the rounded corners come out transparent.
;;
;; It also takes out what only distracts in a picture, for this session only:
;; the sync label in the file tree's mode line, and Ediff's "Type ? for help".
;; `ps/screenshot-inline-diff' shows a diff Claude proposed inline in one
;; buffer, which reads better in a picture than two panes side by side.
;;
;; The dates in the sample notes need no faking: the vault script moves them so
;; their busiest day is today, so the schedule view, availability and conflicts
;; -- which read the real clock -- agree with the agenda.
;;
;; macOS only.  The process running Emacs (the terminal, or the editor that
;; launched it) needs Screen Recording permission, or `screencapture' saves the
;; desktop instead, and Automation permission for System Events, used to bring
;; this Emacs to the front first.

(require 'server)
(require 'seq)

(defvar ps/screenshot-size '(1067 . 667)
  "Outer size of the frame, in points, while taking pictures.")

(defvar ps/screenshot-width 1920
  "Width in pixels of the saved picture.")

(defvar ps/screenshot-directory
  (expand-file-name "screenshots/" user-emacs-directory)
  "Where pictures are saved.")

(defvar ps/screenshot-corner-radius 20
  "Corner radius, in saved pixels, for the mask used when a window capture fails.")

(defun ps/screenshot-fit-frame (&optional frame)
  "Make FRAME's outer size exactly `ps/screenshot-size'."
  (interactive)
  (let ((frame (or frame (selected-frame)))
        ;; Otherwise the size is rounded to whole characters.
        (frame-resize-pixelwise t))
    ;; `set-frame-size' sets the text area; the title bar, fringes and mode
    ;; lines around it are measured once and added back.
    (dotimes (_ 2)
      (pcase-let ((`(,left ,top ,right ,bottom) (frame-edges frame 'outer-edges)))
        (set-frame-size frame
                        (+ (frame-text-width frame) (- (car ps/screenshot-size) (- right left)))
                        (+ (frame-text-height frame) (- (cdr ps/screenshot-size) (- bottom top)))
                        t)))))

(defun ps/screenshot--capture (out)
  "Capture the selected frame's window to OUT; non-nil when it worked.
By window id first, which keeps the rounded corners transparent; by screen
region otherwise, with the corners masked afterwards."
  (let ((id (frame-parameter nil 'window-id)))
    (or (and id
             (eq 0 (call-process "screencapture" nil nil nil "-x" "-o"
                                 (format "-l%s" id) out))
             (file-exists-p out))
        (pcase-let ((`(,left ,top ,right ,bottom) (frame-edges nil 'outer-edges)))
          (and (eq 0 (call-process "screencapture" nil nil nil "-x" "-o"
                                   (format "-R%d,%d,%d,%d" left top
                                           (- right left) (- bottom top))
                                   out))
               (ps/screenshot--round-corners out))))))

(defun ps/screenshot--round-corners (file)
  "Make the corners of FILE transparent, the way a window capture leaves them."
  (let ((r (number-to-string (* 2 ps/screenshot-corner-radius))))
    (eq 0 (call-process
           "magick" nil nil nil file
           "(" "+clone" "-alpha" "extract" "-fill" "black" "-colorize" "100"
           "-fill" "white" "-draw"
           (format "roundrectangle 0,0,%%[fx:w-1],%%[fx:h-1],%s,%s" r r) ")"
           "-alpha" "off" "-compose" "CopyOpacity" "-composite" file))))

(defvar ps/screenshot-outline-color "#9a9a9a"
  "Colour of the thin outline drawn around every picture.")

(defun ps/screenshot--outline (file)
  "Draw a two-pixel outline along the window's shape in FILE.
On a white page the cream window has nothing to end against otherwise.  It
follows the picture's own transparency, so the rounded corners are outlined
too; running it again changes nothing."
  (eq 0 (call-process
         "magick" nil nil nil file
         "(" "+clone" "-alpha" "extract" "-virtual-pixel" "black"
         "-morphology" "EdgeIn" "Diamond:2" "-write" "mpr:edge" "+delete" ")"
         "(" "+clone" "-fill" ps/screenshot-outline-color "-colorize" "100"
         "mpr:edge" "-alpha" "off" "-compose" "CopyOpacity" "-composite" ")"
         "-compose" "Over" "-composite" file)))

(defun ps/screenshot-frame (name)
  "Save the selected frame as NAME.png in `ps/screenshot-directory'."
  (interactive "sPicture name: ")
  (let ((out (expand-file-name (concat (file-name-sans-extension name) ".png")
                               ps/screenshot-directory)))
    (make-directory ps/screenshot-directory t)
    (raise-frame)
    (call-process "osascript" nil nil nil "-e"
                  (format "tell application \"System Events\" to set frontmost of (first process whose unix id is %d) to true"
                          (emacs-pid)))
    ;; The echo area would otherwise still show the last message -- often the
    ;; previous picture's full path.
    (message nil)
    (sit-for 0.5)
    (redisplay t)
    (unless (ps/screenshot--capture out)
      (user-error "screencapture failed for %s" out))
    (call-process "sips" nil nil nil "-Z" (number-to-string ps/screenshot-width) out)
    (ps/screenshot--outline out)
    (call-process "pngquant" nil nil nil "--force" "--skip-if-larger"
                  "--output" out "256" out)
    (message "Saved %s" out)
    out))

;;; Diffs

(defun ps/screenshot--ediff-control ()
  "The control buffer of the live Ediff session, or nil."
  (seq-find (lambda (b) (eq (buffer-local-value 'major-mode b) 'ediff-mode))
            (buffer-list)))

(defun ps/screenshot-hide-ediff-control ()
  "Close the Ediff control window; the session itself stays alive."
  (interactive)
  (when-let* ((ctl (ps/screenshot--ediff-control))
              (w (get-buffer-window ctl)))
    (delete-window w)))

(defun ps/screenshot-inline-diff ()
  "Show the live Ediff session inline, in its B (proposed) buffer alone.
Each difference's old text is drawn plain and struck through, on its own
unnumbered line just before the new text, which is highlighted; the A and
control windows are closed.  Run it again after a change to redraw."
  (interactive)
  (let ((ctl (or (ps/screenshot--ediff-control) (user-error "No Ediff session"))))
    (with-current-buffer ctl
      (let ((buf-a ediff-buffer-A) (buf-b ediff-buffer-B))
        (with-current-buffer buf-b
          (remove-overlays (point-min) (point-max) 'ps/screenshot t))
        (dotimes (n ediff-number-of-differences)
          (let* ((old (with-current-buffer buf-a
                        (buffer-substring-no-properties
                         (ediff-get-diff-posn 'A 'beg n ctl)
                         (ediff-get-diff-posn 'A 'end n ctl))))
                 (beg (ediff-get-diff-posn 'B 'beg n ctl))
                 (end (ediff-get-diff-posn 'B 'end n ctl))
                 (new (make-overlay beg end buf-b)))
            (overlay-put new 'ps/screenshot t)
            (overlay-put new 'priority 1000)
            (overlay-put new 'face 'diff-added)
            (unless (string-empty-p old)
              ;; Hung off the end of the line before, so it reads as an
              ;; inserted line without taking that line's number.
              (let ((ov (make-overlay (max (point-min) (1- beg)) (max (point-min) (1- beg)) buf-b)))
                (overlay-put ov 'ps/screenshot t)
                (overlay-put ov 'after-string
                             (concat "\n" (propertize (string-trim-right old "\n")
                                                       'face '(:inherit diff-removed :strike-through t))))))))
        (when-let ((w (get-buffer-window buf-a))) (delete-window w))))
    (ps/screenshot-hide-ediff-control)))

(defun ps/screenshot-panel-rows ()
  "Return the Claude panel's edges and the picture row of each of its lines.
In saved-picture pixels.  Print it to a file beside each capture of the lead
shot; scripts/compose_lead_screenshot.py cuts the panel by it."
  (let* ((w (get-buffer-window "*claude-code[notes]*"))
         (scale (/ 1920.0 (car ps/screenshot-size)))
         (title (- (nth 1 (frame-edges nil 'inner-edges)) (nth 1 (frame-edges nil 'outer-edges))))
         (left (- (nth 0 (frame-edges nil 'inner-edges)) (nth 0 (frame-edges nil 'outer-edges))))
         (edges (window-pixel-edges w))
         (body (window-body-pixel-edges w))
         rows)
    (with-selected-window w
      (save-excursion
        (goto-char (window-start w))
        (while (and (< (point) (point-max)) (pos-visible-in-window-p (point) w))
          (let ((p (posn-at-point (point) w)))
            (when p
              (push (list (round (* scale (+ title (nth 1 body) (cdr (posn-x-y p)))))
                          (buffer-substring-no-properties (line-beginning-position) (min (line-end-position) (+ (line-beginning-position) 60))))
                    rows)))
          (forward-line 1))))
    (list :x0 (round (* scale (+ left (nth 0 edges)))) :x1 (round (* scale (+ left (nth 2 edges))))
          :top (round (* scale (+ title (nth 1 body)))) :bottom (round (* scale (+ title (nth 3 body))))
          :line (round (* scale (frame-char-height)))
          :rows (nreverse rows))))

;;; This session only

;; The pictures show the sample notes, never a sync in progress -- and no sync
;; label either, which in a picture only raises a question.
(setq ps/git-sync-paused t)
(advice-add 'ps/git-sync--modeline :override (lambda () ""))
(setq-default ediff-brief-help-message-function (lambda () ""))
;; Real words the typo checker does not know yet; an underline on them would
;; read as a mistake in the picture.
(setq-default jinx-local-words "agentic Agentic tokenizer quantized")

;; The scratch folder holding the notes and the inbox stands in for the home
;; directory in the mode line, the way the real ones would read.  Display
;; only: file names are untouched, so nothing can reach the real home.
(let ((scratch (file-name-directory (directory-file-name my-org-base-directory))))
  (advice-add 'ps/mode-line--identity :filter-return
              (lambda (label)
                (if (string-prefix-p scratch label)
                    (concat "~/" (substring label (length scratch)))
                  label))))

;; The capture-inbox fixture is copied beside the notes by the vault script.
(let ((queue (expand-file-name "../info-triage-inbox/info/" my-org-base-directory)))
  (when (file-directory-p queue)
    (setq ps/info-triage-directory queue)
    ;; The agent's context names the inbox, and was written when the vault
    ;; opened -- before this ran -- so it still points at the real one.
    (ps/ai-context-sync)))

(ps/screenshot-fit-frame)

;; A named server, so an agent can stage scenes with `emacsclient -s ps-shots'
;; without reaching any other Emacs that is running.
(unless (and (boundp 'server-process) (process-live-p server-process))
  (setq server-name "ps-shots")
  (server-start))

;;; screenshot.el ends here
