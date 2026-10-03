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
;; is 1280x800 points (16:10, 2560x1600 pixels on a Retina display), and every
;; picture is scaled to 1920x1200 and quantized, like the pictures of the
;; agent-context-pipeline project they sit beside on the blog.
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

(defvar ps/screenshot-size '(1280 . 800)
  "Outer size of the frame, in points, while taking pictures.")

(defvar ps/screenshot-width 1920
  "Width in pixels of the saved picture.")

(defvar ps/screenshot-directory
  (expand-file-name "screenshots/" user-emacs-directory)
  "Where pictures are saved.")

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

(defun ps/screenshot-frame (name)
  "Save the selected frame as NAME.png in `ps/screenshot-directory'."
  (interactive "sPicture name: ")
  (let ((out (expand-file-name (concat (file-name-sans-extension name) ".png")
                               ps/screenshot-directory)))
    (make-directory ps/screenshot-directory t)
    ;; `screencapture -R' grabs whatever is on top at those coordinates, so
    ;; this Emacs must be frontmost, not merely raised.
    (raise-frame)
    (call-process "osascript" nil nil nil "-e"
                  (format "tell application \"System Events\" to set frontmost of (first process whose unix id is %d) to true"
                          (emacs-pid)))
    ;; The echo area would otherwise still show the last message -- often the
    ;; previous picture's full path.
    (message nil)
    (sit-for 0.5)
    (redisplay t)
    (pcase-let ((`(,left ,top ,right ,bottom) (frame-edges nil 'outer-edges)))
      (unless (eq 0 (call-process "screencapture" nil nil nil "-x" "-o"
                                  (format "-R%d,%d,%d,%d" left top (- right left) (- bottom top)) out))
        (user-error "screencapture failed for %s" out)))
    (call-process "sips" nil nil nil "-Z" (number-to-string ps/screenshot-width) out)
    (call-process "pngquant" nil nil nil "--force" "--skip-if-larger"
                  "--output" out "256" out)
    (message "Saved %s" out)
    out))

;; The pictures show the sample notes, never a sync in progress.
(setq ps/git-sync-paused t)

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
