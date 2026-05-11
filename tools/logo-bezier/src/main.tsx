import { useState } from "react";
import { createRoot } from "react-dom/client";
import App from "./App";
import ThreeDMode from "./ThreeDMode";
import "./styles.css";

const root = document.getElementById("root");

function RootSwitch() {
  const [mode, setMode] = useState<"2d" | "3d">("2d");

  return (
    <>
      <div className="mode-switch">
        <button
          type="button"
          className={mode === "2d" ? "is-active" : ""}
          onClick={() => setMode("2d")}
        >
          2D Studio
        </button>
        <button
          type="button"
          className={mode === "3d" ? "is-active" : ""}
          onClick={() => setMode("3d")}
        >
          3D Mode
        </button>
      </div>
      {mode === "2d" ? <App /> : <ThreeDMode />}
    </>
  );
}

if (root) {
  createRoot(root).render(<RootSwitch />);
}
