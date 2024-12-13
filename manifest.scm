(use-modules (guix profiles) (guix-stack-channel))
;; guix shell -L src -m manifest.scm
(package->development-manifest guix-stack/devel)
