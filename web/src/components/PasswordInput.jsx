import React, { useState } from "react";

export default function PasswordInput(props) {
  const [show, setShow] = useState(false);
  return (
    <div className="password-input">
      <input type={show ? "text" : "password"} {...props} />
      <button
        type="button"
        className="password-input__toggle"
        title={show ? "Hide password" : "Show password"}
        aria-label={show ? "Hide password" : "Show password"}
        onMouseDown={(e) => e.preventDefault()}
        onClick={() => setShow((s) => !s)}
      >
        <span className="icon">{show ? "visibility_off" : "visibility"}</span>
      </button>
    </div>
  );
}
