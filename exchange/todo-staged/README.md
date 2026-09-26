# todo

A tiny, dependency-free todo-list tracker for the browser.

## What it is

A single-page vanilla web app with no build step and no dependencies:

- Add todos with the form at the top.
- Toggle a todo complete by clicking its checkbox.
- Edit a todo by double-clicking its text (Enter saves, Escape cancels; saving
  an empty value deletes the todo).
- Delete a todo with the `×` button.
- Filter with **All** / **Active** / **Completed**.
- **Clear completed** removes all finished todos.
- The counter shows how many active items are left.
- State is persisted to `localStorage` under the key `todo-state`, so it
  survives reloads.

Core logic lives in `todoLogic.js` as pure, immutable functions (no DOM, no
storage) shared by both the browser and Node tests. `app.js` handles DOM wiring
and persistence only.

## How to open it

No server or install required. Open `index.html` directly in a browser
(double-click the file, or drag it into a browser window). Everything runs from
the local files.

> Note: some browsers restrict `localStorage` on the `file://` protocol. If
> persistence does not work, serve the folder locally, e.g.
> `python3 -m http.server` from this directory, then visit
> <http://localhost:8000>.

## How to run tests

Tests use only Node built-ins, so there is nothing to install:

```sh
node --test tests/
```

Run it from this directory. All tests should pass with exit code 0.
