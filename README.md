# git-mediate.nvim

Neovim integration for [git-mediate](https://github.com/Peaker/git-mediate) - a tool that transforms git conflict resolution from a nightmare into a breeze.

![git-mediate.nvim in action](FinalGitMediate.gif)

## What is Git Mediate?

The philosophy of git-mediate is simple:

1. Identify which of the two changes is simpler
2. Apply that simpler change to the other two hunks
3. Run git-mediate
4. The conflict is resolved!

Instead of mentally merging both sides of a conflict, you pick the simpler side and mirror it. Git-mediate then auto-resolves by detecting when one hunk matches the base.

### Example 1 — Adding Logging

Say we have this conflict:

```javascript
<<<<<<< HEAD
function calculate(a, b) {
    logger.debug("Calculating sum of", a, "and", b);
    return a + b;
||||||| 86dd402
function calculate(a, b) {
    return a + b;
=======
function calculate(a, b) {
    if (typeof a !== "number" || typeof b !== "number") {
        throw new TypeError("Both arguments must be numbers");
    }
    return a + b
>>>>>>> feature-branch
}
```

The simpler change is the logging addition. Apply it to the base and theirs sections:

```javascript
<<<<<<< HEAD
function calculate(a, b) {
    logger.debug("Calculating sum of", a, "and", b);
    return a + b;
||||||| 86dd402
function calculate(a, b) {
    logger.debug("Calculating sum of", a, "and", b);
    return a + b;
=======
function calculate(a, b) {
    logger.debug("Calculating sum of", a, "and", b);

    if (typeof a !== "number" || typeof b !== "number") {
        throw new TypeError("Both arguments must be numbers");
    }
    return a + b
>>>>>>> feature-branch
}
```

Now git-mediate detects the top hunk equals the base, so it chooses the other side and runs `git add`.

### Example 2 — Variable Rename vs Logic Change

```javascript
<<<<<<< HEAD
function calculate(x, y) {
    logger.debug("Calculating sum of", x, "and", y);

    if (typeof y !== "number" || typeof x !== "number") {
        throw new TypeError("Both arguments must be numbers");
    }
    return x + y
||||||| 86dd402
function calculate(a, b) {
    logger.debug("Calculating sum of", a, "and", b);

    if (typeof a !== "number" || typeof b !== "number") {
        throw new TypeError("Both arguments must be numbers");
    }
    return a + b
=======
function calculate(a, b) {
    // ... complex logic changes ...
    return result
>>>>>>> feature-branch
}
```

One side renames variables, the other adds complex code. Simply rename the variables in the base and theirs sections — git-mediate handles the rest.

## The Plugin

This plugin provides:

- **Character-level diff highlighting** in the buffer itself (similar to Emacs's smerge)
- **Quick conflict navigation** via quickfix list

## Requirements

- Neovim 0.9+
- [git-mediate](https://github.com/Peaker/git-mediate) CLI
- [vscode-diff.nvim](https://github.com/esmuellert/vscode-diff.nvim)

## Installation

```lua
-- lazy.nvim
{
    "Sharonex/git-mediate.nvim",
    dependencies = { "esmuellert/vscode-diff.nvim" },
    config = function()
        require("git-mediate").setup()
    end,
}
```

## Commands

| Command | Description |
|---------|-------------|
| `:GitMediate` | Save, run git-mediate, show remaining conflicts in quickfix |
| `:GitMediateToggle` | Toggle diff view between Ours vs Base / Theirs vs Base |

## Keymaps

Default: `<leader>g[` runs `:GitMediate`

In quickfix: `<CR>` jumps to conflict location.

## Highlighting

Conflicts are automatically highlighted with character-level diffs:
- Green: Ours section
- Blue: Base section
- Red: Theirs section

## Credits

- [git-mediate](https://github.com/Peaker/git-mediate) — the conflict resolution engine
- [vscode-diff.nvim](https://github.com/esmuellert/vscode-diff.nvim) — character-level diff algorithm
