# Optional Office conversion engine

LibreOffice Kit is an optional external dependency; it is not bundled with these skills. Before an operation that requires it, check user configuration and already installed, usable Kit/Node CLI locations. A missing command on PATH alone does not establish whether a configured installation exists.

If no usable installation is available, do not download or install anything automatically. Continue work that does not require the engine and report the limitation. Any installation requires existing user authorization and the environment's approved dependency workflow; authorization for this engine does not authorize installing Python, Node.js, or a package manager. Keep any task-local package data and temporary files inside the current session scratch directory.

When using a configured installation, invoke its actual executable and CLI paths and check the operation's result. If it fails, preserve the source and report the failure; do not silently fall back to system `soffice`, `npx`, or another conversion pipeline.
