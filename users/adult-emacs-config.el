;;; adult-emacs-config.el
;;; Shared, modern Emacs configuration for adults (nicky, aeiuno).
;;;
;;; All packages are supplied by Nix (programs.emacs.extraPackages), so this
;;; file performs no package fetching or compilation at runtime. It targets
;;; GNU Emacs 29+ where `use-package` is built in.

;; ---- Core defaults -------------------------------------------------------
(setq-default
  indent-tabs-mode nil
  tab-width 4
  truncate-lines t
  make-backup-files nil            ; no foo~ litter
  auto-save-default t
  create-lockfiles nil             ; no .#foo litter
  require-final-newline t
  ring-bell-function #'ignore      ; no beeping
  sentence-end-double-space nil)

(electric-pair-mode 1)             ; auto-close (), [], {}, ""
(show-paren-mode 1)                ; highlight the matching paren
(global-display-line-numbers-mode 1)
(column-number-mode 1)
(savehist-mode 1)                  ; remember minibuffer history
(save-place-mode 1)                ; reopen files where you left off
(global-auto-revert-mode 1)        ; auto-reload files changed on disk
(winner-mode 1)                    ; undo window layout changes with C-x <left>/<right>

;; ---- UI -------------------------------------------------------------------
(menu-bar-mode -1)
(tool-bar-mode -1)
(scroll-bar-mode -1)
(blink-cursor-mode -1)
(setq use-dialog-box nil)          ; use the minibuffer, not popup dialogs

;; Built-in, high-contrast light theme; F5 toggles light/dark.
(load-theme 'modus-operandi t)
(define-key global-map (kbd "<f5>") #'modus-themes-toggle)

;; Keep customizations out of this file.
(setq custom-file (expand-file-name "custom.el" user-emacs-directory))
(when (file-exists-p custom-file)
  (load custom-file))

;; ---- Minibuffer completion (vertico/orderless/marginalia/consult) ----------
(use-package vertico
  :init
  (vertico-mode))

(use-package orderless
  :config
  (setq completion-styles '(orderless basic)
        completion-category-overrides
        '((file (styles basic partial-completion)))))

(use-package marginalia
  :init
  (marginalia-mode))

(use-package consult
  :bind
  (("M-s l" . consult-line)
   ("C-x b" . consult-buffer)
   ("C-x C-r" . consult-recent-file))
  :config
  (recentf-mode 1))

(use-package corfu
  :init
  (global-corfu-mode))

(use-package which-key
  :config
  (which-key-mode 1))

;; ---- Tools -----------------------------------------------------------------
(use-package magit
  :bind ("C-x g" . magit-status))

(use-package markdown-mode
  :mode ("\\.md\\'" . markdown-mode))

(use-package typescript-mode
  :mode ("\\.tsx?\\'" . typescript-mode)
  :config
  (setq typescript-indent-level 2))

(use-package nix-mode
  :mode "\\.nix\\'")

(use-package typst-ts-mode
  :mode "\\.typ\\'")

(use-package tex
  :mode "\\.tex\\'"
  :custom (TeX-parse-self t)
  (TeX-auto-save t))

(use-package rust-mode
  :mode "\\.rs\\'")

(use-package go-mode
  :mode "\\.go\\'")

(use-package haskell-mode
  :mode "\\.\\(?:hs\\|lhs\\)\\'")

(use-package csharp-mode
  :mode "\\.cs\\'")

(use-package purescript-mode
  :mode "\\.purs\\'")

;; ---- Language servers (eglot, built into Emacs 29) --------------------------
;; eglot talks to the LSP servers installed by Nix (see users/emacs-adult.nix,
;; home.packages). Servers are started automatically for the major modes listed
;; below; language servers not installed for a mode just stay unused.
;; Keybindings (prefix "C-c e"): r rename, a code actions, f format, q shutdown.
(use-package eglot
  :hook ((typst-ts-mode
          markdown-mode
          LaTeX-mode
          latex-mode
          java-mode
          csharp-mode
          typescript-mode
          js-mode
          purescript-mode
          haskell-mode
          rust-mode
          c-mode
          c++-mode
          go-mode)
         . eglot-ensure)
  :bind
  (("C-c e r" . eglot-rename)
   ("C-c e a" . eglot-code-actions)
   ("C-c e f" . eglot-format)
   ("C-c e q" . eglot-shutdown))
  :config
  (dolist (entry '((typst-ts-mode . ("tinymist"))
                   (markdown-mode . ("marksman"))
                   (LaTeX-mode latex-mode . ("texlab"))
                   (java-mode . ("jdtls"))
                   (csharp-mode . ("csharp-ls"))
                   ((js-mode typescript-mode) . ("typescript-language-server" "--stdio"))
                   (purescript-mode . ("purescript-language-server" "--stdio"))
                   (haskell-mode haskell-literate-mode . ("haskell-language-server-wrapper" "--lsp"))
                   (rust-mode . ("rust-analyzer"))
                   ((c-mode c++-mode) . ("clangd"))
                   (go-mode . ("gopls"))))
    (add-to-list 'eglot-server-programs entry)))

;; ---- Org mode ---------------------------------------------------------------
;; org-mode ships with Emacs; heavy org packages (org-roam, org-modern) are
;; intentionally NOT in programs.emacs.extraPackages because they force a
;; native-compilation rebuild of org (see users/emacs-adult.nix).
(setq org-directory (expand-file-name "~/Notes" (getenv "USER"))
      org-startup-with-inline-images t)
