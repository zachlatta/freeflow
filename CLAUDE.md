## Agent Guardrails

You are running as an agent. Do not run destructive commands without explicit permission.

### Git
- Never run `git push --force`, `git push -f`, or rewrite shared history
- Never delete branches (local or remote) without explicit permission
- Never commit `.env*` files, API keys, tokens, or credentials

### Filesystem
- Never run `rm -rf` on anything outside the current project directory
- Never modify files outside the current working directory without explicit permission
- Never edit `.env`, `.env.local`, or any `.env.*` file without explicit permission

### Dependencies
- Ask before installing new packages or running `npm install <pkg>`
- Ask before upgrading major versions or modifying lockfiles by hand

### Database
- Never run database migrations, drops, or schema changes without explicit permission

### Behavior
- When uncertain, stop and ask rather than guess
- Summarize planned changes before applying anything non-trivial
- Don't disable, skip, or comment out tests, linting, or type checks to make things pass
