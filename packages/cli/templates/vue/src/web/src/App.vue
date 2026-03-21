<script setup lang="ts">
import { ref, onMounted, computed } from 'vue'

interface Todo {
    id: number
    text: string
    done: boolean
}

const todos = ref<Todo[]>([])
const input = ref('')

onMounted(async () => {
    const res = await fetch('/api/todos')
    todos.value = await res.json()
})

const addTodo = async () => {
    const text = input.value.trim()
    if (!text) return

    const res = await fetch('/api/todos', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ text })
    })
    const todo = await res.json()
    todos.value.push(todo)
    input.value = ''
}

const toggleTodo = async (id: number) => {
    const todo = todos.value.find(t => t.id === id)
    if (!todo) return

    const res = await fetch(`/api/todos/${id}`, {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ done: !todo.done })
    })
    const updated = await res.json()
    const idx = todos.value.findIndex(t => t.id === id)
    if (idx !== -1) todos.value[idx] = updated
}

const deleteTodo = async (id: number) => {
    await fetch(`/api/todos/${id}`, { method: 'DELETE' })
    todos.value = todos.value.filter(t => t.id !== id)
}

const onKeyDown = (e: KeyboardEvent) => {
    if (e.key === 'Enter') addTodo()
}

const remaining = computed(() => todos.value.filter(t => !t.done).length)
</script>

<template>
    <div class="app">
        <h1>{{ '{{APP_NAME}}' }}</h1>
        <div class="input-row">
            <input
                v-model="input"
                @keydown="onKeyDown"
                placeholder="Add a todo..."
            />
            <button @click="addTodo">Add</button>
        </div>
        <p v-if="todos.length > 0" class="count">
            {{ remaining }} remaining
        </p>
        <div v-for="todo in todos" :key="todo.id" class="todo-item">
            <input
                type="checkbox"
                :checked="todo.done"
                @change="toggleTodo(todo.id)"
            />
            <span :class="{ done: todo.done }">{{ todo.text }}</span>
            <button class="delete-btn" @click="deleteTodo(todo.id)">&times;</button>
        </div>
        <p class="footer">
            Powered by <strong>Tano</strong> &mdash; on-device Bun server + WebView
        </p>
    </div>
</template>

<style>
* { box-sizing: border-box; margin: 0; padding: 0; }
body { background: #f5f5f5; }

.app {
    max-width: 500px;
    margin: 40px auto;
    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
    padding: 0 16px;
}

h1 {
    font-size: 2rem;
    font-weight: 700;
    margin-bottom: 24px;
    color: #1d1d1f;
}

.input-row {
    display: flex;
    gap: 8px;
    margin-bottom: 20px;
}

.input-row input {
    flex: 1;
    padding: 12px 16px;
    border-radius: 10px;
    border: 1px solid #d2d2d7;
    font-size: 16px;
    outline: none;
    transition: border-color 0.2s;
}

.input-row input:focus {
    border-color: #007AFF;
}

.input-row button {
    padding: 12px 24px;
    border-radius: 10px;
    background: #007AFF;
    color: white;
    border: none;
    font-size: 16px;
    font-weight: 600;
    cursor: pointer;
    transition: opacity 0.2s;
}

.input-row button:active {
    opacity: 0.8;
}

.count {
    font-size: 0.85rem;
    color: #86868b;
    margin-bottom: 12px;
}

.todo-item {
    display: flex;
    align-items: center;
    gap: 12px;
    padding: 12px 0;
    border-bottom: 1px solid #eee;
}

.todo-item input[type="checkbox"] {
    width: 20px;
    height: 20px;
    accent-color: #007AFF;
    cursor: pointer;
}

.todo-item span {
    flex: 1;
    font-size: 15px;
    color: #333;
}

.todo-item span.done {
    text-decoration: line-through;
    color: #999;
}

.delete-btn {
    background: none;
    border: none;
    color: #ff3b30;
    font-size: 18px;
    cursor: pointer;
    padding: 4px 8px;
    opacity: 0;
    transition: opacity 0.15s;
}

.todo-item:hover .delete-btn {
    opacity: 1;
}

.footer {
    margin-top: 24px;
    color: #999;
    font-size: 14px;
}

.footer strong {
    color: #1d1d1f;
}
</style>
