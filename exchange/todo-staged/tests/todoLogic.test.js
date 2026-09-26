"use strict";

const test = require("node:test");
const assert = require("node:assert");
const logic = require("../todoLogic.js");

function stateWith(texts) {
  let state = logic.emptyState();
  texts.forEach((text) => {
    state = logic.addTodo(state, text);
  });
  return state;
}

test("emptyState returns empty todo list", () => {
  assert.deepStrictEqual(logic.emptyState(), { todos: [] });
});

test("addTodo adds a todo with id, text and completed=false", () => {
  const state = logic.addTodo(logic.emptyState(), "buy milk");
  assert.strictEqual(state.todos.length, 1);
  assert.strictEqual(state.todos[0].text, "buy milk");
  assert.strictEqual(state.todos[0].completed, false);
  assert.ok(state.todos[0].id !== undefined && state.todos[0].id !== null);
});

test("addTodo does not mutate the input state", () => {
  const before = logic.emptyState();
  const after = logic.addTodo(before, "write tests");
  assert.deepStrictEqual(before, { todos: [] });
  assert.strictEqual(after.todos.length, 1);
});

test("addTodo trims surrounding whitespace", () => {
  const state = logic.addTodo(logic.emptyState(), "  padded text  ");
  assert.strictEqual(state.todos[0].text, "padded text");
});

test("addTodo rejects empty string", () => {
  assert.throws(() => logic.addTodo(logic.emptyState(), ""), /empty|whitespace/i);
});

test("addTodo rejects whitespace-only string", () => {
  assert.throws(() => logic.addTodo(logic.emptyState(), "   \t\n "), /empty|whitespace/i);
});

test("addTodo assigns unique ids", () => {
  const state = stateWith(["a", "b", "c"]);
  const ids = state.todos.map((todo) => todo.id);
  assert.strictEqual(new Set(ids).size, ids.length);
});

test("addTodo allows duplicate texts", () => {
  const state = stateWith(["same", "same"]);
  assert.strictEqual(state.todos.length, 2);
  assert.strictEqual(state.todos[0].text, state.todos[1].text);
  assert.notStrictEqual(state.todos[0].id, state.todos[1].id);
});

test("toggleTodo flips completed without mutating input", () => {
  const state = stateWith(["task"]);
  const id = state.todos[0].id;
  const toggled = logic.toggleTodo(state, id);
  assert.strictEqual(toggled.todos[0].completed, true);
  assert.strictEqual(state.todos[0].completed, false);
  const toggledBack = logic.toggleTodo(toggled, id);
  assert.strictEqual(toggledBack.todos[0].completed, false);
});

test("toggleTodo leaves other todos unchanged", () => {
  const state = stateWith(["one", "two"]);
  const toggled = logic.toggleTodo(state, state.todos[0].id);
  assert.strictEqual(toggled.todos[0].completed, true);
  assert.strictEqual(toggled.todos[1].completed, false);
});

test("toggleTodo with unknown id is a no-op", () => {
  const state = stateWith(["one"]);
  const result = logic.toggleTodo(state, 9999);
  assert.deepStrictEqual(result, state);
});

test("editTodo changes text and preserves completed flag", () => {
  let state = stateWith(["old"]);
  const id = state.todos[0].id;
  state = logic.toggleTodo(state, id);
  const edited = logic.editTodo(state, id, "new");
  assert.strictEqual(edited.todos[0].text, "new");
  assert.strictEqual(edited.todos[0].completed, true);
});

test("editTodo trims whitespace", () => {
  const state = stateWith(["old"]);
  const edited = logic.editTodo(state, state.todos[0].id, "   spaced   ");
  assert.strictEqual(edited.todos[0].text, "spaced");
});

test("editTodo rejects empty string", () => {
  const state = stateWith(["old"]);
  assert.throws(() => logic.editTodo(state, state.todos[0].id, ""), /empty|whitespace/i);
});

test("editTodo rejects whitespace-only string", () => {
  const state = stateWith(["old"]);
  assert.throws(
    () => logic.editTodo(state, state.todos[0].id, "   "),
    /empty|whitespace/i
  );
});

test("editTodo does not mutate input state", () => {
  const state = stateWith(["old"]);
  logic.editTodo(state, state.todos[0].id, "new");
  assert.strictEqual(state.todos[0].text, "old");
});

test("deleteTodo removes the matching todo and does not mutate input", () => {
  const state = stateWith(["keep", "remove"]);
  const removeId = state.todos[1].id;
  const result = logic.deleteTodo(state, removeId);
  assert.strictEqual(result.todos.length, 1);
  assert.strictEqual(result.todos[0].text, "keep");
  assert.strictEqual(state.todos.length, 2);
});

test("deleteTodo with unknown id is a no-op", () => {
  const state = stateWith(["keep"]);
  const result = logic.deleteTodo(state, 12345);
  assert.deepStrictEqual(result, state);
});

test("clearCompleted removes only completed todos", () => {
  let state = stateWith(["a", "b", "c"]);
  state = logic.toggleTodo(state, state.todos[0].id);
  state = logic.toggleTodo(state, state.todos[2].id);
  const cleared = logic.clearCompleted(state);
  assert.strictEqual(cleared.todos.length, 1);
  assert.strictEqual(cleared.todos[0].text, "b");
  assert.strictEqual(state.todos.length, 3);
});

test("clearCompleted on state with none completed is a no-op copy", () => {
  const state = stateWith(["a", "b"]);
  const cleared = logic.clearCompleted(state);
  assert.deepStrictEqual(cleared, state);
});

test("getFiltered('all') returns every todo", () => {
  let state = stateWith(["a", "b"]);
  state = logic.toggleTodo(state, state.todos[0].id);
  const filtered = logic.getFiltered(state, "all");
  assert.strictEqual(filtered.todos.length, 2);
});

test("getFiltered('active') returns only incomplete todos", () => {
  let state = stateWith(["a", "b", "c"]);
  state = logic.toggleTodo(state, state.todos[0].id);
  const filtered = logic.getFiltered(state, "active");
  assert.strictEqual(filtered.todos.length, 2);
  assert.ok(filtered.todos.every((todo) => !todo.completed));
});

test("getFiltered('completed') returns only complete todos", () => {
  let state = stateWith(["a", "b", "c"]);
  state = logic.toggleTodo(state, state.todos[0].id);
  state = logic.toggleTodo(state, state.todos[1].id);
  const filtered = logic.getFiltered(state, "completed");
  assert.strictEqual(filtered.todos.length, 2);
  assert.ok(filtered.todos.every((todo) => todo.completed));
});

test("getFiltered does not mutate input state", () => {
  const state = stateWith(["a", "b"]);
  logic.getFiltered(state, "active");
  assert.strictEqual(state.todos.length, 2);
});

test("getFiltered rejects an invalid filter", () => {
  const state = stateWith(["a"]);
  assert.throws(() => logic.getFiltered(state, "bogus"), /invalid filter/i);
});

test("counts returns total, active and completed", () => {
  let state = stateWith(["a", "b", "c"]);
  state = logic.toggleTodo(state, state.todos[0].id);
  assert.deepStrictEqual(logic.counts(state), { total: 3, active: 2, completed: 1 });
});

test("counts on empty state returns zeros", () => {
  assert.deepStrictEqual(logic.counts(logic.emptyState()), {
    total: 0,
    active: 0,
    completed: 0
  });
});

test("functions tolerate missing/invalid state by treating it as empty", () => {
  const added = logic.addTodo(undefined, "recovered");
  assert.strictEqual(added.todos.length, 1);
  assert.deepStrictEqual(logic.counts(null), { total: 0, active: 0, completed: 0 });
});
