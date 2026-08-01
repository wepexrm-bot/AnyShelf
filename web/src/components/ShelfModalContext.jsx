import React, { createContext, useContext, useState } from "react";
import ShelfForm from "./ShelfForm";
import { api } from "../api";

export const SHELVES_CHANGED = "shelves-changed";

const ShelfModalContext = createContext({
  openCreateShelf: () => {},
  openEditShelf: () => {},
});

export function useShelfModal() {
  return useContext(ShelfModalContext);
}

export function ShelfModalProvider({ children }) {
  const [open, setOpen] = useState(false);
  const [editShelf, setEditShelf] = useState(null);
  const [books, setBooks] = useState([]);

  const loadBooks = async () => {
    setBooks(await api("/books/").catch(() => []));
  };

  const openCreateShelf = () => {
    setEditShelf(null);
    setOpen(true);
    loadBooks();
  };

  const openEditShelf = (shelf) => {
    setEditShelf(shelf);
    setOpen(true);
    loadBooks();
  };

  const handleSaved = () => {
    setOpen(false);
    window.dispatchEvent(new CustomEvent(SHELVES_CHANGED));
  };

  return (
    <ShelfModalContext.Provider value={{ openCreateShelf, openEditShelf }}>
      {children}
      {open && (
        <ShelfForm initial={editShelf} books={books} onClose={() => setOpen(false)} onSaved={handleSaved} />
      )}
    </ShelfModalContext.Provider>
  );
}
