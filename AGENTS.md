## Git Commit Conventions

- Follow the Conventional Commits specification (v1.0.0).
- Use the format: `type(scope): description`.
- Scope is optional.
- Allowed types: `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `build`, `ci`, `chore`, `revert`.
- Write commit messages in English.
- Use lowercase types and scopes.
- Use the imperative mood in descriptions (e.g., "add", not "added").
- Do not capitalize the first letter of descriptions unless necessary.
- Do not end descriptions with a period.
- Keep the subject line under 72 characters.
- Keep each commit focused on a single logical change.
- For breaking changes, use `!` after the type/scope or a `BREAKING CHANGE:` footer.
- Use `chore: initial commit` for the initial repository commit.
- When creating Git commits, always follow these conventions.
- Do not create Git commits unless explicitly requested.

## Pre-commit Formatting

- Run `./scripts/install-hooks.sh` after cloning to enable the repository hooks.
- The pre-commit hook formats staged `.swift` files using `swift-format` and the staged `.swift-format` configuration.
- Unstaged edits are preserved. If a file is partially staged, only its staged content is formatted.
- The hook requires Python 3 and `swift-format` (available through Xcode's `xcrun` on macOS).
