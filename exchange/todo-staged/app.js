(function () {
  "use strict";

  var STORAGE_KEY = "todo-state";
  var logic = window.todoLogic;

  var addForm = document.getElementById("add-form");
  var newTodoInput = document.getElementById("new-todo");
  var listEl = document.getElementById("todo-list");
  var emptyStateEl = document.getElementById("empty-state");
  var counterEl = document.getElementById("counter");
  var clearCompletedBtn = document.getElementById("clear-completed");
  var filterBtns = Array.prototype.slice.call(
    document.querySelectorAll(".filter-btn")
  );

  var state = loadState();
  var filter = "all";

  function loadState() {
    try {
      var raw = window.localStorage.getItem(STORAGE_KEY);
      if (!raw) return logic.emptyState();
      var parsed = JSON.parse(raw);
      if (parsed && Array.isArray(parsed.todos)) {
        return {
          todos: parsed.todos.map(function (todo) {
            return {
              id: todo.id,
              text: String(todo.text),
              completed: Boolean(todo.completed)
            };
          })
        };
      }
    } catch (err) {
      /* corrupt or unavailable storage: start fresh */
    }
    return logic.emptyState();
  }

  function saveState() {
    try {
      window.localStorage.setItem(STORAGE_KEY, JSON.stringify(state));
    } catch (err) {
      /* storage may be unavailable (private mode); app still works */
    }
  }

  function apply(nextState) {
    state = nextState;
    saveState();
    render();
  }

  function render() {
    var visible = logic.getFiltered(state, filter).todos;
    var summary = logic.counts(state);

    listEl.innerHTML = "";

    visible.forEach(function (todo) {
      listEl.appendChild(renderItem(todo));
    });

    emptyStateEl.hidden = visible.length !== 0;

    clearCompletedBtn.disabled = summary.completed === 0;

    counterEl.textContent =
      summary.active + (summary.active === 1 ? " item left" : " items left");
  }

  function renderItem(todo) {
    var li = document.createElement("li");
    li.className = "todo-item" + (todo.completed ? " is-completed" : "");
    li.dataset.id = String(todo.id);

    var checkbox = document.createElement("input");
    checkbox.type = "checkbox";
    checkbox.className = "toggle";
    checkbox.checked = todo.completed;
    checkbox.setAttribute("aria-label", "Toggle todo");
    checkbox.addEventListener("change", function () {
      apply(logic.toggleTodo(state, todo.id));
    });

    var span = document.createElement("span");
    span.className = "todo-text";
    span.textContent = todo.text;
    span.title = "Double-click to edit";
    span.addEventListener("dblclick", function () {
      startEdit(li, todo);
    });

    var del = document.createElement("button");
    del.type = "button";
    del.className = "delete-btn";
    del.textContent = "\u00d7";
    del.setAttribute("aria-label", "Delete todo");
    del.addEventListener("click", function () {
      apply(logic.deleteTodo(state, todo.id));
    });

    li.appendChild(checkbox);
    li.appendChild(span);
    li.appendChild(del);
    return li;
  }

  function startEdit(li, todo) {
    var input = document.createElement("input");
    input.type = "text";
    input.className = "edit-input";
    input.value = todo.text;

    var span = li.querySelector(".todo-text");
    li.replaceChild(input, span);
    input.focus();
    input.setSelectionRange(input.value.length, input.value.length);

    var committed = false;
    function commit() {
      if (committed) return;
      committed = true;
      var value = input.value;
      if (value.trim() === "") {
        apply(logic.deleteTodo(state, todo.id));
      } else {
        apply(logic.editTodo(state, todo.id, value));
      }
    }

    input.addEventListener("blur", commit);
    input.addEventListener("keydown", function (event) {
      if (event.key === "Enter") {
        event.preventDefault();
        commit();
      } else if (event.key === "Escape") {
        committed = true;
        render();
      }
    });
  }

  addForm.addEventListener("submit", function (event) {
    event.preventDefault();
    var text = newTodoInput.value;
    if (text.trim() === "") {
      newTodoInput.value = "";
      return;
    }
    apply(logic.addTodo(state, text));
    newTodoInput.value = "";
    newTodoInput.focus();
  });

  clearCompletedBtn.addEventListener("click", function () {
    apply(logic.clearCompleted(state));
  });

  filterBtns.forEach(function (btn) {
    btn.addEventListener("click", function () {
      filter = btn.dataset.filter;
      filterBtns.forEach(function (other) {
        other.classList.toggle("is-active", other === btn);
      });
      render();
    });
  });

  render();
})();
