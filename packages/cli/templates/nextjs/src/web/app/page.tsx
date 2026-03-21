'use client'

import { useState, useEffect } from 'react'

interface Todo {
    id: number
    text: string
    done: boolean
}

export default function Home() {
    const [todos, setTodos] = useState<Todo[]>([])
    const [input, setInput] = useState('')

    useEffect(() => {
        fetch('/api/todos').then(r => r.json()).then(setTodos).catch(() => {})
    }, [])

    const addTodo = async () => {
        if (!input.trim()) return
        const res = await fetch('/api/todos', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ text: input })
        })
        const todo = await res.json()
        setTodos([...todos, todo])
        setInput('')
    }

    const toggleTodo = async (id: number) => {
        const todo = todos.find(t => t.id === id)!
        const res = await fetch(`/api/todos/${id}`, {
            method: 'PATCH',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ done: !todo.done })
        })
        const updated = await res.json()
        setTodos(todos.map(t => t.id === id ? updated : t))
    }

    const deleteTodo = async (id: number) => {
        await fetch(`/api/todos/${id}`, { method: 'DELETE' })
        setTodos(todos.filter(t => t.id !== id))
    }

    return (
        <main style={{ maxWidth: 500, margin: '40px auto', padding: '0 20px' }}>
            <h1>{{APP_NAME}}</h1>
            <p style={{ color: '#666', marginBottom: 20 }}>Next.js + Tano on-device server</p>
            <div style={{ display: 'flex', gap: 8, marginBottom: 20 }}>
                <input
                    value={input}
                    onChange={e => setInput(e.target.value)}
                    onKeyDown={e => e.key === 'Enter' && addTodo()}
                    placeholder="Add a todo..."
                    style={{ flex: 1, padding: '10px 14px', borderRadius: 8, border: '1px solid #ddd', fontSize: 16 }}
                />
                <button onClick={addTodo} style={{ padding: '10px 20px', borderRadius: 8, background: '#0070f3', color: 'white', border: 'none', fontSize: 16, cursor: 'pointer' }}>
                    Add
                </button>
            </div>
            {todos.map(todo => (
                <div key={todo.id} style={{ display: 'flex', alignItems: 'center', gap: 10, padding: '12px 0', borderBottom: '1px solid #eee' }}>
                    <input type="checkbox" checked={todo.done} onChange={() => toggleTodo(todo.id)} />
                    <span style={{ flex: 1, textDecoration: todo.done ? 'line-through' : 'none', color: todo.done ? '#999' : '#333' }}>{todo.text}</span>
                    <button onClick={() => deleteTodo(todo.id)} style={{ background: 'none', border: 'none', color: '#ff3b30', cursor: 'pointer', fontSize: 18 }}>×</button>
                </div>
            ))}
            <p style={{ marginTop: 30, color: '#999', fontSize: 13 }}>
                Powered by <strong>Tano</strong> — Next.js static export + on-device Bun server
            </p>
        </main>
    )
}
