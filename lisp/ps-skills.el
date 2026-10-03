;;; ps-skills.el --- Link the shipped Claude Code skills into the vault -*- lexical-binding: t; -*-

;;; Commentary:
;;
;; This config ships the Claude Code skills that maintain the plans (`/route',
;; `/audit') in `skills/' at its root.  Claude Code runs with the vault as its
;; working directory (see lisp/ps-claude.el), so it finds project skills in
;; `<vault>/.claude/skills/'.  `ps/skills-sync' links each shipped skill there.
;;
;; Links, not copies.  A copy goes stale the moment the config is updated, and
;; would be a second source that drifts if anyone edits it in the vault.  A link
;; makes a `git pull' of the config the whole update, and Claude Code opened on
;; the vault from anywhere -- the Emacs panel, VS Code, a terminal -- follows it
;; to the same files.  The target is `ps/skills-directory', resolved at call time
;; against `user-emacs-directory', so a development Emacs links its sample vault
;; to the checkout and the installed config links the real vault to its clone.
;;
;; Every top-level directory of `skills/' is linked, including `_shared/', which
;; is not a skill (it has no SKILL.md) but holds what both skills read.  They
;; refer to it as `../_shared/' from their own folder, which resolves to the same
;; file whether the path is taken lexically or through the link.
;;
;; What it will and won't touch in the vault:
;;   - an absent name is linked; a link aimed elsewhere is re-pointed;
;;   - a real file or directory of the same name is the user's own skill and is
;;     never replaced -- it shadows the shipped one, and is reported;
;;   - a link it made earlier for a skill no longer shipped is removed.
;; "Made earlier" is read from `<vault>/.claude/skills/.gitignore', which this
;; module owns and rewrites (only when its content changes) to list exactly the
;; linked names.  The same file keeps those machine-specific links out of the
;; vault's git history and auto-sync without touching the user's own .gitignore.
;;
;; Called on every vault open and switch (a step in `ps/vault--rederive') and once
;; at the end of config.org for startup.  `ps/skills--plan' is the pure core.

;;; Code:

(require 'seq)
(require 'subr-x)

(defvar my-org-base-directory)

(defgroup ps-skills nil
  "Link the shipped Claude Code skills into the vault."
  :group 'ps)

(defcustom ps/skills-install t
  "When non-nil, `ps/skills-sync' links the shipped skills into the vault."
  :type 'boolean
  :group 'ps-skills)

(defcustom ps/skills-directory nil
  "Directory holding the shipped skills, one subdirectory per skill.
nil means `skills/' under `user-emacs-directory', resolved when the links are
made rather than at load time."
  :type '(choice (const :tag "skills/ in this config" nil) directory)
  :group 'ps-skills)

(defconst ps/skills-vault-subdirectory ".claude/skills"
  "Where Claude Code looks for project skills, relative to its working directory.")

(defconst ps/skills--ignore-header
  "# Written by Emacs (ps/skills-sync): the skills linked from the Emacs config.\n# Rewritten whenever the links change; edits here are lost.\n"
  "First lines of the managed .gitignore.")

;;; Pure core

(defun ps/skills--same-path-p (a b)
  "Return non-nil when paths A and B name the same directory, textually."
  (equal (directory-file-name (expand-file-name a))
         (directory-file-name (expand-file-name b))))

(defun ps/skills--plan (source names existing managed)
  "Return the actions that bring the vault's skills in line with SOURCE.
NAMES are the entries shipped in directory SOURCE.  EXISTING is an alist of
what the vault's skills directory already holds, NAME -> (link . TARGET) or
`real', with TARGET absolute.  MANAGED are the names linked last time.

Each action is (link NAME TARGET), (relink NAME TARGET), (shadowed NAME) or
\(remove NAME); a name already linked correctly yields no action.  Pure."
  (let (actions)
    (dolist (name names)
      (let ((target (expand-file-name name source))
            (have (cdr (assoc name existing))))
        (cond ((null have) (push (list 'link name target) actions))
              ((eq have 'real) (push (list 'shadowed name) actions))
              ((not (ps/skills--same-path-p (cdr have) target))
               (push (list 'relink name target) actions)))))
    (dolist (entry existing)
      (when (and (consp (cdr entry))
                 (member (car entry) managed)
                 (not (member (car entry) names)))
        (push (list 'remove (car entry)) actions)))
    (nreverse actions)))

(defun ps/skills--linked-names (names actions)
  "The NAMES that end up linked once ACTIONS are applied: all but the shadowed."
  (let ((shadowed (delq nil (mapcar (lambda (a) (and (eq (car a) 'shadowed)
                                                     (cadr a)))
                                    actions))))
    (seq-remove (lambda (name) (member name shadowed)) names)))

(defun ps/skills--render-ignore (names)
  "Render the managed .gitignore listing NAMES."
  (concat ps/skills--ignore-header
          (mapconcat (lambda (name) (concat "/" name "\n")) names "")))

(defun ps/skills--parse-ignore (text)
  "Return the names listed in the managed .gitignore TEXT."
  (delq nil (mapcar (lambda (line)
                      (setq line (string-trim line))
                      (and (string-prefix-p "/" line) (substring line 1)))
                    (split-string (or text "") "\n"))))

;;; Impure shell

(defun ps/skills-source ()
  "The directory the shipped skills are linked from."
  (file-name-as-directory
   (expand-file-name (or ps/skills-directory
                         (expand-file-name "skills" user-emacs-directory)))))

(defun ps/skills--shipped (source)
  "The names of the top-level directories in SOURCE, sorted."
  (sort (seq-filter (lambda (name)
                      (and (not (string-prefix-p "." name))
                           (file-directory-p (expand-file-name name source))))
                    (directory-files source))
        #'string<))

(defun ps/skills--existing (dir)
  "Describe the entries of DIR as the alist `ps/skills--plan' takes."
  (when (file-directory-p dir)
    (delq nil
          (mapcar (lambda (name)
                    (let* ((path (expand-file-name name dir))
                           (link (file-symlink-p path)))
                      (cond ((string-prefix-p "." name) nil)
                            (link (cons name (cons 'link (expand-file-name link dir))))
                            (t (cons name 'real)))))
                  (directory-files dir)))))

(defun ps/skills--read-file (file)
  "Return FILE's contents, or nil when it does not exist."
  (when (file-exists-p file)
    (with-temp-buffer (insert-file-contents file) (buffer-string))))

(defun ps/skills--apply (dir action)
  "Carry out ACTION in the vault's skills directory DIR."
  (let ((path (expand-file-name (cadr action) dir)))
    (pcase (car action)
      ('link (make-symbolic-link (directory-file-name (nth 2 action)) path))
      ('relink (delete-file path)
               (make-symbolic-link (directory-file-name (nth 2 action)) path))
      ('remove (delete-file path)))))

;;;###autoload
(defun ps/skills-sync (&optional report)
  "Link the shipped skills into `<vault>/.claude/skills/'.
See the Commentary of ps-skills.el for what is and isn't touched.  Returns the
actions taken.  Does nothing when `ps/skills-install' is nil, no vault is open,
or the skills directory is missing.  Interactively (or with REPORT), says what
it did, including any of your own skills that shadow a shipped one."
  (interactive (list t))
  (let ((source (ps/skills-source))
        (vault (and (boundp 'my-org-base-directory) my-org-base-directory)))
    (when (and ps/skills-install vault (file-directory-p vault)
               (file-directory-p source))
      (let* ((dir (expand-file-name ps/skills-vault-subdirectory vault))
             (ignore-file (expand-file-name ".gitignore" dir))
             (old-ignore (ps/skills--read-file ignore-file))
             (names (ps/skills--shipped source))
             (actions (ps/skills--plan source names (ps/skills--existing dir)
                                       (ps/skills--parse-ignore old-ignore)))
             (new-ignore (ps/skills--render-ignore
                          (ps/skills--linked-names names actions)))
             failed)
        (make-directory dir t)
        (dolist (action actions)
          (condition-case err
              (ps/skills--apply dir action)
            (error (push (cadr action) failed)
                   (message "Skills: could not %s %s: %s" (car action)
                            (cadr action) (error-message-string err)))))
        (unless (equal new-ignore old-ignore)
          (with-temp-file ignore-file (insert new-ignore)))
        (when report
          (let ((shadowed (delq nil (mapcar (lambda (a)
                                              (and (eq (car a) 'shadowed) (cadr a)))
                                            actions))))
            (message "Skills: %d linked from %s%s%s"
                     (- (length names) (length shadowed))
                     (abbreviate-file-name source)
                     (if shadowed
                         (format "; your own %s kept in place of the shipped one"
                                 (string-join shadowed ", "))
                       "")
                     (if failed (format "; failed: %s" (string-join failed ", ")) ""))))
        actions))))

(provide 'ps-skills)
;;; ps-skills.el ends here
