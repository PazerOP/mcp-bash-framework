# Windows Support Notes

- Git-Bash/MSYS drive prefixes (e.g., `C:\foo`) are translated to `/c/foo` by providers to avoid lookup failures (Spec §12).
- Signal delivery (`kill -TERM`) may be unreliable; prefer WSL for production deployments.
- Ensure `MSYS2_ARG_CONV_EXCL=*` is set when passing raw Windows paths to tools to avoid unwanted conversion.
- Python fallback and JSON tooling may need manual installation (`pacman -S python jq`).
