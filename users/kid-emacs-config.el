;;; kid-emacs-config.el
;;; Dead-simple, friendly Emacs configuration for the kids (aaron, sven).
;;;
;;; Everything is clickable and nothing needs configuring. The goal is to
;;; gradually grow into Emacs, so the familiar menus, toolbars and the
;;; built-in tutorial (Help > Emacs Tutorial) stay available.

;; Keep the familiar GUI chrome so it feels like a normal application.
(menu-bar-mode 1)
(tool-bar-mode 1)
(scroll-bar-mode 1)

;; Friendly defaults.
(setq
  make-backup-files nil            ; no foo~ litter
  auto-save-default t              ; autosave
  create-lockfiles nil             ; no .#foo litter
  ring-bell-function #'ignore      ; no beeping
  use-dialog-box t)

;; Visual helpers.
(global-display-line-numbers-mode 1) ; line numbers on the left
(electric-pair-mode 1)               ; auto-close brackets and quotes
(show-paren-mode 1)                  ; highlight the matching bracket
(global-hl-line-mode 1)              ; highlight the current line
(save-place-mode 1)                  ; reopen files where you left off

;; Light, gentle theme built into Emacs.
(load-theme 'modus-operandi t)

;; Show the key combinations as you type them, so shortcuts are learned by
;; discovering them instead of memorizing them.
(which-key-mode 1)

;; Spaces instead of tabs for indentation.
(setq-default indent-tabs-mode nil)
