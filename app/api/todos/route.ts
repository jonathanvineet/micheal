import { NextRequest, NextResponse } from 'next/server';
import fs from 'fs';
import path from 'path';

function resolveUploadsDir(): string {
  const attempts = [process.cwd(), path.join(process.cwd(), '..'), path.join(process.cwd(), '..', '..')];
  for (const base of attempts) {
    const candidate = path.join(base, 'uploads');
    if (fs.existsSync(candidate)) return path.resolve(candidate);
  }
  return path.resolve(process.cwd(), 'uploads');
}

const UPLOAD_DIR = resolveUploadsDir();
const TODOS_FILE = path.join(UPLOAD_DIR, 'todos.json');

interface Todo {
  id: string;
  text: string;
  completed: boolean;
  createdAt: string;
}

// Ensure todos file exists
function ensureTodosFile() {
  if (!fs.existsSync(TODOS_FILE)) {
    fs.writeFileSync(TODOS_FILE, JSON.stringify([], null, 2), 'utf-8');
  }
}

// Read todos from file
function readTodos(): Todo[] {
  try {
    ensureTodosFile();
    const data = fs.readFileSync(TODOS_FILE, 'utf-8');
    return JSON.parse(data);
  } catch (error) {
    console.error('Error reading todos:', error);
    return [];
  }
}

// Write todos to file
function writeTodos(todos: Todo[]) {
  try {
    ensureTodosFile();
    fs.writeFileSync(TODOS_FILE, JSON.stringify(todos, null, 2), 'utf-8');
  } catch (error) {
    console.error('Error writing todos:', error);
  }
}

// GET - Retrieve all todos
export async function GET() {
  try {
    const todos = readTodos();
    return NextResponse.json({ todos }, { status: 200 });
  } catch (error) {
    console.error('Error fetching todos:', error);
    return NextResponse.json({ error: 'Failed to fetch todos' }, { status: 500 });
  }
}

// POST - Add a new todo
export async function POST(request: NextRequest) {
  try {
    const body = await request.json();
    const { text } = body;

    if (!text || typeof text !== 'string' || text.trim().length === 0) {
      return NextResponse.json({ error: 'Todo text is required' }, { status: 400 });
    }

    const todos = readTodos();
    const newTodo: Todo = {
      id: Date.now().toString() + Math.random().toString(36).substr(2, 9),
      text: text.trim(),
      completed: false,
      createdAt: new Date().toISOString(),
    };

    todos.push(newTodo);
    writeTodos(todos);

    return NextResponse.json({ todo: newTodo, todos }, { status: 201 });
  } catch (error) {
    console.error('Error creating todo:', error);
    return NextResponse.json({ error: 'Failed to create todo' }, { status: 500 });
  }
}

// PUT - Update a todo (toggle completed or edit text)
export async function PUT(request: NextRequest) {
  try {
    const body = await request.json();
    const { id, completed, text } = body;

    if (!id) {
      return NextResponse.json({ error: 'Todo ID is required' }, { status: 400 });
    }

    const todos = readTodos();
    const todoIndex = todos.findIndex(t => t.id === id);

    if (todoIndex === -1) {
      return NextResponse.json({ error: 'Todo not found' }, { status: 404 });
    }

    // Update fields if provided
    if (typeof completed === 'boolean') {
      todos[todoIndex].completed = completed;
    }
    if (text && typeof text === 'string' && text.trim().length > 0) {
      todos[todoIndex].text = text.trim();
    }

    writeTodos(todos);

    return NextResponse.json({ todo: todos[todoIndex], todos }, { status: 200 });
  } catch (error) {
    console.error('Error updating todo:', error);
    return NextResponse.json({ error: 'Failed to update todo' }, { status: 500 });
  }
}

// DELETE - Remove a todo
export async function DELETE(request: NextRequest) {
  try {
    const { searchParams } = new URL(request.url);
    const id = searchParams.get('id');

    if (!id) {
      return NextResponse.json({ error: 'Todo ID is required' }, { status: 400 });
    }

    const todos = readTodos();
    const filteredTodos = todos.filter(t => t.id !== id);

    if (filteredTodos.length === todos.length) {
      return NextResponse.json({ error: 'Todo not found' }, { status: 404 });
    }

    writeTodos(filteredTodos);

    return NextResponse.json({ todos: filteredTodos }, { status: 200 });
  } catch (error) {
    console.error('Error deleting todo:', error);
    return NextResponse.json({ error: 'Failed to delete todo' }, { status: 500 });
  }
}
