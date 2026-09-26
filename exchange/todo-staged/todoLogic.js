(function (root, factory) {
  var api = factory();
  if (typeof module !== "undefined" && module.exports) {
    module.exports = api;
  }
  if (typeof window !== "undefined") {
    window.todoLogic = api;
  } else if (root) {
    root.todoLogic = api;
  }
})(typeof globalThis !== "undefined" ? globalThis : this, function () {
  "use strict";

  var VALID_FILTERS = ["all", "active", "completed"];

  function emptyState() {
    return { todos: [] };
  }

  function normalizeState(state) {
    if (!state || typeof state !== "object" || !Array.isArray(state.todos)) {
      return emptyState();
    }
    return state;
  }

  function isBlank(text) {
    return typeof text !== "string" || text.trim() === "";
  }

  function nextId(todos) {
    var max = 0;
    for (var i = 0; i < todos.length; i++) {
      var n = Number(todos[i].id);
      if (isFinite(n) && n > max) {
        max = n;
      }
    }
    return max + 1;
  }

  function addTodo(state, text) {
    var current = normalizeState(state);
    if (isBlank(text)) {
      throw new Error("todo text must not be empty or whitespace-only");
    }
    var todo = {
      id: nextId(current.todos),
      text: String(text).trim(),
      completed: false
    };
    return { todos: current.todos.concat([todo]) };
  }

  function toggleTodo(state, id) {
    var current = normalizeState(state);
    var todos = current.todos.map(function (todo) {
      if (todo.id === id) {
        return { id: todo.id, text: todo.text, completed: !todo.completed };
      }
      return todo;
    });
    return { todos: todos };
  }

  function editTodo(state, id, newText) {
    var current = normalizeState(state);
    if (isBlank(newText)) {
      throw new Error("todo text must not be empty or whitespace-only");
    }
    var todos = current.todos.map(function (todo) {
      if (todo.id === id) {
        return { id: todo.id, text: String(newText).trim(), completed: todo.completed };
      }
      return todo;
    });
    return { todos: todos };
  }

  function deleteTodo(state, id) {
    var current = normalizeState(state);
    var todos = current.todos.filter(function (todo) {
      return todo.id !== id;
    });
    return { todos: todos };
  }

  function clearCompleted(state) {
    var current = normalizeState(state);
    var todos = current.todos.filter(function (todo) {
      return !todo.completed;
    });
    return { todos: todos };
  }

  function getFiltered(state, filter) {
    var current = normalizeState(state);
    if (VALID_FILTERS.indexOf(filter) === -1) {
      throw new Error('invalid filter: expected "all", "active" or "completed"');
    }
    var todos = current.todos.filter(function (todo) {
      if (filter === "active") return !todo.completed;
      if (filter === "completed") return todo.completed;
      return true;
    });
    return { todos: todos };
  }

  function counts(state) {
    var current = normalizeState(state);
    var total = current.todos.length;
    var completed = 0;
    for (var i = 0; i < current.todos.length; i++) {
      if (current.todos[i].completed) completed++;
    }
    return { total: total, active: total - completed, completed: completed };
  }

  return {
    emptyState: emptyState,
    addTodo: addTodo,
    toggleTodo: toggleTodo,
    editTodo: editTodo,
    deleteTodo: deleteTodo,
    clearCompleted: clearCompleted,
    getFiltered: getFiltered,
    counts: counts
  };
});
