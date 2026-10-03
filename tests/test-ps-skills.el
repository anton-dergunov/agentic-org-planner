;;; test-ps-skills.el --- ERT tests for ps-skills -*- lexical-binding: t; -*-

(require 'ert)
(add-to-list 'load-path "lisp")
(require 'ps-skills)

;; Redeclared so the `let'-bindings below reach `ps/skills-sync' (see the note
;; in tests/test-ps-ai-context.el).
(defvar my-org-base-directory)

;;; The plan

(ert-deftest ps/skills-test-plan-links-absent-names ()
  (should (equal (ps/skills--plan "/cfg/skills/" '("audit" "route") nil nil)
                 '((link "audit" "/cfg/skills/audit")
                   (link "route" "/cfg/skills/route")))))

(ert-deftest ps/skills-test-plan-leaves-correct-links-alone ()
  (should-not (ps/skills--plan "/cfg/skills/" '("route")
                               '(("route" link . "/cfg/skills/route/"))
                               '("route"))))

(ert-deftest ps/skills-test-plan-repoints-a-link-aimed-elsewhere ()
  "An old checkout's link is re-pointed at the current source."
  (should (equal (ps/skills--plan "/cfg/skills/" '("route")
                                  '(("route" link . "/old/skills/route")) nil)
                 '((relink "route" "/cfg/skills/route")))))

(ert-deftest ps/skills-test-plan-never-replaces-a-real-directory ()
  (should (equal (ps/skills--plan "/cfg/skills/" '("route") '(("route" . real)) nil)
                 '((shadowed "route")))))

(ert-deftest ps/skills-test-plan-removes-only-its-own-retired-links ()
  "A link it made for a skill no longer shipped goes; the user's own links stay."
  (should (equal (ps/skills--plan "/cfg/skills/" '("route")
                                  '(("route" link . "/cfg/skills/route")
                                    ("gone" link . "/cfg/skills/gone")
                                    ("mine" link . "/elsewhere/mine"))
                                  '("route" "gone"))
                 '((remove "gone")))))

(ert-deftest ps/skills-test-linked-names-exclude-shadowed ()
  (should (equal (ps/skills--linked-names '("audit" "route") '((shadowed "route")))
                 '("audit"))))

(ert-deftest ps/skills-test-ignore-round-trips ()
  (should (equal (ps/skills--parse-ignore (ps/skills--render-ignore '("_shared" "route")))
                 '("_shared" "route"))))

;;; Against a real directory

(defmacro ps/skills-test--with-dirs (&rest body)
  "Run BODY with `source' holding two skills and `vault' an empty vault."
  (declare (indent 0))
  `(let* ((root (file-name-as-directory (make-temp-file "ps-skills-" t)))
          (source (file-name-as-directory (expand-file-name "skills" root)))
          (vault (file-name-as-directory (expand-file-name "vault" root)))
          (skills (expand-file-name ".claude/skills" vault))
          (ps/skills-directory source)
          (ps/skills-install t)
          (my-org-base-directory vault))
     (ignore skills)
     (dolist (name '("_shared" "route"))
       (make-directory (expand-file-name name source) t))
     (make-directory vault t)
     (unwind-protect (progn ,@body)
       (delete-directory root t))))

(ert-deftest ps/skills-test-sync-links-every-shipped-directory ()
  (ps/skills-test--with-dirs
    (ps/skills-sync)
    (dolist (name '("_shared" "route"))
      (should (equal (file-truename (expand-file-name name skills))
                     (file-truename (expand-file-name name source)))))
    (should (equal (ps/skills--parse-ignore
                    (ps/skills--read-file (expand-file-name ".gitignore" skills)))
                   '("_shared" "route")))))

(ert-deftest ps/skills-test-sync-is-idempotent ()
  "A second run does nothing and leaves the .gitignore's mtime alone."
  (ps/skills-test--with-dirs
    (ps/skills-sync)
    (let* ((ignore (expand-file-name ".gitignore" skills))
           (before (file-attribute-modification-time (file-attributes ignore))))
      (should-not (ps/skills-sync))
      (should (equal before (file-attribute-modification-time
                             (file-attributes ignore)))))))

(ert-deftest ps/skills-test-sync-keeps-a-real-skill ()
  (ps/skills-test--with-dirs
    (make-directory (expand-file-name "route" skills) t)
    (with-temp-file (expand-file-name "route/SKILL.md" skills) (insert "mine"))
    (ps/skills-sync)
    (should-not (file-symlink-p (expand-file-name "route" skills)))
    (should (equal (ps/skills--read-file (expand-file-name "route/SKILL.md" skills))
                   "mine"))
    (should (equal (ps/skills--parse-ignore
                    (ps/skills--read-file (expand-file-name ".gitignore" skills)))
                   '("_shared")))))

(ert-deftest ps/skills-test-sync-removes-a-retired-skill ()
  (ps/skills-test--with-dirs
    (ps/skills-sync)
    (delete-directory (expand-file-name "route" source))
    (ps/skills-sync)
    (should-not (file-symlink-p (expand-file-name "route" skills)))
    (should (file-symlink-p (expand-file-name "_shared" skills)))))

(ert-deftest ps/skills-test-sync-without-a-vault-does-nothing ()
  (ps/skills-test--with-dirs
    (let ((my-org-base-directory nil))
      (should-not (ps/skills-sync)))
    (should-not (file-exists-p skills))))

(ert-deftest ps/skills-test-sync-respects-the-switch ()
  (ps/skills-test--with-dirs
    (let ((ps/skills-install nil))
      (should-not (ps/skills-sync)))
    (should-not (file-exists-p skills))))

;;; The shipped skills themselves

(ert-deftest ps/skills-test-shipped-skills-are-well-formed ()
  "Every shipped skill has a SKILL.md whose name: matches its folder."
  (let ((source (expand-file-name "skills")))
    (dolist (name (ps/skills--shipped source))
      (let ((file (expand-file-name (concat name "/SKILL.md") source)))
        (unless (string-prefix-p "_" name)
          (should (file-exists-p file))
          (let ((text (ps/skills--read-file file)))
            (should (string-match-p (concat "^name: " (regexp-quote name) "$") text))
            (should (string-match-p "^description: ." text))))))))

;;; test-ps-skills.el ends here
