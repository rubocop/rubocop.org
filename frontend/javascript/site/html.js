// For text that ends up in innerHTML.
export const escape = (text) =>
  String(text).replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c])

// Escapes text and marks up its `code` the way RuboCop's messages do. The
// browser's side of code_spans in plugins/builders/helpers.rb.
export const withCode = (text) => escape(text).replace(/`([^`]+)`/g, "<code>$1</code>")
